import Foundation

/// Configuration for talking to the Frame.io V4 API via Adobe IMS OAuth 2.0.
///
/// The `clientID` is created by the user in the Adobe Developer Console
/// (https://developer.adobe.com/console) after adding the Frame.io API to a project
/// and registering the redirect URI below. It is read from `UserDefaults` so it can
/// be entered in Settings without rebuilding; a build-time default can also be baked
/// in via the `SPOOL_ADOBE_CLIENT_ID` Info.plist value.
struct FrameIOConfig {
    // MARK: API

    /// Frame.io V4 REST base. All resource calls hang off this.
    static let apiBaseURL = URL(string: "https://api.frame.io/v4")!

    // MARK: Adobe IMS OAuth endpoints

    static let authorizeURL = URL(string: "https://ims-na1.adobelogin.com/ims/authorize/v2")!
    static let tokenURL = URL(string: "https://ims-na1.adobelogin.com/ims/token/v3")!

    /// The OAuth redirect URI. This MUST exactly match the Redirect URI registered on
    /// your Adobe Developer Console credential. Adobe "OAuth Native App" credentials
    /// generate one of the form `adobe+<hash>://adobeid/<client_id>` — paste that here
    /// (Settings) rather than relying on the `spool://` default.
    ///
    /// Note: `ASWebAuthenticationSession` intercepts this callback itself, so the
    /// scheme does NOT need to be registered in Info.plist.
    private static let redirectURIDefaultsKey = "SpoolRedirectURI"

    static var redirectURI: String {
        get {
            if let v = UserDefaults.standard.string(forKey: redirectURIDefaultsKey), !v.isEmpty {
                return v
            }
            return "spool://oauth-callback"
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: redirectURIDefaultsKey) }
    }

    /// The URL scheme portion of `redirectURI` (everything before `://`), used as the
    /// `callbackURLScheme` for `ASWebAuthenticationSession`.
    static var callbackScheme: String {
        guard let range = redirectURI.range(of: "://") else { return redirectURI }
        return String(redirectURI[redirectURI.startIndex..<range.lowerBound])
    }

    /// Scopes requested from IMS. `openid`/`profile`/`email` identify the user and
    /// `offline_access` is required to receive a refresh token. `additional_info.roles`
    /// is commonly needed for Frame.io account/role resolution.
    static let scopes = [
        "openid",
        "AdobeID",
        "offline_access",
        "profile",
        "email",
        "additional_info.roles",
    ]

    // MARK: Client ID resolution

    private static let clientIDDefaultsKey = "SpoolAdobeClientID"

    /// The Adobe IMS client (API) ID. Falls back to a value baked into Info.plist.
    static var clientID: String {
        get {
            if let v = UserDefaults.standard.string(forKey: clientIDDefaultsKey), !v.isEmpty {
                return v
            }
            return (Bundle.main.object(forInfoDictionaryKey: "SPOOL_ADOBE_CLIENT_ID") as? String) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: clientIDDefaultsKey)
        }
    }

    static var isConfigured: Bool { !clientID.isEmpty }
}
