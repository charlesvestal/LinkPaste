import AppKit
import ApplicationServices
import Foundation

/// Reads the text currently selected in the frontmost app.
///
/// Two strategies, in order of politeness:
///
/// 1. **Accessibility** — ask the focused element for `AXSelectedText`. Free, silent,
///    and reliable in native AppKit text fields.
/// 2. **⌘C probe** — synthesize a copy and watch the pasteboard's change count.
///    Universal (it's what the app itself does), but it fires a real keystroke into
///    the target and costs a few tens of milliseconds. Only used when (1) comes back
///    empty, which in practice means browser web content and stubborn Electron apps.
enum SelectionReader {

    enum Source {
        case accessibility
        case copyProbe

        var description: String {
            switch self {
            case .accessibility: "Accessibility"
            case .copyProbe: "⌘C fallback"
            }
        }
    }

    struct Result {
        let text: String
        let source: Source
    }

    /// Returns the selection, or nil if there isn't one (or we couldn't tell).
    static func read(pasteboard: NSPasteboard, allowCopyProbe: Bool, probeTimeout: TimeInterval) -> Result? {
        if let text = readViaAccessibility(), !text.isEmpty {
            return Result(text: text, source: .accessibility)
        }

        guard allowCopyProbe else { return nil }

        if let text = probeViaCopy(pasteboard: pasteboard, timeout: probeTimeout), !text.isEmpty {
            return Result(text: text, source: .copyProbe)
        }

        return nil
    }

    // MARK: - Accessibility

    static func readViaAccessibility() -> String? {
        // Electron apps ship with their accessibility tree switched off until
        // something asks for it. Poking this makes Slack, VS Code and friends
        // answer AXSelectedText without needing the ⌘C probe.
        wakeAccessibilityForFrontmostApp()

        let system = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }

        let element = unsafeDowncast(focused, to: AXUIElement.self)

        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
              let selected = selectedRef, CFGetTypeID(selected) == CFStringGetTypeID()
        else { return nil }

        return selected as? String
    }

    static func wakeAccessibilityForFrontmostApp() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    // MARK: - ⌘C probe

    /// Fires ⌘C and waits for the pasteboard to change.
    ///
    /// `changeCount` is the signal rather than the string itself: if the user's
    /// clipboard already held the same text as their selection, comparing strings
    /// would read "nothing happened" and we'd wrongly conclude there's no selection.
    static func probeViaCopy(pasteboard: NSPasteboard, timeout: TimeInterval) -> String? {
        let before = pasteboard.changeCount
        KeyPoster.postCommandC()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != before {
                return pasteboard.string(forType: .string)
            }
            usleep(8_000)  // 8ms
        }

        // No change: either nothing was selected, or the app ignores ⌘C.
        // Both mean "don't link-paste".
        return nil
    }
}
