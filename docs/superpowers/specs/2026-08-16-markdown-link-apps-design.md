# Markdown-style links for markdown-composer apps

## Problem

LinkPaste replaces the pasteboard with RTF/HTML `<a href="url">text</a>` before
posting the synthetic ⌘V. That works for AppKit text views and most
browser/Electron editors, but fails in apps whose composer runs in markdown
mode — the flagship case being Slack with **Format messages with markup**
turned on. In that mode, Slack's composer treats pasted content as plain text
to be typed, not rich text to be rendered. The RTF/HTML flavors LinkPaste
writes are useless there, and the paste degrades to unlinked plain text
instead of a Slack-style `[text](url)` link.

## Goal

Let the user mark specific apps as "markdown apps." For those apps,
LinkPaste writes a `[text](url)` markdown string as plain text instead of
RTF/HTML.

## Non-goals

- No runtime detection of Slack's in-app markdown toggle. It isn't
  observable from outside the app, so this is explicit, user-configured,
  per-app — not automatic.
- No built-in default list (unlike the denylist's built-in terminals/IDEs/
  password managers). Whether "markdown mode" applies is a per-user Slack
  setting, not a property of the app itself, so a shipped default would be
  wrong for a meaningful fraction of users.
- No unification of the denylist and the new list into a single three-way
  per-app mode. They stay two independent lists, same as the two questions
  they answer ("never touch this app" vs. "this app wants markdown").
- No URL escaping. Only the selection text is escaped; Slack's parser
  tolerates parens and other special characters in the URL portion in
  practice, and over-escaping risks corrupting the URL itself.

## Design

### `AppPolicy` (LinkPasteCore)

Add a second bundle-ID set, matched with the same prefix rule the denylist
already uses (`isDenied`'s trailing-dot-prefix logic, factored out into a
shared helper so both lists match identically):

```swift
public var markdownList: Set<String>
public func usesMarkdownLinks(bundleID: String?) -> Bool
```

`markdownList` has no built-in members — it starts empty and is entirely
user-populated via Settings.

### `LinkPayloadBuilder` (LinkPasteCore)

Add:

```swift
public static func buildMarkdown(text: String, url: URL) -> String
```

Escapes backslash first, then `[` and `]`, in `text` (in that order, so
escaping the brackets doesn't get re-escaped by the backslash pass), leaves
the URL untouched, and returns `[escaped text](url)`.

### `PasteEngine.performLinkPaste`

After selection and URL are resolved (same point where `LinkPayloadBuilder.build`
is currently called), branch on:

```swift
settings.policy.usesMarkdownLinks(bundleID: currentBundleID)
```

- **Markdown apps:** build the markdown string via `buildMarkdown`, and
  write *only* a `.string` pasteboard entry containing it — no RTF, no HTML.
- **All other apps:** unchanged — `LinkPayloadBuilder.build` and the
  existing RTF/HTML/plain write.

`Outcome.linked` and its `description` are unchanged; they already report
text/url/source rather than the wire format, so no changes needed there.

### `Settings`

Add, mirroring the existing denylist support exactly:

```swift
@Published var userMarkdownList: [String] { didSet { defaults.set(userMarkdownList, forKey: Key.markdownList) } }

func addToMarkdownList(_ rawEntry: String)
func removeFromMarkdownList(_ entry: String)
```

New `UserDefaults` key `"userMarkdownList"`. `policy` (the computed
`AppPolicy`) passes both `userDenylist` and `userMarkdownList` through.

### `SettingsView`

Add `MarkdownListSection`, structurally a near-duplicate of
`DenylistSection`: same "Add Running App…" menu, same "Choose App…" button,
same row view (icon, display name, bundle ID, remove button). No "excluded
automatically" disclosure group, since there's no built-in list.

- Heading: "Use markdown links in"
- Explanation: "For apps whose rich-text paste doesn't work — e.g. Slack
  with 'Format messages with markup' on. Adds `[text](url)` as plain text
  instead."

Placed as a new section in `SettingsView.body`, alongside `DenylistSection`
and `LastPasteSection`.

## Testing

- `LinkPayloadBuilderTests` (or a new test file): `buildMarkdown` produces
  `[text](url)` for plain input, and correctly escapes `\`, `[`, `]` in the
  selection text without touching the URL.
- `AppPolicyTests`: `usesMarkdownLinks` matches exact bundle IDs and
  dotted-prefix entries the same way `allowsLinkPaste`'s denylist check
  does; returns `false` for a `nil`/empty bundle ID.
- `PasteEngine`-level test (if the existing test harness supports mocking
  the pasteboard/frontmost app): with a bundle ID in `markdownList`, the
  pasteboard after a link-paste contains only a `.string` entry with markdown
  syntax — no `.rtf`/`.html` entries.
