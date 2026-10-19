import AppKit

Timing.mark("main")
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
