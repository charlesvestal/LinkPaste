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
| Rich vs. plain | Promise the flavors and watch which one the destination reads | Not a heuristic that correlates with rich text: it is the destination app making the exact decision we need, observed directly. Inspecting the focused element only ever yields guesses, and a test insertion has to be undone. |
| URL matching | Schemes + bare domains on a curated TLD set | Slack's liberal feel without linking `README.md`. |
| App shape | Menu bar app + settings window | Losing the permission is silent, and so is being toggled off; the app needs somewhere to say which, plus a fast off switch. |
| Distribution | Developer ID, notarized, direct download | Not a choice: event taps and AX are unavailable to sandboxed apps, so the App Store is impossible. |
| Signing | Locally, never in CI | CI signing needs the Developer ID private key in repository secrets. That key signs every product under this identity, so a leak means revoking, reissuing, and re-signing all of them — a bad trade for skipping one local script. |

## Structure

Pure logic lives in `LinkPasteCore` and is unit tested. Everything that touches
the system lives in `LinkPasteApp` and is covered by `docs/MANUAL_TESTING.md`.

```
LinkPasteCore                     LinkPasteApp
  URLDetector                       EventTapController    tap lifecycle, re-enable
  LinkPayloadBuilder                SelectionReader       AX + ⌘C probe
  AppPolicy                         DestinationInspector  AX role / subrole / page host
  PasteboardSnapshot                KeyPoster             synthetic ⌘V / ⌘C
  PromisedPaste                     LedgerStore           thread safety + persistence
  DestinationLedger                 PasteEngine           orchestration
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
identify the destination → *if it's a known plain-text field, hand the keystroke
straight back* → read the selection (AX, then ⌘C probe) → build RTF + HTML +
plain payload → write it as promised data → post synthetic ⌘V → wait for the
destination to read a flavor → record what it read → restore the snapshot.

Every branch that isn't a successful link-paste ends by posting a plain ⌘V. A
confused LinkPaste should feel like a LinkPaste that isn't running. The plain
flavor is the URL for the same reason: it is only ever read when we were wrong,
and the paste the user would have got anyway beats a ⌘V that appears to do
nothing.

## Knowing whether a field can render a link

The pasteboard is written as *promised* data. Instead of finished bytes, it
advertises the flavors and AppKit calls back into `PromisedPaste` when the
destination reads one — `public.rtf`/`public.html` for a rich field,
`public.utf8-plain-text` for a plain one. That callback is not a proxy for the
answer; it is the destination performing the decision, at no visible cost.

Verdicts are keyed by bundle ID + AX role + subrole + enclosing page host, so
Gmail's composer and a GitHub comment box in the same browser are separate
destinations. A field known to read plain text is never intercepted again: no
clipboard swap, no ⌘C, nothing re-posted.

Reads are only interpreted, never inferred. Nothing read means the ⌘V never
landed in a text field, which teaches us nothing — treating silence as "plain"
would fill the ledger with fields that were never pasted into.

## Things that will bite

**The restore delay is no longer a guess, mostly.** A promised flavor's first
read is the signal that the app has taken what it wanted, so the restore happens
on that rather than on a timer, and `restoreDelay` is now only the ceiling on how
long to wait for an app that never reads at all. The remaining exposure is an app
that reads a *second* time later; the restore also checks the change count first,
so at worst it declines to restore rather than overwriting someone else's copy.
The markdown path still uses the flat delay — it writes one plain flavor, so
there is no read to wait on.

**A field can read the rich flavor and drop the link anyway.** Editors that
flatten formatting on paste are indistinguishable from ones that render it: they
genuinely do read `public.rtf`, right up until they discard the attribute.
Nothing observable at the pasteboard catches this, so Settings shows the last
verdict and lets the user pin it to plain instead.

**Synthetic event recursion.** Our own ⌘V re-enters our own tap. Every event we
post carries a signature in `eventSourceUserData`; the callback checks it first.
Without that the app pastes into itself forever.

**Accessibility trust disappears silently.** It's keyed to the designated
requirement (bundle ID + Team ID), so it survives ordinary Developer ID updates —
but it's dropped when the signing identity changes, and on every rebuild of an
ad-hoc-signed dev build, whose signature is identified by its hash. Whichever
happens, `tapCreate` just returns nil and ⌘V goes quietly back to normal.
`PermissionsMonitor` polls so the menu bar can say so instead of the app looking
dead.

**The ⌘C probe is a real keystroke in someone else's app.** Harmless in a text
editor; not something to fire into a password manager, hence the denylist. It's
also why the probe is user-disableable.

**Clipboard destruction is the unforgivable failure.** We overwrite the
clipboard twice per paste. Restore runs on every path, including the ones that
bail out early, and `PasteboardSnapshot` copies every type on every item rather
than just the string.
