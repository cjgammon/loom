import XCTest
@testable import Spool

final class PKCETests: XCTestCase {
    func testChallengeIsDeterministicForVerifier() {
        // Known vector from RFC 7636 Appendix B.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        XCTAssertEqual(PKCE.challenge(for: verifier), expectedChallenge)
    }

    func testGeneratedVerifierIsURLSafeAndUnpadded() {
        let pkce = PKCE()
        XCTAssertFalse(pkce.verifier.contains("="))
        XCTAssertFalse(pkce.verifier.contains("+"))
        XCTAssertFalse(pkce.verifier.contains("/"))
        XCTAssertGreaterThanOrEqual(pkce.verifier.count, 43)
        XCTAssertEqual(pkce.method, "S256")
    }

    func testBase64URLEncodingStripsPadding() {
        let encoded = PKCE.base64URLEncode(Data([0xFB, 0xFF]))
        XCTAssertFalse(encoded.contains("="))
    }
}
