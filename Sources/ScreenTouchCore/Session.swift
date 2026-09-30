import Foundation
import IOKit.hid

/// One active pairing: seizes the device and turns its reports into mouse events on the display.
public final class Session {
    public enum State: Equatable {
        case idle
        case running
        case seizeFailed(Int32)
    }

    public private(set) var state: State = .idle
    public var display: DisplayInfo
    public var pairing: Pairing

    private let device: IOHIDDevice
    private let info: PointerDevice
    private let poster: EventPoster
    private var machine = ClickStateMachine()
    private var queue: IOHIDQueue?
    private var rawX = 0
    private var rawY = 0
    private var buttonDown = false
    private var lastPoint = CGPoint.zero

    public init(device: IOHIDDevice, info: PointerDevice, display: DisplayInfo, pairing: Pairing, poster: EventPoster) {
        self.device = device
        self.info = info
        self.display = display
        self.pairing = pairing
        self.poster = poster
    }

    public func start() {
        guard state != .running else { return }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            state = .seizeFailed(result)
            return
        }
        guard let queue = IOHIDQueueCreate(kCFAllocatorDefault, device, 64, IOOptionBits(kIOHIDOptionsTypeNone)) else {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            state = .seizeFailed(kIOReturnNoMemory)
            return
        }
        for cookie in [info.xCookie, info.yCookie, info.buttonCookie] {
            if let element = element(for: cookie) { IOHIDQueueAddElement(queue, element) }
        }
        IOHIDQueueRegisterValueAvailableCallback(queue, { context, _, _ in
            Unmanaged<Session>.fromOpaque(context!).takeUnretainedValue().drainQueue()
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDQueueScheduleWithRunLoop(queue, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDQueueStart(queue)
        self.queue = queue
        state = .running
    }

    /// Releases a held press, stops reading and gives the device back to macOS.
    public func stop() {
        guard state == .running else {
            state = .idle
            return
        }
        for event in machine.cancel(at: lastPoint) { poster.post(event) }
        if let queue {
            IOHIDQueueStop(queue)
            IOHIDQueueUnscheduleFromRunLoop(queue, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
        queue = nil
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        state = .idle
    }

    private func element(for cookie: IOHIDElementCookie) -> IOHIDElement? {
        let match = [kIOHIDElementCookieKey: cookie] as CFDictionary
        return (IOHIDDeviceCopyMatchingElements(device, match, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement])?.first
    }

    private func drainQueue() {
        guard let queue else { return }
        var changed = false
        while let value = IOHIDQueueCopyNextValueWithTimeout(queue, 0) {
            let cookie = IOHIDElementGetCookie(IOHIDValueGetElement(value))
            let integer = IOHIDValueGetIntegerValue(value)
            switch cookie {
            case info.xCookie: rawX = integer
            case info.yCookie: rawY = integer
            case info.buttonCookie: buttonDown = integer != 0
            default: continue
            }
            changed = true
        }
        guard changed else { return }
        let point = CoordinateMapper.map(rawX: rawX, rawY: rawY, rangeX: info.rangeX, rangeY: info.rangeY,
                                         bounds: display.bounds, flipX: pairing.flipX, flipY: pairing.flipY)
        lastPoint = point
        let now = ProcessInfo.processInfo.systemUptime
        for event in machine.update(isDown: buttonDown, point: point, time: now) { poster.post(event) }
    }
}
