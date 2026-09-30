import Foundation
import IOKit.hid

/// Keeps the list of connected absolute-pointer HID interfaces.
public final class DeviceScanner {
    public private(set) var devices: [UInt64: (info: PointerDevice, device: IOHIDDevice)] = [:]
    public var onChange: (() -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

    public init() {}

    public func start() {
        let matches = [kHIDUsage_GD_Mouse, kHIDUsage_GD_Pointer].map {
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: $0] as CFDictionary
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<DeviceScanner>.fromOpaque(context!).takeUnretainedValue().add(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<DeviceScanner>.fromOpaque(context!).takeUnretainedValue().remove(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Retries the devices that could not be described yet. Their elements are only
    /// readable once the device is open, and opening a pointer needs Input Monitoring.
    public func rescan() {
        guard let all = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }
        var changed = false
        for device in all {
            guard let id = PointerDevice.registryID(of: device), devices[id] == nil else { continue }
            IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            if let info = PointerDevice(hidDevice: device) {
                devices[id] = (info, device)
                changed = true
            }
        }
        if changed { onChange?() }
    }

    private func add(_ device: IOHIDDevice) {
        guard let info = PointerDevice(hidDevice: device) else { return }
        devices[info.id] = (info, device)
        onChange?()
    }

    // Matched by reference: the service of an unplugged device may already be
    // terminated, so its registry ID can no longer be read.
    private func remove(_ device: IOHIDDevice) {
        guard let id = devices.first(where: { $0.value.device == device })?.key else { return }
        devices[id] = nil
        onChange?()
    }
}
