import XCTest
@testable import FreeLLMAPConnect

final class GatewayURLTests: XCTestCase {
    func testNormalizesMissingSchemeAndV1Suffix() throws {
        let url = try GatewayURL.normalize("freellmapi.example.com/v1/")
        XCTAssertEqual(url.absoluteString, "https://freellmapi.example.com")
    }

    func testNormalizesCopiedLegacyDashboardURL() throws {
        let url = try GatewayURL.normalize("http://87.106.131.211:20128/home")
        XCTAssertEqual(url.absoluteString, "http://87.106.131.211:20128")
    }

    func testRejectsHostlessURL() {
        XCTAssertThrowsError(try GatewayURL.normalize("not a url"))
    }
}
