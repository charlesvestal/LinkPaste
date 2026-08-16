import XCTest
@testable import LinkPasteCore

final class AppPolicyTests: XCTestCase {

    func testAllowsOrdinaryApps() {
        let policy = AppPolicy()
        XCTAssertTrue(policy.allowsLinkPaste(bundleID: "com.apple.mail"))
        XCTAssertTrue(policy.allowsLinkPaste(bundleID: "com.tinyspeck.slackmacgap"))
        XCTAssertTrue(policy.allowsLinkPaste(bundleID: "notion.id"))
    }

    func testDeniesTerminalsAndEditors() {
        let policy = AppPolicy()
        XCTAssertFalse(policy.allowsLinkPaste(bundleID: "com.apple.Terminal"))
        XCTAssertFalse(policy.allowsLinkPaste(bundleID: "com.microsoft.VSCode"))
        XCTAssertFalse(policy.allowsLinkPaste(bundleID: "com.apple.dt.Xcode"))
    }

    func testDeniesPasswordManagers() {
        let policy = AppPolicy()
        // These matter most: the ⌘C probe would put a credential on the clipboard.
        XCTAssertFalse(policy.allowsLinkPaste(bundleID: "com.1password.1password"))
        XCTAssertFalse(policy.allowsLinkPaste(bundleID: "com.bitwarden.desktop"))
    }

    func testPrefixEntriesMatchWholeFamilies() {
        let policy = AppPolicy()
        XCTAssertFalse(policy.allowsLinkPaste(bundleID: "com.jetbrains.intellij"))
        XCTAssertFalse(policy.allowsLinkPaste(bundleID: "com.jetbrains.pycharm.ce"))
        // Prefix matching must not swallow a merely similar-looking ID.
        XCTAssertTrue(policy.allowsLinkPaste(bundleID: "com.jetbrainsfanclub.app"))
    }

    func testMatchingIsCaseInsensitive() {
        let policy = AppPolicy()
        XCTAssertFalse(policy.allowsLinkPaste(bundleID: "COM.APPLE.TERMINAL"))
    }

    func testUserDenylistIsHonored() {
        let policy = AppPolicy(userDenylist: ["com.example.CustomApp"])
        XCTAssertFalse(policy.allowsLinkPaste(bundleID: "com.example.CustomApp"))
    }

    func testUnknownAppIsDenied() {
        // No bundle ID means no way to reason about the target, so don't gamble.
        let policy = AppPolicy()
        XCTAssertFalse(policy.allowsLinkPaste(bundleID: nil))
        XCTAssertFalse(policy.allowsLinkPaste(bundleID: ""))
    }

    func testMarkdownListHasNoBuiltInMembers() {
        // Whether markdown mode applies is a per-user in-app setting, not a
        // property of the app itself — so there's nothing safe to default.
        let policy = AppPolicy()
        XCTAssertFalse(policy.usesMarkdownLinks(bundleID: "com.tinyspeck.slackmacgap"))
    }

    func testMarkdownListIsHonored() {
        let policy = AppPolicy(markdownList: ["com.tinyspeck.slackmacgap"])
        XCTAssertTrue(policy.usesMarkdownLinks(bundleID: "com.tinyspeck.slackmacgap"))
        XCTAssertFalse(policy.usesMarkdownLinks(bundleID: "com.apple.mail"))
    }

    func testMarkdownListMatchesPrefixesAndIsCaseInsensitive() {
        let policy = AppPolicy(markdownList: ["com.jetbrains."])
        XCTAssertTrue(policy.usesMarkdownLinks(bundleID: "COM.JETBRAINS.INTELLIJ"))
        XCTAssertFalse(policy.usesMarkdownLinks(bundleID: "com.jetbrainsfanclub.app"))
    }

    func testMarkdownListDoesNotAffectDenylist() {
        let policy = AppPolicy(markdownList: ["com.tinyspeck.slackmacgap"])
        XCTAssertTrue(policy.allowsLinkPaste(bundleID: "com.tinyspeck.slackmacgap"))
    }

    func testMarkdownListRejectsUnknownApp() {
        let policy = AppPolicy(markdownList: ["com.tinyspeck.slackmacgap"])
        XCTAssertFalse(policy.usesMarkdownLinks(bundleID: nil))
        XCTAssertFalse(policy.usesMarkdownLinks(bundleID: ""))
    }
}
