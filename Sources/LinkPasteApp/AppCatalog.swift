import AppKit
import UniformTypeIdentifiers

/// An app the user can recognize: icon and name, not just a bundle identifier.
///
/// The denylist is stored as bundle IDs because that's what the event tap can
/// match against, but nobody should have to *type* one. This turns the stored
/// identifiers back into something readable, and offers the two natural ways to
/// pick an app: one that's running, or one on disk.
struct AppInfo: Identifiable, Hashable {
    let bundleID: String
    let name: String

    var id: String { bundleID }

    /// Looked up lazily — icons are expensive and irrelevant to equality.
    var icon: NSImage? { AppCatalog.icon(forBundleID: bundleID) }
}

enum AppCatalog {

    /// Apps with a normal UI presence, minus LinkPaste itself. Agents and
    /// background helpers are excluded: you can't paste into them, so listing
    /// them would just make the menu long.
    static func runningApps() -> [AppInfo] {
        let ownBundleID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier, bundleID != ownBundleID else { return nil }
                return AppInfo(bundleID: bundleID, name: app.localizedName ?? bundleID)
            }
            .uniqued(by: \.bundleID)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Resolves a stored bundle ID back to a display name. Falls back to the
    /// identifier itself, so an entry for an uninstalled app still reads sensibly
    /// rather than disappearing.
    static func displayName(forBundleID bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return url.appDisplayName
    }

    static func icon(forBundleID bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Asks the user to pick an application, and returns its bundle identifier.
    /// Returns nil if they cancel or pick something without one.
    @MainActor
    static func chooseApplication() -> AppInfo? {
        let panel = NSOpenPanel()
        panel.title = "Choose an app to exclude"
        panel.prompt = "Exclude"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier
        else { return nil }

        return AppInfo(bundleID: bundleID, name: url.appDisplayName)
    }
}

private extension URL {
    /// `displayName(atPath:)` keeps the ".app" extension when the user has
    /// "show all filename extensions" on, which reads as a file path rather than
    /// an app name next to running apps listed as plain "Safari".
    var appDisplayName: String {
        let name = FileManager.default.displayName(atPath: path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

private extension Sequence {
    /// First occurrence wins. A single app can have several running instances.
    func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen: Set<Key> = []
        return filter { seen.insert(key($0)).inserted }
    }
}
