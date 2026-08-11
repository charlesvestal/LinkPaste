import AppKit
import ApplicationServices
import Combine
import Foundation

/// Watches Accessibility permission, which this app cannot function without.
///
/// Trust is keyed to the app's designated requirement (bundle ID + Team ID), so
/// it survives ordinary updates signed with the same identity. It is dropped when
/// that identity changes — and, because an ad-hoc signature is identified by its
/// hash, on every rebuild of a locally-signed development build.
///
/// Either way the failure is silent: the event tap simply refuses to be created
/// and ⌘V quietly goes back to normal. Polling is what lets the menu bar say so
/// out loud instead of the app looking dead.
final class PermissionsMonitor: ObservableObject {

    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()

    /// Called when trust flips, so the app can start or stop the tap.
    var onChange: ((Bool) -> Void)?

    private var timer: Timer?

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let trusted = AXIsProcessTrusted()
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        onChange?(trusted)
    }

    /// Shows the system prompt. Only does anything the first time; afterwards
    /// macOS silently ignores it, which is why `openSettings()` exists.
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
