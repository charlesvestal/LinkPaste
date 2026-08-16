import Foundation

/// Decides whether link-pasting is allowed in a given app.
///
/// We hijack ⌘V globally, so this denylist is the safety valve. Anything that is
/// fundamentally a plain-text surface — terminals, code editors, password
/// managers — must get an untouched paste, because inserting rich text there
/// either does nothing useful or (in some Electron editors) dumps literal markup.
///
/// `markdownList` overrides the denylist, built-in or user's own: adding an app
/// there is a deliberate per-app choice that link-pasting belongs there, once the
/// output is plain-text markdown rather than RTF/HTML.
public struct AppPolicy: Equatable {

    /// Bundle IDs that never get a link-paste. Prefixes are matched too, so
    /// `com.jetbrains.` covers every JetBrains IDE.
    public static let defaultDenylist: Set<String> = [
        // Terminals
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty",
        // Code editors / IDEs
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.apple.dt.Xcode",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "com.jetbrains.",
        "com.barebones.bbedit",
        "com.macromates.TextMate",
        "com.panic.Nova",
        "org.gnu.Emacs",
        "org.vim.MacVim",
        "dev.zed.Zed",
        // Credential surfaces — never synthesize keystrokes at these
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.apple.keychainaccess",
        "in.sinew.Enpass-Desktop",
        "com.bitwarden.desktop",
    ]

    /// Extra bundle IDs the user added in Settings.
    public var userDenylist: Set<String>
    public var builtInDenylist: Set<String>

    /// Bundle IDs of apps whose composer wants `[text](url)` markdown as
    /// plain text, rather than RTF/HTML — e.g. Slack with "Format messages
    /// with markup" on. No built-in members: whether markdown mode applies
    /// is a per-user app setting, not a property of the app itself.
    public var markdownList: Set<String>

    public init(
        userDenylist: Set<String> = [],
        builtInDenylist: Set<String> = AppPolicy.defaultDenylist,
        markdownList: Set<String> = []
    ) {
        self.userDenylist = userDenylist
        self.builtInDenylist = builtInDenylist
        self.markdownList = markdownList
    }

    public func allowsLinkPaste(bundleID: String?) -> Bool {
        // No bundle ID means we can't reason about the target at all. Don't
        // gamble — a normal paste is always the safe answer.
        guard let bundleID, !bundleID.isEmpty else { return false }
        // Explicitly adding an app to the markdown list is a deliberate,
        // per-app choice — it overrides a denylist entry (built-in or user's
        // own) for that app, on the theory that a user who asked for
        // markdown output there has already decided link-pasting belongs.
        return usesMarkdownLinks(bundleID: bundleID) || !isDenied(bundleID)
    }

    public func usesMarkdownLinks(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return Self.matches(bundleID, in: markdownList)
    }

    func isDenied(_ bundleID: String) -> Bool {
        Self.matches(bundleID, in: builtInDenylist.union(userDenylist))
    }

    private static func matches(_ bundleID: String, in entries: Set<String>) -> Bool {
        let id = bundleID.lowercased()
        for entry in entries {
            let e = entry.lowercased()
            if e.hasSuffix(".") ? id.hasPrefix(e) : id == e { return true }
        }
        return false
    }
}
