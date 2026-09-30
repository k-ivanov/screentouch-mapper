import AppKit
import ServiceManagement
import ScreenTouchCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let manager = SessionManager()
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hand.point.up.left",
                                           accessibilityDescription: "ScreenTouch Mapper")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.manager.reconcile()
        }

        Permissions.requestMissing()
        manager.start()
        watchPermissions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.stopAll()
    }

    /// Starts the saved pairings as soon as both permissions are granted, without a restart.
    private func watchPermissions() {
        guard !Permissions.allGranted else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard Permissions.allGranted else { return }
            timer.invalidate()
            self?.manager.reconcile()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        manager.reconcile()
        menu.removeAllItems()

        if !Permissions.accessibility {
            menu.addItem(ActionMenuItem("⚠ Accessibility needed…") { Permissions.openAccessibilitySettings() })
        }
        if !Permissions.inputMonitoring {
            menu.addItem(ActionMenuItem("⚠ Input Monitoring needed…") { Permissions.openInputMonitoringSettings() })
        }
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }

        menu.addItem(ActionMenuItem("Touchscreens", enabled: false))
        let devices = manager.devices
        if devices.isEmpty {
            menu.addItem(ActionMenuItem("No absolute-pointer devices found", enabled: false))
        }
        for device in devices {
            menu.addItem(deviceItem(for: device))
        }

        menu.addItem(.separator())
        let loginEnabled = SMAppService.mainApp.status == .enabled
        menu.addItem(ActionMenuItem("Start at Login", state: loginEnabled ? .on : .off) {
            do {
                if loginEnabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                NSLog("ScreenTouch Mapper: could not change the login item: \(error)")
            }
        })
        menu.addItem(ActionMenuItem("Quit ScreenTouch Mapper") { NSApp.terminate(nil) })
    }

    private func deviceItem(for device: PointerDevice) -> NSMenuItem {
        let pairing = manager.pairing(for: device)
        var title = device.name + (device.looksLikeTablet ? " (tablet?)" : "")
        if case .seizeFailed = manager.state(for: device) {
            title += " — ⚠ Could not take exclusive access"
        }
        let item = ActionMenuItem(title, state: pairing == nil ? .off : .on)

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(ActionMenuItem("Off", state: pairing == nil ? .on : .off) { [weak self] in
            self?.manager.assign(nil, to: device)
        })
        for display in manager.displays {
            let selected = pairing?.display.matches(display.key) == true
            let name = display.name + (display.isBuiltin ? " (built-in)" : "")
            submenu.addItem(ActionMenuItem(name, state: selected ? .on : .off) { [weak self] in
                self?.manager.assign(display, to: device)
            })
        }
        submenu.addItem(.separator())
        submenu.addItem(ActionMenuItem("Flip Horizontally", state: pairing?.flipX == true ? .on : .off,
                                       enabled: pairing != nil) { [weak self] in
            self?.manager.toggleFlip(horizontal: true, for: device)
        })
        submenu.addItem(ActionMenuItem("Flip Vertically", state: pairing?.flipY == true ? .on : .off,
                                       enabled: pairing != nil) { [weak self] in
            self?.manager.toggleFlip(horizontal: false, for: device)
        })
        item.submenu = submenu
        return item
    }
}
