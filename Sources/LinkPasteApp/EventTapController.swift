import CoreGraphics
import Foundation

/// Owns the CGEventTap that watches for ⌘V.
///
/// Two things about event taps that are easy to get wrong and painful to debug:
///
/// - **The callback has a watchdog.** Take too long and macOS silently disables
///   the tap — every subsequent ⌘V stops working with no error anywhere. So the
///   callback does nothing but classify the event and hand off; all real work
///   happens on another queue.
/// - **Disabled taps must be re-enabled by hand.** macOS tells you via
///   `.tapDisabledByTimeout` / `.tapDisabledByUserInput` and then waits for you
///   to call `tapEnable` again. Miss that and the app is dead until relaunch.
final class EventTapController {

    /// Called on the event-tap thread when ⌘V is pressed.
    /// Return `true` to swallow the event (we'll handle the paste ourselves),
    /// `false` to let it through untouched.
    var shouldInterceptCommandV: (() -> Bool)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
            // Almost always means Accessibility permission is missing or stale.
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        tap = port
        runLoopSource = source
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    fileprivate func reenableAfterDisable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func handleKeyDown(_ event: CGEvent) -> Bool {
        // Our own synthetic events must pass straight through, or the ⌘V we post
        // comes back to us and we recurse forever.
        guard event.getIntegerValueField(.eventSourceUserData) != KeyPoster.signature else { return false }

        guard CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == KeyCode.v else { return false }

        // ⌘V exactly — not ⌘⇧V (paste and match style), not ⌥⌘V, not ⌃⌘V.
        // Those are distinct commands and hijacking them would be rude.
        let relevant: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        guard event.flags.intersection(relevant) == .maskCommand else { return false }

        return shouldInterceptCommandV?() ?? false
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        controller.reenableAfterDisable()
        return nil

    case .keyDown:
        return controller.handleKeyDown(event) ? nil : Unmanaged.passUnretained(event)

    default:
        return Unmanaged.passUnretained(event)
    }
}
