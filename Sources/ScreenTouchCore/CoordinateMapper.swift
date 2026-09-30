import CoreGraphics

/// Logical range of one HID axis, taken from the report descriptor.
public struct AxisRange: Codable, Equatable {
    public var min: Int
    public var max: Int

    public init(min: Int, max: Int) {
        self.min = min
        self.max = max
    }
}

public enum CoordinateMapper {
    /// Maps a raw absolute HID position onto `bounds`, which is in global
    /// display coordinates (top-left origin, may be negative).
    public static func map(rawX: Int, rawY: Int, rangeX: AxisRange, rangeY: AxisRange,
                           bounds: CGRect, flipX: Bool = false, flipY: Bool = false) -> CGPoint {
        let tx = normalized(rawX, in: rangeX, flip: flipX)
        let ty = normalized(rawY, in: rangeY, flip: flipY)
        return CGPoint(x: bounds.minX + tx * Swift.max(bounds.width - 1, 0),
                       y: bounds.minY + ty * Swift.max(bounds.height - 1, 0))
    }

    static func normalized(_ raw: Int, in range: AxisRange, flip: Bool) -> CGFloat {
        let span = range.max - range.min
        guard span > 0 else { return 0 }
        let t = Swift.min(Swift.max(CGFloat(raw - range.min) / CGFloat(span), 0), 1)
        return flip ? 1 - t : t
    }
}
