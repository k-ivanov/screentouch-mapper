import Foundation
import IOKit.hid
import ScreenTouchCore

/// `ScreenTouchMapper --list`: prints the absolute-pointer devices and the displays.
enum DiagnosticList {
    static func run() {
        let scanner = DeviceScanner()
        scanner.start()
        CFRunLoopRunInMode(.defaultMode, 0.5, false)

        print("Absolute-pointer devices:")
        let devices = scanner.devices.values.map(\.info).sorted { $0.name < $1.name }
        if devices.isEmpty {
            print("  (none)")
            if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
                print("  Grant Input Monitoring to this terminal app, or the devices cannot be read.")
            }
        }
        for d in devices {
            print("  \(d.name)\(d.looksLikeTablet ? " (tablet?)" : "")"
                  + "  vendor=\(hex(d.key.vendorID, 4)) product=\(hex(d.key.productID, 4))"
                  + " location=\(hex(d.key.locationID, 8)) serial=\"\(d.key.serialNumber)\""
                  + "  X \(d.rangeX.min)…\(d.rangeX.max)  Y \(d.rangeY.min)…\(d.rangeY.max)")
        }

        print("Displays:")
        for display in DisplayInfo.current() {
            print("  \(display.name)\(display.isBuiltin ? " (built-in)" : "")  id=\(display.id)"
                  + "  bounds=\(display.bounds)")
        }
    }

    private static func hex(_ value: Int, _ digits: Int) -> String {
        "0x" + String(value, radix: 16).leftPadded(to: digits)
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: Swift.max(0, length - count)) + self
    }
}
