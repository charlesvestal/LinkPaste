import Combine
import Foundation
import LinkPasteCore

/// Thread-safe home for the destination ledger, plus its persistence.
///
/// `Settings` deliberately skips locking because its values are single words and
/// a torn read costs one paste behaving like the previous setting. A dictionary
/// is a different matter: it is written from the paste queue and read from the
/// paste queue while SwiftUI reads its summary on the main thread, so this one
/// takes a lock and publishes to the UI separately.
final class LedgerStore: ObservableObject {

    /// Everything below is for the UI, and only ever touched on the main thread.
    @Published private(set) var learnedCount: Int
    @Published private(set) var lastContext: DestinationContext?
    @Published private(set) var lastKind: DestinationKind?
    @Published private(set) var lastIsPinned = false

    private static let storageKey = "destinationLedger"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var ledger: DestinationLedger

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = DestinationLedger.decoded(from: defaults.data(forKey: Self.storageKey))
        ledger = loaded
        learnedCount = loaded.count
    }

    // MARK: - Paste queue

    func kind(for context: DestinationContext) -> DestinationKind? {
        lock.lock()
        defer { lock.unlock() }
        return ledger.kind(for: context)
    }

    func record(_ kind: DestinationKind, for context: DestinationContext) {
        lock.lock()
        ledger.record(kind, for: context)
        let data = ledger.encoded()
        let count = ledger.count
        let pinned = ledger.isPinned(context)
        lock.unlock()

        persist(data)
        publish(count: count, context: context, kind: kind, pinned: pinned)
    }

    // MARK: - Main thread

    /// The user override for a destination that reads the rich flavor and then
    /// discards the link — the one failure the observation cannot see.
    func pinLastAsPlain() {
        guard let context = lastContext else { return }
        lock.lock()
        ledger.pin(.plain, for: context)
        let data = ledger.encoded()
        let count = ledger.count
        lock.unlock()

        persist(data)
        publish(count: count, context: context, kind: .plain, pinned: true)
    }

    func forgetAll() {
        lock.lock()
        ledger.forgetAll()
        let data = ledger.encoded()
        lock.unlock()

        persist(data)
        publish(count: 0, context: nil, kind: nil, pinned: false)
    }

    // MARK: - Plumbing

    private func persist(_ data: Data?) {
        guard let data else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func publish(count: Int, context: DestinationContext?, kind: DestinationKind?, pinned: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            learnedCount = count
            lastContext = context
            lastKind = kind
            lastIsPinned = pinned
        }
    }
}
