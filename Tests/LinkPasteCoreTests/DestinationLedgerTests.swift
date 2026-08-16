import XCTest
@testable import LinkPasteCore

final class DestinationLedgerTests: XCTestCase {

    private let composer = DestinationContext(bundleID: "com.tinyspeck.slackmacgap", role: "AXTextArea")
    private let search = DestinationContext(bundleID: "com.tinyspeck.slackmacgap", role: "AXTextField")
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testKnowsNothingToStart() {
        let ledger = DestinationLedger()
        XCTAssertNil(ledger.kind(for: composer, now: now))
        XCTAssertEqual(ledger.count, 0)
    }

    func testRemembersWhatItObserved() {
        var ledger = DestinationLedger()
        ledger.record(.rich, for: composer, now: now)

        XCTAssertEqual(ledger.kind(for: composer, now: now), .rich)
    }

    func testRolesInTheSameAppAreSeparateDestinations() {
        // A rich composer and a plain search box share a bundle ID; treating them
        // as one destination is how a wrong verdict spreads across an app.
        var ledger = DestinationLedger()
        ledger.record(.rich, for: composer, now: now)
        ledger.record(.plain, for: search, now: now)

        XCTAssertEqual(ledger.kind(for: composer, now: now), .rich)
        XCTAssertEqual(ledger.kind(for: search, now: now), .plain)
    }

    func testWebPagesInTheSameBrowserAreSeparateDestinations() {
        let gmail = DestinationContext(bundleID: "com.google.Chrome", role: "AXTextArea", host: "mail.google.com")
        let github = DestinationContext(bundleID: "com.google.Chrome", role: "AXTextArea", host: "github.com")

        var ledger = DestinationLedger()
        ledger.record(.rich, for: gmail, now: now)

        XCTAssertEqual(ledger.kind(for: gmail, now: now), .rich)
        XCTAssertNil(ledger.kind(for: github, now: now), "a verdict for one site must not answer for another")
    }

    func testLaterObservationsWin() {
        var ledger = DestinationLedger()
        ledger.record(.rich, for: composer, now: now)
        ledger.record(.plain, for: composer, now: now)

        XCTAssertEqual(ledger.kind(for: composer, now: now), .plain)
    }

    func testVerdictsExpire() {
        var ledger = DestinationLedger(timeToLive: 60)
        ledger.record(.plain, for: composer, now: now)

        XCTAssertEqual(ledger.kind(for: composer, now: now.addingTimeInterval(59)), .plain)
        XCTAssertNil(ledger.kind(for: composer, now: now.addingTimeInterval(61)))
    }

    func testPinnedVerdictsDoNotExpire() {
        var ledger = DestinationLedger(timeToLive: 60)
        ledger.pin(.plain, for: composer, now: now)

        XCTAssertEqual(ledger.kind(for: composer, now: now.addingTimeInterval(10_000)), .plain)
        XCTAssertTrue(ledger.isPinned(composer))
    }

    func testPinnedVerdictsSurviveContraryObservations() {
        // The whole point of pinning: the user has seen something the pasteboard
        // cannot show us, so watching harder must not overrule them.
        var ledger = DestinationLedger()
        ledger.pin(.plain, for: composer, now: now)
        ledger.record(.rich, for: composer, now: now)

        XCTAssertEqual(ledger.kind(for: composer, now: now), .plain)
    }

    func testForgetAllClearsEverythingIncludingPins() {
        var ledger = DestinationLedger()
        ledger.record(.rich, for: composer, now: now)
        ledger.pin(.plain, for: search, now: now)

        ledger.forgetAll()

        XCTAssertEqual(ledger.count, 0)
        XCTAssertNil(ledger.kind(for: composer, now: now))
        XCTAssertNil(ledger.kind(for: search, now: now))
    }

    func testSurvivesAnEncodeDecodeRoundTrip() throws {
        var ledger = DestinationLedger()
        ledger.record(.rich, for: composer, now: now)
        ledger.pin(.plain, for: search, now: now)

        let restored = DestinationLedger.decoded(from: try XCTUnwrap(ledger.encoded()))

        XCTAssertEqual(restored.kind(for: composer, now: now), .rich)
        XCTAssertEqual(restored.kind(for: search, now: now), .plain)
        XCTAssertTrue(restored.isPinned(search))
    }

    func testDecodingGarbageStartsEmptyRatherThanFailing() {
        XCTAssertEqual(DestinationLedger.decoded(from: Data("not json".utf8)).count, 0)
        XCTAssertEqual(DestinationLedger.decoded(from: nil).count, 0)
    }

    func testDecodesEntriesWrittenBeforePinningExisted() throws {
        // Pinning arrived after the first ledgers were persisted; an entry without
        // the field must still load rather than dropping the whole ledger.
        let legacy = Data(#"{"com.example|AXTextArea||":{"kind":"rich","learnedAt":0}}"#.utf8)
        let ledger = DestinationLedger.decoded(from: legacy)

        let context = DestinationContext(bundleID: "com.example", role: "AXTextArea")
        XCTAssertEqual(ledger.kind(for: context, now: Date(timeIntervalSinceReferenceDate: 0)), .rich)
        XCTAssertFalse(ledger.isPinned(context))
    }
}
