import XCTest
@testable import Spool

final class ConfigTests: XCTestCase {
    override func tearDown() {
        // Restore the default so other tests/users aren't affected.
        UserDefaults.standard.removeObject(forKey: "SpoolRedirectURI")
        super.tearDown()
    }

    func testCallbackSchemeFromAdobeNativeRedirect() {
        FrameIOConfig.redirectURI = "adobe+1bad59b7af50a6b8f928bfd615efc985e58f1d00://adobeid/e5d56229978c434fade13db7f972630d"
        XCTAssertEqual(FrameIOConfig.callbackScheme, "adobe+1bad59b7af50a6b8f928bfd615efc985e58f1d00")
    }

    func testCallbackSchemeFromSimpleScheme() {
        FrameIOConfig.redirectURI = "spool://oauth-callback"
        XCTAssertEqual(FrameIOConfig.callbackScheme, "spool")
    }

    func testUserDefaultsRedirectOverrideWins() {
        FrameIOConfig.redirectURI = "myscheme://cb"
        XCTAssertEqual(FrameIOConfig.redirectURI, "myscheme://cb")
        XCTAssertEqual(FrameIOConfig.callbackScheme, "myscheme")
    }
}
