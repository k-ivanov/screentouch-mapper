import CoreGraphics

public protocol EventPoster {
    func post(_ event: PointerEvent)
}

/// Posts left-button mouse events into the HID event stream. Needs Accessibility.
public struct CGEventPoster: EventPoster {
    public init() {}

    public func post(_ event: PointerEvent) {
        let type: CGEventType
        let point: CGPoint
        var clickCount: Int?
        switch event {
        case .move(let p): type = .mouseMoved; point = p
        case .down(let p, let count): type = .leftMouseDown; point = p; clickCount = count
        case .drag(let p): type = .leftMouseDragged; point = p
        case .up(let p, let count): type = .leftMouseUp; point = p; clickCount = count
        }
        guard let cgEvent = CGEvent(mouseEventSource: nil, mouseType: type,
                                    mouseCursorPosition: point, mouseButton: .left)
        else { return }
        if let clickCount {
            cgEvent.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        }
        cgEvent.post(tap: .cghidEventTap)
    }
}
