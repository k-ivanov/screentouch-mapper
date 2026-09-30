import Foundation

/// Identifies one HID interface across reconnects.
public struct DeviceKey: Codable, Hashable {
    public var vendorID: Int
    public var productID: Int
    public var serialNumber: String
    public var locationID: Int

    public init(vendorID: Int, productID: Int, serialNumber: String, locationID: Int) {
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.locationID = locationID
    }

    /// Same model, and the same serial number when both have one, else the same USB location.
    public func matches(_ other: DeviceKey) -> Bool {
        guard vendorID == other.vendorID, productID == other.productID else { return false }
        if !serialNumber.isEmpty && !other.serialNumber.isEmpty {
            return serialNumber == other.serialNumber
        }
        return locationID == other.locationID
    }
}

/// Identifies one display across restarts and layout changes.
public struct DisplayKey: Codable, Hashable {
    public var vendor: UInt32
    public var model: UInt32
    public var serialNumber: UInt32
    public var displayID: UInt32

    public init(vendor: UInt32, model: UInt32, serialNumber: UInt32, displayID: UInt32) {
        self.vendor = vendor
        self.model = model
        self.serialNumber = serialNumber
        self.displayID = displayID
    }

    /// Same model, and the same serial number when both have one, else the same display ID.
    public func matches(_ other: DisplayKey) -> Bool {
        guard vendor == other.vendor, model == other.model else { return false }
        if serialNumber != 0 && other.serialNumber != 0 {
            return serialNumber == other.serialNumber
        }
        return displayID == other.displayID
    }
}

public struct Pairing: Codable, Equatable {
    public var device: DeviceKey
    public var display: DisplayKey
    public var flipX: Bool
    public var flipY: Bool

    public init(device: DeviceKey, display: DisplayKey, flipX: Bool = false, flipY: Bool = false) {
        self.device = device
        self.display = display
        self.flipX = flipX
        self.flipY = flipY
    }
}

extension Array where Element == Pairing {
    public func pairing(for device: DeviceKey) -> Pairing? {
        first { $0.device.matches(device) }
    }

    /// Replaces the pairing of `device`, or removes it when `pairing` is nil.
    public mutating func setPairing(_ pairing: Pairing?, for device: DeviceKey) {
        removeAll { $0.device.matches(device) }
        if let pairing { append(pairing) }
    }
}
