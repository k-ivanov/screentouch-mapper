import AppKit
import IOKit.hid

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var inputMonitoring: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    static var allGranted: Bool { accessibility && inputMonitoring }

    /// Adds the app to both lists in System Settings and shows the system prompts.
    static func requestMissing() {
        if !accessibility {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if !inputMonitoring {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    static func openAccessibilitySettings() { open("Privacy_Accessibility") }
    static func openInputMonitoringSettings() { open("Privacy_ListenEvent") }

    private static func open(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
