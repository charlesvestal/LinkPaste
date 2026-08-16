import AppKit
import SwiftUI

/// Wires the pieces together and owns the Settings window. Everything with real
/// behavior lives elsewhere; this file should stay readable as a summary of how
/// the app is assembled.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let settings = Settings()
    private let permissions = PermissionsMonitor()
    private let eventTap = EventTapController()
    private let menuBar = MenuBarController()

    private var engine: PasteEngine!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine = PasteEngine(settings: settings)
        engine.onOutcome = { [weak self] outcome in
            self?.settings.lastOutcomeDescription = outcome.description
        }

        eventTap.shouldInterceptCommandV = { [weak self] in
            self?.engine.shouldIntercept() ?? false
        }

        menuBar.onOpenSettings = { [weak self] in self?.showSettings() }
        menuBar.onToggleEnabled = { [weak self] in
            guard let self else { return }
            settings.isEnabled.toggle()
            refreshMenuBar()
        }

        permissions.onChange = { [weak self] trusted in
            guard let self else { return }
            trusted ? startTap() : eventTap.stop()
            refreshMenuBar()
        }
        permissions.start()

        if permissions.isTrusted {
            startTap()
        } else {
            permissions.requestAccess()
            showSettings()
        }
        refreshMenuBar()
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

    private func refreshMenuBar() {
        let state: MenuBarController.State =
            !permissions.isTrusted ? .needsPermission
            : settings.isEnabled ? .active
            : .paused
        menuBar.update(state: state, isEnabled: settings.isEnabled)
    }

    // MARK: - Settings window

    private static let settingsWindowSize = NSSize(width: 480, height: 560)

    private func showSettings() {
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeSettingsWindow() -> NSWindow {
        // Two ways to collapse this window to an invisible sliver, both of which
        // this app shipped with at some point:
        //
        //  1. Assigning `window.styleMask` *after* the contentViewController is
        //     attached — AppKit recomputes the frame and it becomes ~1x32 points.
        //  2. Assigning `contentViewController` after init — that resizes the
        //     window to the controller's fitting size, which is zero before the
        //     SwiftUI view has been laid out.
        //
        // So: let NSWindow(contentViewController:) build the window and its
        // default style mask, drive the size through preferredContentSize, and
        // never touch styleMask. Both failures are silent — the window reports
        // isVisible == true while being invisible — so verify by size, not by
        // whether the call appeared to succeed.
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, permissions: permissions))
        hosting.preferredContentSize = Self.settingsWindowSize

        let window = NSWindow(contentViewController: hosting)
        window.title = "LinkPaste"
        window.isReleasedWhenClosed = false
        window.setContentSize(Self.settingsWindowSize)
        window.minSize = NSSize(width: 460, height: 380)
        window.center()
        return window
    }
}
