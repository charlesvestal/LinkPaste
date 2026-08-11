import Combine
import Foundation
import LinkPasteCore
import ServiceManagement

/// User-facing settings, persisted to UserDefaults.
///
/// Values are read from the event-tap thread and written from the main thread.
/// They're all trivially copyable, and a torn read only means one paste behaves
/// like the previous setting, so this doesn't warrant locking.
final class Settings: ObservableObject {

    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Key.enabled) } }

    @Published var allowsCopyProbe: Bool { didSet { defaults.set(allowsCopyProbe, forKey: Key.copyProbe) } }

    /// How long to wait after pasting before restoring the user's clipboard.
    /// Exposed to the user because the right value is app-dependent and there's
    /// no signal from the target app to detect it.
    @Published var restoreDelayMilliseconds: Int {
        didSet { defaults.set(restoreDelayMilliseconds, forKey: Key.restoreDelay) }
    }

    @Published var userDenylist: [String] { didSet { defaults.set(userDenylist, forKey: Key.denylist) } }

    /// What happened on the last ⌘V, shown in Settings so the app can explain
    /// itself when it decides *not* to link something.
    @Published var lastOutcomeDescription = "No pastes yet"

    @Published private(set) var launchesAtLogin: Bool
    /// Set when registering the login item fails, so the toggle doesn't silently
    /// lie about a state the system rejected.
    @Published private(set) var launchAtLoginFailure: String?

    static let delayRange = 50...2000
    static let defaultDelay = 250

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        allowsCopyProbe = defaults.object(forKey: Key.copyProbe) as? Bool ?? true
        let storedDelay = defaults.object(forKey: Key.restoreDelay) as? Int ?? Self.defaultDelay
        restoreDelayMilliseconds = storedDelay.clamped(to: Self.delayRange)
        userDenylist = defaults.stringArray(forKey: Key.denylist) ?? []
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Derived values

    var restoreDelay: TimeInterval { Double(restoreDelayMilliseconds) / 1000 }

    /// Long enough for a sluggish Electron app to answer ⌘C, short enough that an
    /// app which never copies doesn't leave the user staring at a stalled keystroke.
    var copyProbeTimeout: TimeInterval { 0.35 }

    var policy: AppPolicy { AppPolicy(userDenylist: Set(userDenylist)) }

    /// Bundle IDs excluded without the user having to configure anything.
    var builtInDenylist: [String] { AppPolicy.defaultDenylist.sorted() }

    // MARK: - Denylist editing

    func addToDenylist(_ rawEntry: String) {
        let entry = rawEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty, !userDenylist.contains(entry) else { return }
        userDenylist.append(entry)
    }

    func removeFromDenylist(_ entry: String) {
        userDenylist.removeAll { $0 == entry }
    }

    // MARK: - Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginFailure = nil
        } catch {
            // Registering fails for unsigned or non-/Applications builds. Surface
            // it rather than leaving the toggle showing a state that isn't real.
            launchAtLoginFailure = error.localizedDescription
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    private enum Key {
        static let enabled = "isEnabled"
        static let copyProbe = "allowsCopyProbe"
        static let restoreDelay = "restoreDelayMilliseconds"
        static let denylist = "userDenylist"
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
