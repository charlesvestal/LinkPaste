import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let settings = Settings()
    private let permissions = PermissionsMonitor()
    private let eventTap = EventTapController()
    private var engine: PasteEngine!

    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine = PasteEngine(settings: settings)
        engine.onOutcome = { [weak self] outcome in
            self?.settings.lastOutcomeDescription = Self.describe(outcome)
        }

        eventTap.shouldInterceptCommandV = { [weak self] in
            self?.engine.shouldIntercept() ?? false
        }

        permissions.onChange = { [weak self] trusted in
            trusted ? self?.startTap() : self?.eventTap.stop()
            self?.updateStatusIcon()
        }
        permissions.start()

        setUpStatusItem()

        if permissions.isTrusted {
            startTap()
        } else {
            permissions.requestAccess()
            showSettings(nil)
        }
        updateStatusIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap.stop()
        permissions.stop()
    }

    private func startTap() {
        if !eventTap.start() {
            NSLog("LinkPaste: could not create event tap — Accessibility permission is probably stale.")
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        let toggle = menu.addItem(
            withTitle: "Enable Link Pasting",
            action: #selector(toggleEnabled(_:)),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit LinkPaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        menu.delegate = self
        statusItem.menu = menu
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let healthy = permissions.isTrusted && settings.isEnabled
        let symbol = healthy ? "link" : "link.badge.plus"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "LinkPaste")
        button.appearsDisabled = !healthy
        button.toolTip = permissions.isTrusted
            ? (settings.isEnabled ? "LinkPaste is active" : "LinkPaste is paused")
            : "LinkPaste needs Accessibility access"
    }

    @objc private func toggleEnabled(_ sender: Any?) {
        settings.isEnabled.toggle()
        updateStatusIcon()
    }

    @objc private func showSettings(_ sender: Any?) {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(settings: settings, permissions: permissions))
        let window = NSWindow(contentViewController: hosting)
        window.title = "LinkPaste"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func describe(_ outcome: PasteEngine.Outcome) -> String {
        switch outcome {
        case let .linked(text, url, source):
            let via = source == .accessibility ? "Accessibility" : "⌘C fallback"
            return "Linked “\(text)” → \(url.absoluteString) (via \(via))"
        case let .passedThrough(reason):
            return "Pasted normally — \(reason)"
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTitle: "Enable Link Pasting")?.state = settings.isEnabled ? .on : .off
    }
}
