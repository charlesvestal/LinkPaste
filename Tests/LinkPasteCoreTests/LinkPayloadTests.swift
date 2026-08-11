import AppKit
import XCTest
@testable import LinkPasteCore

final class LinkPayloadTests: XCTestCase {

    private let url = URL(string: "https://example.com/page")!

    func testBuildsAllThreeFlavors() throws {
        let payload = try XCTUnwrap(LinkPayloadBuilder.build(text: "the docs", url: url))
        XCTAssertFalse(payload.rtf.isEmpty)
        XCTAssertFalse(payload.html.isEmpty)
        XCTAssertEqual(payload.plain, "the docs")
    }

    func testPlainFallbackIsTheTextNotTheURL() throws {
        // A plain-text field that ignores our rich flavors should end up with the
        // text unchanged — a harmless no-op, not a URL dumped over the selection.
        let payload = try XCTUnwrap(LinkPayloadBuilder.build(text: "the docs", url: url))
        XCTAssertEqual(payload.plain, "the docs")
        XCTAssertFalse(payload.plain.contains("example.com"))
    }

    func testRTFRoundTripsToALinkedString() throws {
        let payload = try XCTUnwrap(LinkPayloadBuilder.build(text: "the docs", url: url))
        let restored = try XCTUnwrap(NSAttributedString(rtf: payload.rtf, documentAttributes: nil))

        XCTAssertEqual(restored.string, "the docs")

        var range = NSRange()
        let link = restored.attribute(.link, at: 0, effectiveRange: &range)
        XCTAssertNotNil(link, "RTF should carry a link attribute")
        XCTAssertEqual(range.length, restored.length, "the whole run should be linked")

        let linkedURL = (link as? URL) ?? URL(string: (link as? String) ?? "")
        XCTAssertEqual(linkedURL?.absoluteString, url.absoluteString)
    }

    func testHTMLContainsAnAnchorToTheURL() throws {
        let payload = try XCTUnwrap(LinkPayloadBuilder.build(text: "the docs", url: url))
        let html = try XCTUnwrap(String(data: payload.html, encoding: .utf8))
        XCTAssertTrue(html.contains("example.com/page"), "HTML flavor should reference the URL: \(html)")
        XCTAssertTrue(html.contains("the docs"), "HTML flavor should contain the visible text")
    }

    func testHandlesMultilineAndUnicodeSelections() throws {
        let payload = try XCTUnwrap(LinkPayloadBuilder.build(text: "erste Zeile\nzweite Zeile — ü", url: url))
        let restored = try XCTUnwrap(NSAttributedString(rtf: payload.rtf, documentAttributes: nil))
        XCTAssertEqual(restored.string, "erste Zeile\nzweite Zeile — ü")
    }

    func testHandlesTextWithRTFControlCharacters() throws {
        // Backslashes and braces are RTF syntax; AppKit must escape them for us.
        let payload = try XCTUnwrap(LinkPayloadBuilder.build(text: #"a\b{c}d"#, url: url))
        let restored = try XCTUnwrap(NSAttributedString(rtf: payload.rtf, documentAttributes: nil))
        XCTAssertEqual(restored.string, #"a\b{c}d"#)
    }
}
