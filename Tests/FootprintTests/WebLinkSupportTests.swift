import XCTest
@testable import Footprint

final class WebLinkSupportTests: XCTestCase {
    func testMailtoRejectsEncodedHeaderInjection() {
        XCTAssertNil(normalizedWebLinkURL("mailto:test@example.com%0ABcc:other@example.com"))
        XCTAssertNil(normalizedWebLinkURL("mailto:test@example.com%0D%0ABcc:other@example.com"))
    }

    func testExternalURLPolicyAllowsOnlySupportedSchemes() {
        XCTAssertNotNil(normalizedWebLinkURL("https://example.com/path"))
        XCTAssertNotNil(normalizedWebLinkURL("mailto:test@example.com"))
        XCTAssertNil(normalizedWebLinkURL("file:///etc/passwd"))
        XCTAssertNil(normalizedWebLinkURL("javascript:alert(1)"))
    }
}
