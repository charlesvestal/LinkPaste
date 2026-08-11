import AppKit
import XCTest
@testable import LinkPasteCore

/// These run against a private named pasteboard, never the user's clipboard.
final class PasteboardSnapshotTests: XCTestCase {

    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("app.linkpaste.tests.\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    func testRestoresPlainText() {
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("clobbered", forType: .string)
        XCTAssertEqual(pasteboard.string(forType: .string), "clobbered")

        snapshot.restore(to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "original clipboard")
    }

    func testRestoresAllTypesOnAnItem() throws {
        let rtf = try XCTUnwrap(
            NSAttributedString(string: "styled").rtf(from: NSRange(location: 0, length: 6), documentAttributes: [:])
        )

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("styled", forType: .string)
        item.setData(rtf, forType: .rtf)
        pasteboard.writeObjects([item])

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("clobbered", forType: .string)

        snapshot.restore(to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "styled")
        XCTAssertEqual(pasteboard.data(forType: .rtf), rtf)
    }

    func testRestoresMultipleItems() {
        pasteboard.clearContents()
        let first = NSPasteboardItem()
        first.setString("one", forType: .string)
        let second = NSPasteboardItem()
        second.setString("two", forType: .string)
        pasteboard.writeObjects([first, second])

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("clobbered", forType: .string)

        snapshot.restore(to: pasteboard)
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 2)
        XCTAssertEqual(pasteboard.pasteboardItems?.first?.string(forType: .string), "one")
    }

    func testRestoringAnEmptySnapshotLeavesAnEmptyPasteboard() {
        pasteboard.clearContents()
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.setString("clobbered", forType: .string)
        snapshot.restore(to: pasteboard)

        XCTAssertNil(pasteboard.string(forType: .string))
    }
}
