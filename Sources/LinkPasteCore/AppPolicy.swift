import Foundation

/// Decides whether link-pasting is allowed in a given app.
///
/// We hijack ⌘V globally, so this denylist is the safety valve. Anything that is
/// fundamentally a plain-text surface — terminals, code editors, password
/// managers — must get an untouched paste, because inserting rich text there
/// either does nothing useful or (in some Electron editors) dumps literal markup.
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

    public init(userDenylist: Set<String> = [], builtInDenylist: Set<String> = AppPolicy.defaultDenylist) {
        self.userDenylist = userDenylist
        self.builtInDenylist = builtInDenylist
    }

    public func allowsLinkPaste(bundleID: String?) -> Bool {
        // No bundle ID means we can't reason about the target at all. Don't
        // gamble — a normal paste is always the safe answer.
        guard let bundleID, !bundleID.isEmpty else { return false }
        return !isDenied(bundleID)
    }

    func isDenied(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        for entry in builtInDenylist.union(userDenylist) {
            let e = entry.lowercased()
            if e.hasSuffix(".") ? id.hasPrefix(e) : id == e { return true }
        }
        return false
    }
}
