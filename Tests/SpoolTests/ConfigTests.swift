import XCTest
@testable import Spool

final class ConfigTests: XCTestCase {
    override func tearDown() {
        // Restore the default so other tests/users aren't affected.
        UserDefaults.standard.removeObject(forKey: "SpoolRedirectURI")
        super.tearDown()
    }

    func testCallbackSchemeFromAdobeNativeRedirect() {
        // Placeholder values in the shape Adobe's "OAuth Native App" generates.
        FrameIOConfig.redirectURI = "adobe+0000000000000000000000000000000000000000://adobeid/00000000000000000000000000000000"
        XCTAssertEqual(FrameIOConfig.callbackScheme, "adobe+0000000000000000000000000000000000000000")
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
