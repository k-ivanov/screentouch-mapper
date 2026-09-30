import Foundation
import IOKit.hid

/// One HID interface that reports an absolute X/Y position and a primary button.
public struct PointerDevice: Identifiable, Equatable {
    public var id: UInt64
    public var key: DeviceKey
    public var name: String
    public var rangeX: AxisRange
    public var rangeY: AxisRange
    public var xCookie: IOHIDElementCookie
    public var yCookie: IOHIDElementCookie
    public var buttonCookie: IOHIDElementCookie
    /// True when the interface also has pen or stylus usages (probably a drawing tablet).
    public var looksLikeTablet: Bool

    /// Nil unless the interface has absolute X and Y and a Button 1 element.
    public init?(hidDevice: IOHIDDevice) {
        guard let id = PointerDevice.registryID(of: hidDevice),
              let elements = IOHIDDeviceCopyMatchingElements(hidDevice, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]
        else { return nil }

        var x: IOHIDElement?, y: IOHIDElement?, button: IOHIDElement?
        var tablet = false
        for element in elements {
            let page = Int(IOHIDElementGetUsagePage(element))
            let usage = Int(IOHIDElementGetUsage(element))
            if page == kHIDPage_Digitizer,
               [kHIDUsage_Dig_Pen, kHIDUsage_Dig_LightPen, kHIDUsage_Dig_Stylus].contains(usage) {
                tablet = true
            }
            let type = IOHIDElementGetType(element)
            guard type == kIOHIDElementTypeInput_Misc || type == kIOHIDElementTypeInput_Button else { continue }
            if page == kHIDPage_GenericDesktop, usage == kHIDUsage_GD_X, x == nil, !IOHIDElementIsRelative(element) {
                x = element
            } else if page == kHIDPage_GenericDesktop, usage == kHIDUsage_GD_Y, y == nil, !IOHIDElementIsRelative(element) {
                y = element
            } else if page == kHIDPage_Button, usage == 1, button == nil {
                button = element
            }
        }
        guard let x, let y, let button else { return nil }

        self.id = id
        self.key = DeviceKey(vendorID: Self.intProperty(hidDevice, kIOHIDVendorIDKey),
                             productID: Self.intProperty(hidDevice, kIOHIDProductIDKey),
                             serialNumber: Self.stringProperty(hidDevice, kIOHIDSerialNumberKey),
                             locationID: Self.intProperty(hidDevice, kIOHIDLocationIDKey))
        let product = Self.stringProperty(hidDevice, kIOHIDProductKey)
        self.name = product.isEmpty ? "Unknown pointer" : product
        self.rangeX = AxisRange(min: IOHIDElementGetLogicalMin(x), max: IOHIDElementGetLogicalMax(x))
        self.rangeY = AxisRange(min: IOHIDElementGetLogicalMin(y), max: IOHIDElementGetLogicalMax(y))
        self.xCookie = IOHIDElementGetCookie(x)
        self.yCookie = IOHIDElementGetCookie(y)
        self.buttonCookie = IOHIDElementGetCookie(button)
        self.looksLikeTablet = tablet
    }

    public static func registryID(of device: IOHIDDevice) -> UInt64? {
        var id: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id) == KERN_SUCCESS else { return nil }
        return id
    }

    private static func intProperty(_ device: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    private static func stringProperty(_ device: IOHIDDevice, _ key: String) -> String {
        (IOHIDDeviceGetProperty(device, key as CFString) as? String) ?? ""
    }
}
