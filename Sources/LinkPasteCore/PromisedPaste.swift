import AppKit
import Foundation

/// What a destination turned out to be, judged by which pasteboard flavor it read.
public enum DestinationKind: String, Codable, Equatable, Sendable {
    case rich
    case plain

    public var description: String {
        switch self {
        case .rich: "rich text"
        case .plain: "plain text"
        }
    }
}

/// Writes a paste as *promised* pasteboard data, and reports which flavor the
/// destination asked for.
///
/// This is how the app knows whether a destination can render a hyperlink.
/// Nothing is inspected and nothing is guessed: instead of writing finished bytes,
/// the pasteboard advertises the flavors and AppKit calls back here when the
/// destination reads one. A rich text area reads `public.rtf` or `public.html`; a
/// plain one reads `public.utf8-plain-text`. That callback isn't a signal that
/// correlates with rich text — it *is* the destination app performing the exact
/// decision we're trying to predict, observed directly, at no visible cost.
///
/// It answers a second question too, the one `docs/DESIGN.md` lists under "things
/// that will bite": *when has the app finished reading?* Restoring the user's
/// clipboard on a fixed delay is a guess in both directions. The first read is the
/// real signal.
///
/// Every flavor is served from precomputed `Data`, so the callback is a dictionary
/// lookup — whatever is asked for is delivered immediately, with no work that
/// could fail or block the destination.
public final class PromisedPaste: NSObject, NSPasteboardItemDataProvider {

    /// Asks well-behaved clipboard managers not to record this item. Besides being
    /// polite about churn we're about to undo anyway, it keeps them from reading
    /// flavors themselves and muddying the observation.
    public static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private static let richTypes: Set<NSPasteboard.PasteboardType> = [.rtf, .html]

    private let payloads: [NSPasteboard.PasteboardType: Data]

    private let lock = NSLock()
    private var requestedTypes: Set<NSPasteboard.PasteboardType> = []
    private var hasSignalledFirstRead = false
    private var changeCountAtWrite: Int?

    private let firstRead = DispatchSemaphore(value: 0)

    public init(payloads: [NSPasteboard.PasteboardType: Data]) {
        self.payloads = payloads
    }

    // MARK: - Writing

    @discardableResult
    public func write(to pasteboard: NSPasteboard) -> Bool {
        let types = Array(payloads.keys)
        guard !types.isEmpty else { return false }

        let item = NSPasteboardItem()
        item.setString("", forType: Self.transientType)
        item.setDataProvider(self, forTypes: types)

        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { return false }

        lock.lock()
        changeCountAtWrite = pasteboard.changeCount
        lock.unlock()
        return true
    }

    // MARK: - Observing

    /// Blocks until the destination reads a flavor, then a moment longer, and
    /// reports what it read.
    ///
    /// The settle matters: an app that reads plain text first and rich text second
    /// would otherwise be judged on its first read alone and recorded as plain.
    /// Returning early on the read rather than always sleeping the full timeout is
    /// what makes the clipboard restore both faster and safer than a fixed delay.
    ///
    /// Blocks the calling thread — call it from the paste queue, never from the
    /// event tap callback or the main thread, since the callbacks it is waiting on
    /// are delivered on the main run loop.
    public func waitForRead(timeout: TimeInterval, settle: TimeInterval = 0.05) -> DestinationKind? {
        let wasRead = firstRead.wait(timeout: .now() + timeout) == .success
        if wasRead, settle > 0 {
            Thread.sleep(forTimeInterval: settle)
        }
        return observedKind
    }

    public var observedKind: DestinationKind? {
        lock.lock()
        defer { lock.unlock() }
        if !requestedTypes.isDisjoint(with: Self.richTypes) { return .rich }
        if requestedTypes.contains(.string) { return .plain }
        // Nobody read anything: the ⌘V didn't land in a text field at all. Judging
        // that "plain" from silence would poison the ledger, so judge nothing.
        return nil
    }

    /// False once anything else has written to the pasteboard since we did.
    ///
    /// Restoring the snapshot in that case would destroy whatever the user (or
    /// another app) put there in the meantime — which `docs/DESIGN.md` rightly
    /// calls the unforgivable failure.
    public func stillOwnsPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let changeCountAtWrite else { return false }
        return pasteboard.changeCount == changeCountAtWrite
    }

    // MARK: - NSPasteboardItemDataProvider

    public func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        // Serve first, bookkeep second — the destination is blocked on this call.
        if let data = payloads[type] {
            item.setData(data, forType: type)
        }

        lock.lock()
        requestedTypes.insert(type)
        let shouldSignal = !hasSignalledFirstRead
        hasSignalledFirstRead = true
        lock.unlock()

        if shouldSignal { firstRead.signal() }
    }
}
