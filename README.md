# LinkPaste

Slack's link-pasting behavior, everywhere on macOS.

Select some text, copy a URL, press **⌘V** — instead of replacing your selection with a raw URL, the selection becomes a hyperlink to it.

```
selection:  the documentation
clipboard:  https://example.com/docs
⌘V      →   the documentation      (linked to https://example.com/docs)
```

Slack, Notion, Jira and Bear each build this in. macOS doesn't provide it, so every other rich-text field on your Mac — Mail, Notes, Pages, TextEdit, Google Docs — makes you go the long way round. LinkPaste fills that gap system-wide.

## Install

Download `LinkPaste.zip` from [Releases](../../releases), unzip, and drag `LinkPaste.app` to `/Applications`.

On first launch it will ask for **Accessibility** access. It genuinely cannot work without this — seeing ⌘V and reading your selection both require it.

> **Note:** macOS revokes Accessibility access whenever an app's code signature changes, which includes every update. If link-pasting silently stops working after an update, that's why — the menu bar icon will show it, and Settings has a button to re-grant.

## How it works

1. A `CGEventTap` watches for ⌘V.
2. If the clipboard holds a URL and the front app isn't denylisted, the keystroke is swallowed.
3. The selected text is read via the Accessibility API, falling back to a synthetic ⌘C when the app won't report it (browsers, Slack, Notion).
4. The clipboard is temporarily replaced with rich text — `<a href="url">selection</a>` in RTF, HTML, and plain-text flavors.
5. A synthetic ⌘V pastes it, then your original clipboard is restored.

**Every failure path falls back to an ordinary paste.** If anything is unclear, unsupported, or broken, you get the paste you would have gotten anyway.

## What counts as a URL

Anything with a scheme (`https://`, `mailto:`, `slack://`) plus bare domains with a recognized TLD (`example.com`, `sub.domain.co.uk/path`).

Deliberately *not* matched: anything containing whitespace, and filenames that happen to look like domains. `README.md`, `build.sh`, and `Version 2.0` are never turned into links — `.md`, `.sh` and friends are real TLDs, and linking them would be the most irritating possible false positive. See [`URLDetector.swift`](Sources/LinkPasteCore/URLDetector.swift).

## Where it doesn't run

Terminals, code editors, and password managers are excluded by default — they're plain-text surfaces where a rich paste is useless, and in the case of password managers, somewhere a synthetic ⌘C has no business going. Add your own bundle IDs in Settings.

## Settings

- **Enable link pasting** — global on/off.
- **Launch at login.**
- **⌘C fallback** — turn off if you'd rather no synthetic ⌘C is ever sent. Costs you support in browsers, Slack, and Notion.
- **Clipboard restore delay** (default 250 ms) — how long to wait before restoring your clipboard. No app signals when it has finished reading the pasteboard, so this is a timing guess. If a slow app ever pastes your *previous* clipboard instead of the link, raise it.

## Build from source

```sh
swift build          # build
swift test           # 30 unit tests
scripts/make_app.sh  # assemble dist/LinkPaste.app
```

Signed releases are cut by pushing a tag:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

That runs [`.github/workflows/release.yml`](.github/workflows/release.yml), which builds a universal binary, signs it with Developer ID, notarizes and staples it, and attaches the result to a GitHub release. Credentials come from repository secrets — run [`scripts/setup_ci_secrets.sh`](scripts/setup_ci_secrets.sh) once to set them up.

## Not on the Mac App Store

It can't be. Event taps and the Accessibility API are unavailable to sandboxed apps, and the App Store requires the sandbox. Developer ID distribution only.

## License

MIT
