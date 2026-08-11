import Combine
import Foundation
import LinkPasteCore
import ServiceManagement

/// User-facing settings, persisted to UserDefaults.
///
/// Read from the event tap thread, written from the main thread. The values are
/// all trivially-copyable and a torn read just means one paste behaves like the
/// previous setting, so this doesn't warrant locking.
final class Settings: ObservableObject {

    private enum Key {
        static let enabled = "isEnabled"
        static let restoreDelayMs = "restoreDelayMilliseconds"
        static let copyProbe = "allowsCopyProbe"
        static let userDenylist = "userDenylist"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.restoreDelayMs: 250,
            Key.copyProbe: true,
        ])
    }

    @Published var lastOutcomeDescription: String = "No pastes yet"

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled); objectWillChange.send() }
    }

    var allowsCopyProbe: Bool {
        get { defaults.bool(forKey: Key.copyProbe) }
        set { defaults.set(newValue, forKey: Key.copyProbe); objectWillChange.send() }
    }

    /// How long to wait after pasting before putting the user's clipboard back.
    /// Exposed because the right value is app-dependent and we can't detect it.
    var restoreDelay: TimeInterval {
        get { Double(restoreDelayMilliseconds) / 1000.0 }
    }

    var restoreDelayMilliseconds: Int {
        get {
            let stored = defaults.integer(forKey: Key.restoreDelayMs)
            return stored == 0 ? 250 : min(max(stored, 50), 2000)
        }
        set { defaults.set(newValue, forKey: Key.restoreDelayMs); objectWillChange.send() }
    }

    /// Long enough for a sluggish Electron app to answer ⌘C, short enough that a
    /// non-copying app doesn't leave the user staring at a stalled keystroke.
    var copyProbeTimeout: TimeInterval { 0.35 }

    var userDenylist: [String] {
        get { defaults.stringArray(forKey: Key.userDenylist) ?? [] }
        set { defaults.set(newValue, forKey: Key.userDenylist); objectWillChange.send() }
    }

    var policy: AppPolicy {
        AppPolicy(userDenylist: Set(userDenylist))
    }

    // MARK: - Launch at login

    var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("LinkPaste: launch-at-login change failed: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }
}
