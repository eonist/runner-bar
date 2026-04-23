import AppKit

// Must be called before NSApplication.shared
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon

let delegate = AppDelegate()
app.delegate = delegate
app.run()
