# Manual test checklist

The event tap, the Accessibility read, and the paste round-trip can't be
meaningfully unit tested — they need a real app with a real text field and a real
keystroke. This checklist is the substitute. Run it before cutting a release.

Setup: copy `https://example.com/docs` to the clipboard before each case unless
stated otherwise.

## Core behavior

| # | App | Steps | Expected |
|---|-----|-------|----------|
| 1 | TextEdit (rich text) | Select a word, ⌘V | Word becomes a link. Clipboard still holds the URL afterwards. |
| 2 | Mail (new message) | Select a word, ⌘V | Word becomes a link. |
| 3 | Notes | Select a word, ⌘V | Word becomes a link. |
| 4 | Pages | Select a word, ⌘V | Word becomes a link. |
| 5 | Slack (message box) | Select a word, ⌘V | Word becomes a link — matching Slack's own behavior, not fighting it. |
| 6 | Notion | Select a word, ⌘V | Word becomes a link. |
| 7 | Gmail in Chrome | Select a word, ⌘V | Word becomes a link. |
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
| 15 | ⌘⇧V (paste and match style) | Untouched — normal system behavior. |
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
