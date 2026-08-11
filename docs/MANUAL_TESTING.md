# Manual test checklist

The event tap, the Accessibility read, and the paste round-trip can't be
meaningfully unit tested — they need a real app with a real text field and a real
keystroke. This checklist is the substitute. Run it before cutting a release.

Setup: copy `https://example.com/docs` to the clipboard before each case unless
stated otherwise.

Two traps worth knowing before you start, both of which produced false results
the first time through:

- **Don't reset a document by select-all-and-retype.** Typing over linked text
  inherits the link attribute, so the new text arrives *already linked* and the
  next paste looks like a false positive. Open a fresh document per case.
- **Don't verify by copying the result back to the clipboard.** If the copy
  selects nothing, the clipboard keeps its previous contents and you'll read a
  stale value as though it were the result. Verify by looking at the document,
  or in an app whose copy reliably produces a rich flavor.

## Core behavior

| # | App | Steps | Expected |
|---|-----|-------|----------|
| 1 | TextEdit (rich text) | Select a word, ⌘V | Word becomes a link. Clipboard still holds the URL afterwards. |
| 2 | Mail (new message) | Select a word, ⌘V | Word becomes a link. |
| 3 | Notes | Select a word, ⌘V | Word becomes a link. |
| 4 | Pages | Select a word, ⌘V | Word becomes a link. |
| 5 | Slack (message box) | Select a word, ⌘V | Word becomes a link — matching Slack's own behavior, not fighting it. |
| 6 | Notion | Select a word, ⌘V | Word becomes a link. |
| 7 | Gmail in Chrome | Select a word, ⌘V | Word becomes a link. **Chrome does not expose `AXSelectedText`** — verified by disabling the ⌘C fallback, after which the raw URL pastes instead. The probe is load-bearing for all browser content, not a nicety. |
| 8 | Google Docs | Select a word, ⌘V | Word becomes a link. |

## Pass-through (must behave like an ordinary ⌘V)

| # | Case | Expected |
|---|------|----------|
| 9 | No selection, cursor only | URL pastes as plain text. |
| 10 | Clipboard holds non-URL text | Normal paste. |
| 11 | Clipboard holds an image | Normal paste. |
| 12 | Terminal — select text, ⌘V | Raw URL pastes. No rich text, no synthetic ⌘C. |
| 13 | VS Code — select text, ⌘V | Raw URL pastes. |
| 14 | TextEdit in **plain text** mode | Selection is replaced by the *selection text* (harmless no-op), never by markup. |
| 15 | Paste and Match Style | Untouched — normal system behavior. **Use the app's real shortcut**: TextEdit binds this to ⌥⇧⌘V, not ⌘⇧V. Testing ⌘⇧V in TextEdit proves nothing — the key is simply unbound there, so "nothing happened" is indistinguishable from a pass. |
| 16 | Toggle off in the menu bar, then ⌘V | Normal paste everywhere. |

## Clipboard integrity — the failure that matters most

| # | Case | Expected |
|---|------|----------|
| 17 | Any successful link-paste, then ⌘V into TextEdit again | The *original URL* pastes. The clipboard was restored. |
| 18 | Copy an image, then link-paste elsewhere, then ⌘V | The image is still on the clipboard. |
| 19 | Link-paste into a slow Electron app | The link pastes — not the previous clipboard contents. If it does paste the wrong thing, raise the restore delay and note the app. |
| 20 | Hold ⌘ and press V several times rapidly | No interleaving, no lost clipboard, no duplicate pastes. |

## Permissions

| # | Case | Expected |
|---|------|----------|
| 21 | Launch without Accessibility access | Settings window opens, menu bar icon shows the warning state, ⌘V behaves normally. |
| 22 | Grant access while running | Tap starts within ~2s, no relaunch needed. |
| 23 | Revoke access while running | Icon flips to the warning state, ⌘V returns to normal behavior. |
| 24 | Rebuild the app and relaunch | macOS revokes trust; the app must say so rather than failing silently. |
