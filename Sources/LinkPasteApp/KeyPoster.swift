import CoreGraphics
import Foundation

enum KeyCode {
    static let v: CGKeyCode = 9
    static let c: CGKeyCode = 8
}

/// Posts the synthetic keystrokes we need (⌘V to paste our payload, ⌘C to probe
/// the selection).
enum KeyPoster {

    /// Stamped into every event we generate so `EventTapController` can recognize
    /// its own output and pass it straight through. Without this, our synthetic
    /// ⌘V re-enters the tap and the app pastes into itself forever.
    static let signature: Int64 = 0x4C_4B_50_53  // 'LKPS'

    static func post(keyCode: CGKeyCode, flags: CGEventFlags) {
        // A private state source keeps our synthetic modifiers from mixing with
        // the physical keyboard's — the user may still be holding ⌘ down.
        let source = CGEventSource(stateID: .privateState)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }

        for event in [down, up] {
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: signature)
            event.post(tap: .cghidEventTap)
        }
    }

    static func postCommandV() { post(keyCode: KeyCode.v, flags: .maskCommand) }
    static func postCommandC() { post(keyCode: KeyCode.c, flags: .maskCommand) }
}
