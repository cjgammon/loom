import Foundation
import CryptoKit

/// PKCE (RFC 7636) verifier/challenge pair for the OAuth authorization-code flow.
///
/// Kept free of UIKit/AppKit so it can be unit-tested on its own.
struct PKCE: Equatable {
    let verifier: String
    let challenge: String
    let method = "S256"

    init(verifier: String = PKCE.makeVerifier()) {
        self.verifier = verifier
        self.challenge = PKCE.challenge(for: verifier)
    }

    /// Generate a high-entropy code verifier (43–128 chars, URL-safe).
    static func makeVerifier(byteCount: Int = 64) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URLEncode(Data(bytes))
    }

    /// S256 challenge = BASE64URL(SHA256(verifier)).
    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    /// Base64-URL encoding without padding, per the PKCE spec.
    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
