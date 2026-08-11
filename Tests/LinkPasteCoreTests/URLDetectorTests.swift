import XCTest
@testable import LinkPasteCore

final class URLDetectorTests: XCTestCase {

    private func assertLinks(_ input: String, to expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let result = URLDetector.detect(in: input)
        XCTAssertEqual(result?.absoluteString, expected, "expected \(input) to link to \(expected)", file: file, line: line)
    }

    private func assertIgnored(_ input: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(URLDetector.detect(in: input), "expected \(input) to be ignored", file: file, line: line)
    }

    // MARK: - Explicit schemes

    func testAcceptsCommonWebSchemes() {
        assertLinks("https://example.com", to: "https://example.com")
        assertLinks("http://example.com/a/b?c=d#e", to: "http://example.com/a/b?c=d#e")
        assertLinks("HTTPS://EXAMPLE.COM", to: "HTTPS://EXAMPLE.COM")
        assertLinks("ftp://files.example.org/pub", to: "ftp://files.example.org/pub")
    }

    func testAcceptsAppSchemes() {
        assertLinks("slack://channel?team=T1&id=C1", to: "slack://channel?team=T1&id=C1")
        assertLinks("zoommtg://zoom.us/join?confno=1", to: "zoommtg://zoom.us/join?confno=1")
    }

    func testAcceptsAuthorityFreeSchemes() {
        assertLinks("mailto:someone@example.com", to: "mailto:someone@example.com")
        assertLinks("tel:+15551234567", to: "tel:+15551234567")
    }

    func testRejectsUnknownAuthorityFreeSchemes() {
        // These read as scheme:payload but are far more likely to be code or prose.
        assertIgnored("note:remember this")  // also caught by the whitespace rule
        assertIgnored("Foo:Bar")
        assertIgnored("TODO:fix")
    }

    func testRejectsEmptySchemePayload() {
        assertIgnored("https://")
        assertIgnored("mailto:")
    }

    // MARK: - Bare hosts

    func testAcceptsBareDomains() {
        assertLinks("example.com", to: "https://example.com")
        assertLinks("www.example.com", to: "https://www.example.com")
        assertLinks("sub.domain.co.uk/path?q=1", to: "https://sub.domain.co.uk/path?q=1")
        assertLinks("my-site.dev", to: "https://my-site.dev")
        assertLinks("openai.com/research", to: "https://openai.com/research")
    }

    func testRejectsProseAndVersionNumbers() {
        // The whole reason the bare-host rule is conservative.
        assertIgnored("Version 2.0")
        assertIgnored("2.0")
        assertIgnored("see fig.3")
        assertIgnored("fig.3")
        assertIgnored("Mr. Smith")
        assertIgnored("etc.")
        assertIgnored("...")
    }

    func testRejectsFilenamesThatLookLikeDomains() {
        // .md, .sh, .py, .ts are all real ccTLDs. Linking README.md would be
        // the single most annoying possible false positive.
        assertIgnored("README.md")
        assertIgnored("build.sh")
        assertIgnored("main.py")
        assertIgnored("index.ts")
        assertIgnored("styles.css")
        assertIgnored("package.json")
        assertIgnored("photo.png")
    }

    func testRejectsMultiWordStrings() {
        assertIgnored("visit example.com today")
        assertIgnored("https://example.com and more")
        assertIgnored("hello world")
    }

    func testRejectsHostsWithPortsOrCredentials() {
        assertIgnored("localhost:3000")
        assertIgnored("user@example.com")  // an email address, not a link target
    }

    func testRejectsMalformedHosts() {
        assertIgnored("example")
        assertIgnored(".com")
        assertIgnored("example.")
        assertIgnored("-example.com")
        assertIgnored("example-.com")
        assertIgnored("exa..mple.com")
    }

    // MARK: - Hygiene

    func testTrimsSurroundingWhitespace() {
        assertLinks("  https://example.com\n", to: "https://example.com")
        assertLinks("\texample.com  ", to: "https://example.com")
    }

    func testRejectsEmptyAndOversizedInput() {
        assertIgnored("")
        assertIgnored("   \n  ")
        assertIgnored("https://example.com/" + String(repeating: "a", count: 3000))
    }
}
