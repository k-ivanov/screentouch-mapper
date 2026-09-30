import AppKit

public struct DisplayInfo: Equatable {
    public var id: CGDirectDisplayID
    public var name: String
    public var key: DisplayKey
    /// Global display coordinates, top-left origin.
    public var bounds: CGRect
    public var isBuiltin: Bool

    public init(id: CGDirectDisplayID, name: String, key: DisplayKey, bounds: CGRect, isBuiltin: Bool) {
        self.id = id
        self.name = name
        self.key = key
        self.bounds = bounds
        self.isBuiltin = isBuiltin
    }

    public static func current() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }

        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[number.uint32Value] = screen.localizedName
            }
        }

        return ids.prefix(Int(count)).map { id in
            DisplayInfo(id: id,
                        name: names[id] ?? "Display \(id)",
                        key: DisplayKey(vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                                        serialNumber: CGDisplaySerialNumber(id), displayID: id),
                        bounds: CGDisplayBounds(id),
                        isBuiltin: CGDisplayIsBuiltin(id) != 0)
        }
    }
}

extension Array where Element == DisplayInfo {
    public func display(matching key: DisplayKey) -> DisplayInfo? {
        first { $0.key.matches(key) }
    }
}
