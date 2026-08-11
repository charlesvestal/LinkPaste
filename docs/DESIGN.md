# LinkPaste — design

## The problem

Slack, Notion, Jira and Bear all implement one small nicety: paste a URL over
selected text and the text becomes a link rather than being replaced. macOS has
no system-wide equivalent, so every other rich-text field on the machine makes
you open a link dialog instead.

Prior art, and why none of it fits:

- **In-app implementations** — solve it one app at a time; nothing to reuse.
- **Keyboard Maestro / PopClip macros** — exist, work, but bind to ⌘K or a popup
  button rather than ⌘V, and mostly emit Markdown rather than rich text. They're
  a deliberate "make a link" gesture, which is the thing we're trying to avoid.
- **Command X, OpenPaste** — different purposes, but both ship the global-⌘V
  interception this design depends on, which is good evidence the approach holds
  up outside a prototype.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Trigger | Hijack ⌘V globally, with a denylist | The whole value is not having to think about it. A separate shortcut is just a worse ⌘K. |
| Selection read | Accessibility first, synthetic ⌘C as fallback | AX alone is dead in browser web content and much of Electron — i.e. where most rich-text editing happens. |
| URL matching | Schemes + bare domains on a curated TLD set | Slack's liberal feel without linking `README.md`. |
| App shape | Menu bar app + settings window | Permission revocation is silent and frequent; the app needs somewhere to say so, and a fast off switch. |
| Distribution | Developer ID, notarized, direct download | Not a choice: event taps and AX are unavailable to sandboxed apps, so the App Store is impossible. |

## Structure

Pure logic lives in `LinkPasteCore` and is unit tested. Everything that touches
the system lives in `LinkPasteApp` and is covered by `docs/MANUAL_TESTING.md`.

```
LinkPasteCore                     LinkPasteApp
  URLDetector                       EventTapController   tap lifecycle, re-enable
  LinkPayloadBuilder                SelectionReader      AX + ⌘C probe
  AppPolicy                         KeyPoster            synthetic ⌘V / ⌘C
  PasteboardSnapshot                PasteEngine          orchestration
                                    PermissionsMonitor
                                    AppDelegate / SettingsView
```

## The paste, step by step

Split across two threads deliberately. The event tap callback runs under a
watchdog — block it and macOS silently disables the tap, after which ⌘V stops
working everywhere with no error surfaced anywhere. So the callback only does
cheap work.

**On the tap thread** (must be fast): app enabled? not already mid-paste? front
app allowed? clipboard holds a URL? All yes → swallow the event and hand off.

**On a serial background queue**: snapshot the clipboard → re-read the URL →
read the selection (AX, then ⌘C probe) → build RTF + HTML + plain payload →
write it → post synthetic ⌘V → wait → restore the snapshot.

Every branch that isn't a successful link-paste ends by posting a plain ⌘V. A
confused LinkPaste should feel like a LinkPaste that isn't running.

## Things that will bite

**The restore delay is a guess.** No app signals when it has finished reading the
pasteboard. Restore too early and a slow app pastes the user's *previous*
clipboard — the worst failure this app can produce, because it's silent and
wrong rather than merely absent. Default 250 ms, user-adjustable, no way to
detect the right value.

**Synthetic event recursion.** Our own ⌘V re-enters our own tap. Every event we
post carries a signature in `eventSourceUserData`; the callback checks it first.
Without that the app pastes into itself forever.

**Accessibility trust is revoked on every signature change.** Every rebuild in
development, every update in the wild. It fails silently — `tapCreate` just
returns nil. `PermissionsMonitor` polls for it so the menu bar can say so.

**The ⌘C probe is a real keystroke in someone else's app.** Harmless in a text
editor; not something to fire into a password manager, hence the denylist. It's
also why the probe is user-disableable.

**Clipboard destruction is the unforgivable failure.** We overwrite the
clipboard twice per paste. Restore runs on every path, including the ones that
bail out early, and `PasteboardSnapshot` copies every type on every item rather
than just the string.
