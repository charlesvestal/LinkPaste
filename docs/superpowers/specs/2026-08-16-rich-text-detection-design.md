# Detecting whether a destination can render a link

## Problem

LinkPaste writes RTF, HTML and plain text to the pasteboard and lets the
destination pick. That works, but the app never finds out *which* flavor was
taken, so it cannot tell a rich composer from a plain text field. Three
consequences:

1. **Plain fields keep getting the full treatment.** A synthetic ⌘C fires into
   them, the clipboard is swapped, and the selection is replaced by whatever the
   plain flavor happens to be — every time, forever, with no way to learn better.
2. **The plain flavor was the selected text**, so the one moment it is read is
   the one moment the user's ⌘V silently does nothing: no link, no URL, no
   feedback.
3. **The restore delay is a guess** (`docs/DESIGN.md`, "things that will bite").
   Nothing tells us when the destination has finished reading.

The manual `markdownList` exists because of (1): the user has to predict, per
app, what the app is going to do.

## Goal

Determine, per destination, whether it renders a hyperlink — reliably enough to
act on, cheaply enough to do on every paste, and without inserting anything into
the user's document.

## Non-goals

- **No test insertion.** Pasting a probe string and undoing it is visible, relies
  on ⌘Z behaving, and can only be done in a document the user is already editing.
- **No AX inspection as the primary signal.** Roles do not answer the question:
  a `<textarea>` and a contenteditable are both `AXTextArea`, and an
  `NSTextView` with `isRichText = false` is indistinguishable from one without.
  AX is used only for *identity*, not for the verdict.
- **No auto-downgrade when a link fails to stick.** Verifying the pasted range
  through AX would need `AXLink` vs `.link` attribute handling that varies by
  app; a wrong downgrade silently disables the feature where it works. The user
  pins it instead.

## Design

### `PromisedPaste` (LinkPasteCore)

Write the flavors as *promised* data instead of finished data.
`NSPasteboardItem.setDataProvider(_:forTypes:)` advertises the types and AppKit
calls back when a flavor is actually read — including across processes, which is
the case that matters. The type requested is the verdict:

| Requested | Verdict |
| --- | --- |
| `public.rtf`, `public.html` | `.rich` |
| `public.utf8-plain-text` | `.plain` |
| nothing | no verdict — the ⌘V never landed in a text field |

Rich wins over plain when both are read, since editors commonly check for plain
text before taking the rich flavor.

```swift
public final class PromisedPaste: NSObject, NSPasteboardItemDataProvider {
    public init(payloads: [NSPasteboard.PasteboardType: Data])
    public func write(to pasteboard: NSPasteboard) -> Bool
    public func waitForRead(timeout: TimeInterval, settle: TimeInterval = 0.05) -> DestinationKind?
    public var observedKind: DestinationKind? { get }
    public func stillOwnsPasteboard(_ pasteboard: NSPasteboard) -> Bool
}
```

Every flavor is served from precomputed `Data`, so the callback is a dictionary
lookup with no work that could block the destination. It carries the transient
type so clipboard managers neither record the item nor read flavors and pollute
the observation.

`waitForRead` returns on the first read rather than sleeping a fixed delay, which
is what fixes the restore timing; `stillOwnsPasteboard` compares the change count
so a restore never overwrites a copy the user made in the meantime.

### `DestinationLedger` + `DestinationContext` (LinkPasteCore)

Verdicts are stored against bundle ID + AX role + AX subrole + enclosing page
host. The host is what stops one browser verdict answering for every site.

Entries expire after 30 days so a redesigned app heals on its own. A pinned entry
is a user override: it never expires and no observation overwrites it.

### `DestinationInspector` (LinkPasteApp)

Builds a `DestinationContext` from the focused element: role, subrole, and a
bounded (8 hop) walk up to the enclosing `AXWebArea` for the page host. Reuses
`SelectionReader.focusedElement()`, so Electron's accessibility tree gets woken
the same way it already does.

### `LedgerStore` (LinkPasteApp)

Owns the ledger, its lock, and its `UserDefaults` persistence, and publishes a
summary for Settings. `Settings` skips locking on purpose — its values are single
words — but a dictionary read on the paste queue while the main thread writes is
a real race, so this one is locked.

### `PasteEngine`

- Identify the destination before reading the selection.
- **Known plain** → `passThrough` immediately, before the ⌘C probe fires a real
  keystroke into a field that cannot use the result.
- Otherwise build the payload, write it through `PromisedPaste`, post ⌘V, then
  `waitForRead` → record the verdict → restore if still ours.
- Markdown mode is unchanged and unprobed: only one flavor goes out, so the
  destination's read says nothing about what it can render.

### `LinkPayload.plain`

Becomes the URL rather than the selected text, overridable via
`build(text:url:plainText:)`. This reverses an earlier decision deliberately: the
old value made a mis-detected paste invisible, and `docs/DESIGN.md` sets the bar
at "a confused LinkPaste should feel like a LinkPaste that isn't running".

### `Settings` / `SettingsView`

- New `usesMarkdownInPlainDestinations` toggle (default off): apply the markdown
  treatment wherever a destination *turns out* to be plain, rather than only where
  the user predicted it. This is `markdownList` without the prediction.
- New "Learned fields" section: what the last destination was judged to be, a
  **Treat as Plain Text** pin, and **Forget Learned Fields**.

## Testing

- `PromisedPasteTests` — against a private named pasteboard, since an in-process
  read resolves the promise through the same path a cross-process paste does:
  each flavor is served correctly; rtf/html read as rich; string as plain; rich
  wins when plain is read first; silence yields no verdict; `waitForRead` returns
  on the read rather than the timeout; `stillOwnsPasteboard` goes false after
  another writer.
- `DestinationLedgerTests` — separate verdicts per role and per host, later
  observations win, expiry, pins beating both expiry and observation, encode/decode
  round trip, garbage and pre-pinning JSON decode without dropping the ledger.
- `LinkPayloadTests` — plain flavor is the URL, override works, `flavors` covers
  every promised type.
- Manual (`docs/MANUAL_TESTING.md`): the first paste into a new plain field
  behaves like an ordinary paste, and the second one is not intercepted at all.
