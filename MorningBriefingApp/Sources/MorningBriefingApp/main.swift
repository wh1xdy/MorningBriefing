import AppKit

// Entry point — AppDelegate is instantiated and the run loop started here.
// NSApplicationMain handles main-thread bootstrapping so AppDelegate can
// safely access @MainActor-isolated types in its delegate callbacks.
let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
