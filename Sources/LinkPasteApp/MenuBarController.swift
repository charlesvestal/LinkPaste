import AppKit

/// The menu bar item: LinkPaste's only always-visible surface.
///
/// Split out of `AppDelegate` because it owns real state — the status item, its
/// menu, and the mapping from app health to what the icon shows — and because
/// building a menu inline makes the delegate read like a script instead of a
/// description of the app.
final class MenuBarController {

    /// What the menu bar should currently communicate.
    enum State {
        case active
        case paused
        case needsPermission

        var symbol: String {
            switch self {
            case .active: "link"
            case .paused: "pause.circle"
            case .needsPermission: "exclamationmark.triangle.fill"
            }
        }

        /// Spoken by VoiceOver and shown on hover. The icon alone can't say this.
        var description: String {
            switch self {
            case .active: "LinkPaste is active"
            case .paused: "LinkPaste is paused"
            case .needsPermission: "LinkPaste needs Accessibility access"
            }
        }
    }

    var onOpenSettings: () -> Void = {}
    var onToggleEnabled: () -> Void = {}

    private let statusItem: NSStatusItem
    private let enableItem: NSMenuItem
    private let statusMessageItem: NSMenuItem

    private var state: State = .needsPermission
    private var isEnabled = true

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Held as properties rather than looked up by title later: title lookups
        // break silently the moment a word changes.
        statusMessageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusMessageItem.isEnabled = false
        enableItem = NSMenuItem(title: "Enable Link Pasting", action: nil, keyEquivalent: "")

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        menu.addItem(statusMessageItem)
        menu.addItem(.separator())

        enableItem.target = self
        enableItem.action = #selector(toggleEnabled)
        menu.addItem(enableItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit LinkPaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    /// Single entry point for refreshing everything the menu bar displays.
    func update(state: State, isEnabled: Bool) {
        self.state = state
        self.isEnabled = isEnabled

        enableItem.state = isEnabled ? .on : .off
        statusMessageItem.title = state.description

        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: state.symbol, accessibilityDescription: state.description)
        button.toolTip = state.description
        // The image's accessibilityDescription is not what VoiceOver reads for
        // the status item — the button's own label is. Without this it announces
        // a constant "LinkPaste" in every state, including broken ones.
        button.setAccessibilityLabel(state.description)
    }

    @objc private func openSettings() { onOpenSettings() }
    @objc private func toggleEnabled() { onToggleEnabled() }
}
