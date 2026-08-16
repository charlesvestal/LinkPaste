import AppKit
import XCTest
@testable import LinkPasteCore

/// These run against a private named pasteboard, never the user's clipboard.
///
/// Reading a promised flavor in-process goes through the same resolution path a
/// paste in another app does — AppKit calls the data provider either way — so
/// these exercise the real detection mechanism rather than a stand-in for it.
final class PromisedPasteTests: XCTestCase {

    private var pasteboard: NSPasteboard!

    private let rtf = Data("rich".utf8)
    private let html = Data("<a href=\"https://example.com\">text</a>".utf8)
    private let plain = Data("https://example.com".utf8)

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("app.linkpaste.tests.\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    private func makePaste() -> PromisedPaste {
        PromisedPaste(payloads: [.rtf: rtf, .html: html, .string: plain])
    }

    func testDeclaresEveryFlavorItPromises() {
        let paste = makePaste()
        XCTAssertTrue(paste.write(to: pasteboard))

        let types = pasteboard.types ?? []
        XCTAssertTrue(types.contains(.rtf))
        XCTAssertTrue(types.contains(.html))
        XCTAssertTrue(types.contains(.string))
    }

    func testServesTheFlavorThatIsAskedFor() {
        let paste = makePaste()
        paste.write(to: pasteboard)

        XCTAssertEqual(pasteboard.data(forType: .rtf), rtf)
        XCTAssertEqual(pasteboard.data(forType: .string), plain)
    }

    func testNoVerdictBeforeAnythingReads() {
        let paste = makePaste()
        paste.write(to: pasteboard)

        // Silence must not be read as "plain" — a ⌘V that never landed in a text
        // field would otherwise teach the ledger something false.
        XCTAssertNil(paste.observedKind)
    }

    func testReadingRichTextIsJudgedRich() {
        let paste = makePaste()
        paste.write(to: pasteboard)

        _ = pasteboard.data(forType: .rtf)
        XCTAssertEqual(paste.observedKind, .rich)
    }

    func testReadingHTMLIsJudgedRich() {
        let paste = makePaste()
        paste.write(to: pasteboard)

        _ = pasteboard.data(forType: .html)
        XCTAssertEqual(paste.observedKind, .rich)
    }

    func testReadingPlainTextIsJudgedPlain() {
        let paste = makePaste()
        paste.write(to: pasteboard)

        _ = pasteboard.data(forType: .string)
        XCTAssertEqual(paste.observedKind, .plain)
    }

    func testRichWinsWhenAnAppReadsPlainTextFirst() {
        // Some editors check for plain text before taking the rich flavor. Judging
        // on the first read alone would file them under plain and stop linking there.
        let paste = makePaste()
        paste.write(to: pasteboard)

        _ = pasteboard.data(forType: .string)
        _ = pasteboard.data(forType: .rtf)
        XCTAssertEqual(paste.observedKind, .rich)
    }

    func testWaitReturnsOnceAFlavorIsRead() {
        let paste = makePaste()
        paste.write(to: pasteboard)

        // The wait goes on a background queue and the read stays here, mirroring
        // the app: the destination's read is answered on the main run loop, so a
        // waiter that blocked it would be waiting on itself.
        let returned = expectation(description: "waitForRead returned")
        var kind: DestinationKind?
        DispatchQueue.global().async {
            kind = paste.waitForRead(timeout: 5, settle: 0.01)
            returned.fulfill()
        }

        // Long enough for the waiter to actually be waiting when the read lands.
        Thread.sleep(forTimeInterval: 0.05)
        _ = pasteboard.data(forType: .rtf)

        // Comfortably inside waitForRead's own 5s timeout, so finishing at all
        // proves it returned on the read rather than timing out.
        wait(for: [returned], timeout: 3)
        XCTAssertEqual(kind, .rich)
    }

    func testWaitGivesUpWhenNothingReads() {
        let paste = makePaste()
        paste.write(to: pasteboard)

        XCTAssertNil(paste.waitForRead(timeout: 0.1, settle: 0))
    }

    func testStillOwnsPasteboardUntilSomethingElseWrites() {
        let paste = makePaste()
        paste.write(to: pasteboard)
        XCTAssertTrue(paste.stillOwnsPasteboard(pasteboard))

        pasteboard.clearContents()
        pasteboard.setString("someone else's copy", forType: .string)

        // Restoring a snapshot over this would destroy what the user just copied.
        XCTAssertFalse(paste.stillOwnsPasteboard(pasteboard))
    }

    func testWritingNothingIsRefused() {
        let empty = PromisedPaste(payloads: [:])
        XCTAssertFalse(empty.write(to: pasteboard))
    }
}
