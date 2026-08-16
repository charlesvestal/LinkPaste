import AppKit
import Foundation

/// The rich-text payload we put on the pasteboard in place of the raw URL.
public struct LinkPayload: Equatable {
    /// RTF — what AppKit text views (Mail, Notes, TextEdit, Pages) read.
    public let rtf: Data
    /// HTML — what browser-based and Electron editors (Slack, Notion, Gmail) read.
    public let html: Data
    /// Plain-text fallback.
    ///
    /// This is the *selected text*, not the URL. A plain-text field that ignores
    /// our rich flavors then ends up with the text unchanged, which is a boring
    /// no-op rather than a mangled paste.
    public let plain: String

    public init(rtf: Data, html: Data, plain: String) {
        self.rtf = rtf
        self.html = html
        self.plain = plain
    }
}

public enum LinkPayloadBuilder {

    /// Builds `<a href="url">text</a>` in every flavor an editor might want.
    ///
    /// Returns nil only if AppKit fails to serialize, which shouldn't happen for
    /// a single-run attributed string — but the caller treats nil as "just paste
    /// normally" rather than crashing on a keystroke the user makes constantly.
    public static func build(text: String, url: URL) -> LinkPayload? {
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

        return LinkPayload(rtf: rtf, html: html, plain: text)
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
