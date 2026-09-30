import CoreGraphics
import Foundation

public enum PointerEvent: Equatable {
    case move(CGPoint)
    case down(CGPoint, clickCount: Int)
    case drag(CGPoint)
    case up(CGPoint, clickCount: Int)
}

/// Turns the button state of successive HID reports into mouse events.
public struct ClickStateMachine {
    public var doubleClickInterval: TimeInterval
    public var doubleClickDistance: CGFloat

    private var isDown = false
    private var lastDownPoint: CGPoint?
    private var lastDownTime: TimeInterval = 0
    private var clickCount = 0

    public init(doubleClickInterval: TimeInterval = 0.5, doubleClickDistance: CGFloat = 20) {
        self.doubleClickInterval = doubleClickInterval
        self.doubleClickDistance = doubleClickDistance
    }

    public mutating func update(isDown down: Bool, point: CGPoint, time: TimeInterval) -> [PointerEvent] {
        defer { isDown = down }
        switch (isDown, down) {
        case (false, true):
            if let last = lastDownPoint,
               time - lastDownTime <= doubleClickInterval,
               hypot(point.x - last.x, point.y - last.y) <= doubleClickDistance {
                clickCount += 1
            } else {
                clickCount = 1
            }
            lastDownPoint = point
            lastDownTime = time
            return [.move(point), .down(point, clickCount: clickCount)]
        case (true, true):
            return [.drag(point)]
        case (true, false):
            return [.up(point, clickCount: clickCount)]
        case (false, false):
            return [.move(point)]
        }
    }

    /// Releases a held press, for example when the session stops mid-touch.
    public mutating func cancel(at point: CGPoint) -> [PointerEvent] {
        guard isDown else { return [] }
        isDown = false
        return [.up(point, clickCount: clickCount)]
    }
}
