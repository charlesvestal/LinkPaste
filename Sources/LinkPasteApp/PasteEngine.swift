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
        case linked(text: String, url: URL, source: SelectionReader.Source, observed: DestinationKind?)
        case linkedAsMarkdown(text: String, url: URL, source: SelectionReader.Source)
        case passedThrough(reason: String)

        /// Phrased for the "Last paste" line in Settings — this is how the app
        /// explains itself when it decides *not* to link something.
        var description: String {
            switch self {
            case let .linked(text, url, source, observed):
                var line = "Linked “\(text)” → \(url.absoluteString) (via \(source.description))"
                switch observed {
                case .rich: line += " — the destination read rich text"
                case .plain: line += " — but the destination read plain text, so it got the URL"
                case nil: line += " — the destination never read the pasteboard"
                }
                return line
            case let .linkedAsMarkdown(text, url, source):
                return "Pasted [\(text)](\(url.absoluteString)) as markdown (via \(source.description))"
            case let .passedThrough(reason):
                return "Pasted normally — \(reason)"
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

        let bundleID = currentBundleID
        let destination = DestinationInspector.inspect(bundleID: bundleID)
        let known = destination.flatMap { settings.destinations.kind(for: $0) }
        let wantsMarkdown = settings.policy.usesMarkdownLinks(bundleID: bundleID)
            || (known == .plain && settings.usesMarkdownInPlainDestinations)

        // Somewhere we have already watched read the plain flavor. It cannot
        // render a link, so hand the keystroke back now — before the ⌘C probe
        // fires a real keystroke into it and before the clipboard is touched.
        if known == .plain, !wantsMarkdown {
            return passThrough(restoring: nil, reason: "\(destination?.label ?? "this field") reads plain text")
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

        if wantsMarkdown {
            // Only a plain flavor goes out, so there is nothing to learn from this
            // paste — the destination can only read the one thing we offered.
            let markdown = LinkPayloadBuilder.buildMarkdown(text: selection.text, url: url)
            let changeCount = writeMarkdown(markdown)
            KeyPoster.postCommandV()
            Thread.sleep(forTimeInterval: settings.restoreDelay)
            restore(snapshot, ifPasteboardIsStillAt: changeCount)
            return report(.linkedAsMarkdown(text: selection.text, url: url, source: selection.source))
        }

        guard let payload = LinkPayloadBuilder.build(text: selection.text, url: url) else {
            return passThrough(restoring: snapshot, reason: "could not build rich text")
        }

        // Promised rather than finished data: the destination's read comes back to
        // us as a callback, which is both the rich/plain verdict and the signal
        // that it is safe to restore the clipboard. See `PromisedPaste`.
        let promised = PromisedPaste(payloads: payload.flavors)
        guard promised.write(to: pasteboard) else {
            return passThrough(restoring: snapshot, reason: "could not write the pasteboard")
        }
        KeyPoster.postCommandV()

        // Returns as soon as the destination reads, rather than always sleeping
        // the full delay. `restoreDelay` is now only the ceiling on how long we
        // will wait for an app that never reads at all.
        let observed = promised.waitForRead(timeout: settings.restoreDelay)
        if let observed, let destination {
            settings.destinations.record(observed, for: destination)
        }

        if promised.stillOwnsPasteboard(pasteboard) {
            snapshot.restore(to: pasteboard)
        }

        report(.linked(text: selection.text, url: url, source: selection.source, observed: observed))
    }

    /// Puts the user's clipboard back, unless it is no longer ours to put back.
    private func restore(_ snapshot: PasteboardSnapshot, ifPasteboardIsStillAt changeCount: Int) {
        // Someone else owns the clipboard now — the user hit ⌘C, or another app
        // wrote to it. Putting our snapshot back would destroy their copy.
        guard pasteboard.changeCount == changeCount else { return }
        snapshot.restore(to: pasteboard)
    }

    /// Markdown-mode composers (Slack with "Format messages with markup" on)
    /// read pasted content as literal text to type, not rich text to render.
    /// Writing RTF/HTML there is the exact bug this exists to avoid, so only
    /// a plain-text flavor goes on the pasteboard.
    @discardableResult
    private func writeMarkdown(_ markdown: String) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(markdown, forType: .string)
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
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
