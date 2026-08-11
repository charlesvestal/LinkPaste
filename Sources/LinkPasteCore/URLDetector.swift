import Foundation

/// Decides whether a clipboard string is "a URL" for link-paste purposes.
///
/// The bar is deliberately asymmetric. A false negative is invisible — you get a
/// normal paste. A false positive turns `Version 2.0` into a hyperlink to
/// `http://2.0`, which is the failure users actually notice. So: liberal about
/// real URLs, paranoid about prose.
public enum URLDetector {

    /// Schemes we accept without a `//` authority. Anything else must look like
    /// `scheme://…`, which keeps `note:remember this` and Swift's `Foo:Bar` out.
    static let authorityFreeSchemes: Set<String> = [
        "mailto", "tel", "sms", "facetime", "facetime-audio", "callto", "im",
    ]

    /// TLDs that may appear on a *bare* host (no scheme). Curated rather than the
    /// full public suffix list: the PSL contains hundreds of entries that collide
    /// with everyday text and file names, and shipping it would trade a rare miss
    /// for a common embarrassment.
    ///
    /// Deliberately absent: `md`, `sh`, `ts`, `rs`, `py`, `so`, `im` and friends
    /// that read as file extensions far more often than as domains — `README.md`
    /// must never become a link. `ai` is included despite `.ai` being an Illustrator
    /// extension, because bare `.ai` domains are now common enough to earn it.
    static let bareHostTLDs: Set<String> = [
        // generic
        "com", "org", "net", "edu", "gov", "mil", "int", "info", "biz", "name",
        "pro", "app", "dev", "io", "co", "ai", "xyz", "site", "online", "store",
        "blog", "cloud", "tech", "design", "media", "news", "email", "wiki",
        "social", "space", "live", "life", "world", "today", "zone", "team",
        // country codes in common web use
        "uk", "de", "fr", "jp", "cn", "ru", "br", "in", "au", "ca", "nl", "se",
        "no", "dk", "fi", "es", "it", "ch", "at", "be", "pt", "gr", "cz", "eu",
        "nz", "mx", "kr", "tw", "hk", "sg", "za", "ie", "il", "tr", "ua", "tv",
        "fm", "gg", "us",
    ]

    /// Returns the URL to link to, or `nil` if this clipboard content should just
    /// be pasted normally.
    public static func detect(in raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty, text.count <= 2048 else { return nil }
        // Any interior whitespace means it's a sentence, not a URL.
        guard text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }

        if let scheme = explicitScheme(of: text) {
            guard hasUsableScheme(text, scheme: scheme) else { return nil }
            return URL(string: text)
        }

        return bareHostURL(from: text)
    }

    // MARK: - Scheme handling

    /// The `scheme` in `scheme:rest`, lowercased, or nil if there's no leading
    /// scheme. Must start with a letter per RFC 3986.
    static func explicitScheme(of text: String) -> String? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let candidate = String(text[text.startIndex..<colon])
        guard let first = candidate.first, first.isLetter else { return nil }
        let valid = candidate.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
        guard valid, !candidate.isEmpty else { return nil }
        return candidate.lowercased()
    }

    /// A scheme is usable if it carries an authority (`scheme://host…`) or is one
    /// of the known authority-free schemes with a non-empty payload.
    static func hasUsableScheme(_ text: String, scheme: String) -> Bool {
        if text.dropFirst(scheme.count).hasPrefix("://") {
            // Reject `https://` with nothing after it.
            return text.count > scheme.count + 3
        }
        guard authorityFreeSchemes.contains(scheme) else { return false }
        return text.count > scheme.count + 1
    }

    // MARK: - Bare hosts

    /// `example.com`, `sub.domain.co.uk/path?q=1#frag` → an https URL.
    static func bareHostURL(from text: String) -> URL? {
        // Split off the first path/query/fragment delimiter; the rest is the host.
        let hostPart: Substring
        if let cut = text.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            hostPart = text[text.startIndex..<cut]
        } else {
            hostPart = text[...]
        }

        // A bare host with credentials or a port is more likely a config string
        // than something a person meant to link. Keep it simple and skip both.
        guard !hostPart.contains("@"), !hostPart.contains(":") else { return nil }

        let labels = hostPart.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return nil }
        guard labels.allSatisfy(isValidHostLabel) else { return nil }

        guard let tld = labels.last?.lowercased(), bareHostTLDs.contains(tld) else { return nil }

        return URL(string: "https://\(text)")
    }

    static func isValidHostLabel(_ label: Substring) -> Bool {
        guard !label.isEmpty, label.count <= 63 else { return false }
        guard label.first != "-", label.last != "-" else { return false }
        return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}
