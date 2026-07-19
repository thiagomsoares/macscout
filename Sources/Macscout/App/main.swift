import AppKit

// Macscout is an LSUIElement agent app: no Dock icon, lives in the menu bar
// and in a notch-style floating panel.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
    // Keep the delegate alive for the app's lifetime.
    objc_setAssociatedObject(app, &delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
    app.run()
}

private var delegateKey: UInt8 = 0
