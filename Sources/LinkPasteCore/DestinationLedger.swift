import Foundation

/// Identifies "a kind of place a paste can land".
///
/// Granular enough to tell a rich composer from a plain search box in the same
/// app; coarse enough that what we learn about one Gmail compose window applies
/// to the next one. The page host is what keeps a browser honest — without it
/// every text area in Chrome shares one identity, and Gmail's composer would hand
/// its verdict to a GitHub comment box.
///
/// `window` does the same job for desktop apps that have no page host to key on.
/// TextEdit's plain-text window and its rich-text window are otherwise identical
/// — same bundle ID, same role, no host — so without it they share one verdict,
/// and whichever was pasted into last silently overwrites what was learned about
/// the other: a rich document gets left unlinked, or a plain one gets sent real
/// RTF/HTML it can only mangle. It's left blank for web content on purpose —
/// browser window titles change with the page, and `host` already disambiguates
/// there without that churn.
public struct DestinationContext: Hashable, Sendable {
    public let bundleID: String
    public let role: String
    public let subrole: String
    public let host: String
    public let window: String

    public init(bundleID: String, role: String, subrole: String = "", host: String = "", window: String = "") {
        self.bundleID = bundleID
        self.role = role
        self.subrole = subrole
        self.host = host
        self.window = window
    }

    /// `window` is appended only when present, so a context that never sets it
    /// (every existing caller, and every browser destination) produces exactly
    /// the key it always has — no format bump, nothing to migrate.
    public var key: String {
        var parts = [bundleID, role, subrole, host]
        if !window.isEmpty { parts.append(window) }
        return parts.joined(separator: "|")
    }

    /// For the "Last paste" line in Settings.
    public var label: String {
        var parts = [bundleID.isEmpty ? "(unknown app)" : bundleID]
        if !host.isEmpty { parts.append(host) }
        if !role.isEmpty { parts.append(role) }
        if !window.isEmpty { parts.append(window) }
        return parts.joined(separator: " · ")
    }
}

/// What each destination turned out to be, so the invasive parts of a paste only
/// happen where they pay off.
///
/// Entries are observations from `PromisedPaste`, not guesses, which is what makes
/// acting on them reasonable. A pinned entry is a user override and outranks both
/// expiry and any later observation.
public struct DestinationLedger: Equatable {

    public struct Entry: Codable, Equatable {
        public var kind: DestinationKind
        public var learnedAt: Date
        /// Optional so that ledgers written before pinning existed still decode.
        public var pinned: Bool?

        public init(kind: DestinationKind, learnedAt: Date, pinned: Bool? = nil) {
            self.kind = kind
            self.learnedAt = learnedAt
            self.pinned = pinned
        }

        public var isPinned: Bool { pinned == true }
    }

    /// Apps get redesigned and web apps get rewritten; an unpinned verdict should
    /// heal on its own eventually rather than being believed forever.
    public static let defaultTimeToLive: TimeInterval = 30 * 24 * 60 * 60

    public private(set) var entries: [String: Entry]
    public let timeToLive: TimeInterval

    public init(entries: [String: Entry] = [:], timeToLive: TimeInterval = DestinationLedger.defaultTimeToLive) {
        self.entries = entries
        self.timeToLive = timeToLive
    }

    public var count: Int { entries.count }

    public func kind(for context: DestinationContext, now: Date = Date()) -> DestinationKind? {
        guard let entry = entries[context.key] else { return nil }
        guard entry.isPinned || now.timeIntervalSince(entry.learnedAt) < timeToLive else { return nil }
        return entry.kind
    }

    public func isPinned(_ context: DestinationContext) -> Bool {
        entries[context.key]?.isPinned ?? false
    }

    public mutating func record(_ kind: DestinationKind, for context: DestinationContext, now: Date = Date()) {
        guard entries[context.key]?.isPinned != true else { return }
        entries[context.key] = Entry(kind: kind, learnedAt: now, pinned: false)
    }

    /// A user override, for the one case observation cannot catch: a destination
    /// that reads the rich flavor and then throws the link away.
    public mutating func pin(_ kind: DestinationKind, for context: DestinationContext, now: Date = Date()) {
        entries[context.key] = Entry(kind: kind, learnedAt: now, pinned: true)
    }

    public mutating func forgetAll() {
        entries.removeAll()
    }

    // MARK: - Persistence

    public func encoded() -> Data? {
        try? JSONEncoder().encode(entries)
    }

    public static func decoded(from data: Data?, timeToLive: TimeInterval = DestinationLedger.defaultTimeToLive) -> DestinationLedger {
        guard let data,
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return DestinationLedger(timeToLive: timeToLive) }
        return DestinationLedger(entries: entries, timeToLive: timeToLive)
    }
}
