import AppKit

// No storyboard, no @main — an executable SwiftPM target owns its own entry
// point, so the app is wired up by hand. `.accessory` keeps LinkPaste out of the
// Dock and the ⌘-Tab switcher; the menu bar is the whole interface.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
