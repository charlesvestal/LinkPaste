import AppKit
import Foundation

/// The rich-text payload we put on the pasteboard in place of the raw URL.
public struct LinkPayload: Equatable {
    /// RTF — what AppKit text views (Mail, Notes, TextEdit, Pages) read.
    public let rtf: Data
    /// HTML — what browser-based and Electron editors (Slack, Notion, Gmail) read.
    public let html: Data
    /// Plain-text fallback — the URL, by default.
    ///
    /// This used to be the selected text, on the reasoning that leaving the text
    /// unchanged is a harmless no-op. In practice it is the opposite of harmless:
    /// the one moment this flavor is ever read is the moment we've guessed wrong
    /// about a destination, and the user gets a ⌘V that silently does nothing —
    /// no link, no URL, no explanation. Pasting the URL is what would have
    /// happened without this app running, which is the bar `docs/DESIGN.md` sets
    /// for every path that isn't a successful link-paste.
    public let plain: String

    public init(rtf: Data, html: Data, plain: String) {
        self.rtf = rtf
        self.html = html
        self.plain = plain
    }

    /// Keyed by pasteboard type, ready to hand to `PromisedPaste`.
    public var flavors: [NSPasteboard.PasteboardType: Data] {
        [
            .rtf: rtf,
            .html: html,
            .string: Data(plain.utf8),
        ]
    }
}

public enum LinkPayloadBuilder {

    /// Builds `<a href="url">text</a>` in every flavor an editor might want.
    ///
    /// `plainText` overrides the plain-text flavor; it defaults to the URL, so a
    /// destination that turns out not to render links gets an ordinary paste.
    ///
    /// Returns nil only if AppKit fails to serialize, which shouldn't happen for
    /// a single-run attributed string — but the caller treats nil as "just paste
    /// normally" rather than crashing on a keystroke the user makes constantly.
    public static func build(text: String, url: URL, plainText: String? = nil) -> LinkPayload? {
        let attributed = NSMutableAttributedString(string: text)
        let range = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.link, value: url, range: range)

        // Underline + link colour so the pasted link *looks* like a link in
        // editors that render RTF literally instead of restyling it themselves.
        attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        attributed.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)

        guard let rtf = attributed.rtf(from: range, documentAttributes: [:]) else { return nil }

        guard let html = try? attributed.data(
            from: range,
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.html,
                .excludedElements: ["XMLDeclaration", "DOCTYPE", "meta"],
            ]
        ) else { return nil }

        return LinkPayload(rtf: rtf, html: html, plain: plainText ?? url.absoluteString)
    }

    /// Builds `[text](url)` for composers that read pasted content as literal
    /// markdown — e.g. Slack with "Format messages with markup" on, where the
    /// RTF/HTML this app normally writes doesn't render.
    ///
    /// Only `text` is escaped (`\`, `[`, `]`, in that order so escaping the
    /// brackets doesn't get re-escaped by the backslash pass). The URL is left
    /// untouched: Slack's parser tolerates parens and other special characters
    /// there in practice, and over-escaping risks corrupting it.
    public static func buildMarkdown(text: String, url: URL) -> String {
        var escaped = text
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "[", with: "\\[")
        escaped = escaped.replacingOccurrences(of: "]", with: "\\]")
        return "[\(escaped)](\(url.absoluteString))"
    }
}
