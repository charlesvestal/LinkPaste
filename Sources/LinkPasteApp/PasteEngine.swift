import AppKit
import Foundation
import LinkPasteCore

/// Orchestrates a single link-paste.
///
/// The work is split across two threads on purpose. The event tap's callback runs
/// under a watchdog, so it only gets the cheap checks — is the app enabled, is
/// there a URL on the clipboard, is this app denylisted. Everything slow (the
/// Accessibility query, the ⌘C probe, the paste, the restore delay) happens on a
/// serial background queue after the event has already been swallowed.
///
/// Every failure path ends the same way: post a plain ⌘V. If this app is confused,
/// broken, or unlucky, the user should experience an ordinary paste — never a
/// mangled one and never a swallowed keystroke.
final class PasteEngine {

    private let queue = DispatchQueue(label: "app.linkpaste.engine", qos: .userInteractive)
    private let settings: Settings
    private let pasteboard: NSPasteboard

    private let lock = NSLock()
    private var frontmostBundleID: String?
    private var isBusy = false

    /// Fired after each handled ⌘V so the UI can show what happened.
    var onOutcome: ((Outcome) -> Void)?

    enum Outcome {
        case linked(text: String, url: URL, source: SelectionReader.Source)
        case passedThrough(reason: String)

        /// Phrased for the "Last paste" line in Settings — this is how the app
        /// explains itself when it decides *not* to link something.
        var description: String {
            switch self {
            case let .linked(text, url, source):
                "Linked “\(text)” → \(url.absoluteString) (via \(source.description))"
            case let .passedThrough(reason):
                "Pasted normally — \(reason)"
            }
        }
    }

    init(settings: Settings, pasteboard: NSPasteboard = .general) {
        self.settings = settings
        self.pasteboard = pasteboard
        observeFrontmostApp()
    }

    // MARK: - Frontmost app tracking

    /// NSWorkspace is main-thread furniture, and the event tap callback is not on
    /// the main thread. Track activations up front instead of querying from the tap.
    private func observeFrontmostApp() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.setFrontmostBundleID(app?.bundleIdentifier)
        }
        setFrontmostBundleID(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    private func setFrontmostBundleID(_ id: String?) {
        lock.lock()
        frontmostBundleID = id
        lock.unlock()
    }

    private var currentBundleID: String? {
        lock.lock()
        defer { lock.unlock() }
        return frontmostBundleID
    }

    // MARK: - Fast path (event tap thread)

    /// Cheap checks only. Returns true to swallow the ⌘V and take over.
    func shouldIntercept() -> Bool {
        guard settings.isEnabled else { return false }

        lock.lock()
        let busy = isBusy
        lock.unlock()
        // A second ⌘V while we're mid-paste would interleave pasteboard writes.
        // Let it through as a normal paste rather than racing ourselves.
        guard !busy else { return false }

        guard settings.policy.allowsLinkPaste(bundleID: currentBundleID) else { return false }

        guard let string = pasteboard.string(forType: .string),
              URLDetector.detect(in: string) != nil
        else { return false }

        lock.lock()
        isBusy = true
        lock.unlock()

        queue.async { [weak self] in self?.performLinkPaste() }
        return true
    }

    // MARK: - Slow path (background queue)

    private func performLinkPaste() {
        defer {
            lock.lock()
            isBusy = false
            lock.unlock()
        }

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        // Re-read rather than trusting the fast path: the clipboard could have
        // changed in the microseconds since, and we're about to overwrite it.
        guard let clipboardString = pasteboard.string(forType: .string),
              let url = URLDetector.detect(in: clipboardString)
        else {
            return passThrough(restoring: nil, reason: "clipboard is no longer a URL")
        }

        let selection = SelectionReader.read(
            pasteboard: pasteboard,
            allowCopyProbe: settings.allowsCopyProbe,
            probeTimeout: settings.copyProbeTimeout
        )

        guard let selection, !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // The ⌘C probe may have clobbered the clipboard on its way to finding
            // nothing, so restore before handing the paste back.
            return passThrough(restoring: snapshot, reason: "no text selected")
        }

        guard let payload = LinkPayloadBuilder.build(text: selection.text, url: url) else {
            return passThrough(restoring: snapshot, reason: "could not build rich text")
        }

        write(payload)
        KeyPoster.postCommandV()

        // No app tells us when it has finished reading the pasteboard, so this
        // delay is a guess. Too short and we restore the old clipboard before a
        // slow app reads ours — which pastes the *wrong thing*. Hence the
        // deliberately generous default.
        Thread.sleep(forTimeInterval: settings.restoreDelay)
        snapshot.restore(to: pasteboard)

        report(.linked(text: selection.text, url: url, source: selection.source))
    }

    private func write(_ payload: LinkPayload) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(payload.rtf, forType: .rtf)
        item.setData(payload.html, forType: .html)
        item.setString(payload.plain, forType: .string)
        pasteboard.writeObjects([item])
    }

    private func passThrough(restoring snapshot: PasteboardSnapshot?, reason: String) {
        if let snapshot {
            snapshot.restore(to: pasteboard)
            // Give the pasteboard server a moment to settle before the app reads it.
            Thread.sleep(forTimeInterval: 0.02)
        }
        KeyPoster.postCommandV()
        report(.passedThrough(reason: reason))
    }

    private func report(_ outcome: Outcome) {
        DispatchQueue.main.async { [weak self] in self?.onOutcome?(outcome) }
    }
}
