import Foundation
import AuthenticationServices
import AppKit

/// Manages the Frame.io / Adobe IMS OAuth 2.0 authorization-code-with-PKCE flow and
/// the resulting token lifecycle (Keychain persistence + automatic refresh).
@MainActor
final class FrameIOAuth: NSObject, ObservableObject {
    enum AuthError: LocalizedError {
        case notConfigured
        case userCancelled
        case missingCode
        case tokenExchangeFailed(String)
        case notSignedIn

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Set your Adobe API client ID in Settings before signing in."
            case .userCancelled:
                return "Sign-in was cancelled."
            case .missingCode:
                return "The authorization response did not contain a code."
            case .tokenExchangeFailed(let detail):
                return "Token exchange failed: \(detail)"
            case .notSignedIn:
                return "You are not signed in to Frame.io."
            }
        }
    }

    @Published private(set) var isSignedIn = false

    private let keychain = KeychainStore()
    private let keychainAccount = "frameio-oauth"
    private var tokens: OAuthTokenSet? {
        didSet { isSignedIn = tokens != nil }
    }

    /// Held strong for the duration of the web auth session.
    private var webAuthSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        self.tokens = try? keychain.getValue(OAuthTokenSet.self, account: keychainAccount)
        self.isSignedIn = tokens != nil
    }

    // MARK: - Sign in

    /// Run the interactive browser sign-in. Returns once tokens are stored.
    func signIn() async throws {
        guard FrameIOConfig.isConfigured else { throw AuthError.notConfigured }

        let pkce = PKCE()
        let state = UUID().uuidString
        let code = try await authorize(pkce: pkce, state: state)
        let tokenSet = try await exchangeCode(code, pkce: pkce)
        try persist(tokenSet)
        Log.auth.info("Signed in to Frame.io.")
    }

    func signOut() {
        tokens = nil
        try? keychain.delete(account: keychainAccount)
        Log.auth.info("Signed out of Frame.io.")
    }

    // MARK: - Access token for API calls

    /// Return a valid access token, refreshing first if needed.
    func validAccessToken() async throws -> String {
        guard let current = tokens else { throw AuthError.notSignedIn }
        if !current.isExpired { return current.accessToken }

        guard let refresh = current.refreshToken else {
            // No refresh token: force re-auth.
            signOut()
            throw AuthError.notSignedIn
        }
        let refreshed = try await refreshTokens(refreshToken: refresh)
        try persist(refreshed)
        return refreshed.accessToken
    }

    // MARK: - Authorization request (browser)

    private func authorize(pkce: PKCE, state: String) async throws -> String {
        var comps = URLComponents(url: FrameIOConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: FrameIOConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: FrameIOConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: FrameIOConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "state", value: state),
        ]
        let authURL = comps.url!

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "spool"
            ) { url, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.userCancelled)
                    return
                }
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url = url else {
                    continuation.resume(throwing: AuthError.missingCode)
                    return
                }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webAuthSession = session
            if !session.start() {
                continuation.resume(throwing: AuthError.tokenExchangeFailed("Could not start auth session"))
            }
        }

        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
        // Validate state to guard against CSRF.
        guard items?.first(where: { $0.name == "state" })?.value == state else {
            throw AuthError.tokenExchangeFailed("State mismatch")
        }
        guard let code = items?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.missingCode
        }
        return code
    }

    // MARK: - Token exchange / refresh

    private func exchangeCode(_ code: String, pkce: PKCE) async throws -> OAuthTokenSet {
        var params = [
            "grant_type": "authorization_code",
            "client_id": FrameIOConfig.clientID,
            "code": code,
            "redirect_uri": FrameIOConfig.redirectURI,
            "code_verifier": pkce.verifier,
        ]
        params["scope"] = FrameIOConfig.scopes.joined(separator: " ")
        return try await postToken(params)
    }

    private func refreshTokens(refreshToken: String) async throws -> OAuthTokenSet {
        let params = [
            "grant_type": "refresh_token",
            "client_id": FrameIOConfig.clientID,
            "refresh_token": refreshToken,
            "scope": FrameIOConfig.scopes.joined(separator: " "),
        ]
        var refreshed = try await postToken(params)
        // IMS may not return a new refresh token on refresh; keep the existing one.
        if refreshed.refreshToken == nil { refreshed.refreshToken = refreshToken }
        return refreshed
    }

    private func postToken(_ params: [String: String]) async throws -> OAuthTokenSet {
        var request = URLRequest(url: FrameIOConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncoded(params).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.tokenExchangeFailed("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.tokenExchangeFailed("HTTP \(http.statusCode): \(body)")
        }

        let decoded = try JSONDecoder().decode(IMSTokenResponse.self, from: data)
        // IMS `expires_in` is sometimes milliseconds; normalize to seconds.
        let raw = decoded.expires_in ?? 3600
        let seconds = raw > 100_000 ? raw / 1000 : raw
        return OAuthTokenSet(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresIn: seconds
        )
    }

    private func persist(_ tokenSet: OAuthTokenSet) throws {
        try keychain.setValue(tokenSet, account: keychainAccount)
        tokens = tokenSet
    }

    private func formURLEncoded(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}

// MARK: - Presentation anchor

extension FrameIOAuth: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.windows.first { $0.isKeyWindow } ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
