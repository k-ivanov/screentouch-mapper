import AppKit
import ScreenTouchCore

if CommandLine.arguments.contains("--list") {
    DiagnosticList.run()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
