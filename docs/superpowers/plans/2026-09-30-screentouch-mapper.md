# ScreenTouch Mapper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu bar app that pins any mouse-mode (absolute-pointer) touchscreen to a display that the user selects.

**Architecture:** A Swift package with a UI-free library `ScreenTouchCore` (pure mapping and click logic, pairing storage, thin IOKit/CoreGraphics adapters) and an executable `ScreenTouchMapper` (AppKit status item, session manager, permissions). A `Session` seizes one HID interface, reads its absolute X/Y/button values through an `IOHIDQueue`, maps them onto the paired display, and posts `CGEvent`s.

**Tech Stack:** Swift 5.9+, SwiftPM, XCTest, IOKit HID, CoreGraphics, AppKit, ServiceManagement, Make.

**Spec:** `docs/superpowers/specs/2026-09-30-screentouch-mapper-design.md`

**Status:** Completed 2026-09-30. Changes made during execution are listed in section 11 of the spec.

## Global Constraints

- Platform floor: macOS 13 (`.macOS(.v13)`, `LSMinimumSystemVersion` 13.0). Build universal (arm64 + x86_64).
- No third-party dependencies.
- Product name `ScreenTouch Mapper`; bundle `ScreenTouch Mapper.app`; bundle ID `com.kivanov.ScreenTouchMapper`; package `ScreenTouchMapper`; library target `ScreenTouchCore`; app target `ScreenTouchMapper`; release asset `ScreenTouchMapper-<version>.zip`.
- Pairings file: `~/Library/Application Support/ScreenTouch Mapper/pairings.json`.
- Single touch only: move, tap, drag, double-tap. No gestures.
- Never seize a device the user has not paired. No auto-pairing.
- Ad-hoc signing (`codesign --sign -`); no notarization.
- Commit format: subject `NO-TICKET <Title>` ≤ 50 chars total, body wrapped at 50, no file lists or test names.
- Do not push; the user pushes or asks for it explicitly.

## Review Focus

- A descriptor axis with zero span (logical min == max) must not crash or divide by zero; the point falls on the display origin. → test in Task 1.
- A target display left of or above the main display (negative global origin) must receive the touches. → test in Task 1.
- A finger still down when the session stops (display unplugged, pairing set to Off, app quits) must produce a button-up, or the system keeps a stuck mouse button. → test in Task 2.
- Two devices of the same model: with serial numbers they must not cross-match; without serial numbers the USB location decides. → test in Task 3.
- A missing or damaged `pairings.json`, or a missing Application Support folder, must give an empty list on load and a created folder on save. → test in Task 3.

---

### Task 1: Package scaffold and CoordinateMapper

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/ScreenTouchCore/CoordinateMapper.swift`
- Create: `Sources/ScreenTouchMapper/main.swift` (placeholder entry point so the package builds)
- Test: `Tests/ScreenTouchCoreTests/CoordinateMapperTests.swift`

**Interfaces:**
- Produces: `struct AxisRange: Codable, Equatable { var min: Int; var max: Int }`,
  `enum CoordinateMapper { static func map(rawX: Int, rawY: Int, rangeX: AxisRange, rangeY: AxisRange, bounds: CGRect, flipX: Bool = false, flipY: Bool = false) -> CGPoint }`

- [x] **Step 1: Write the package files**

`Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScreenTouchMapper",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ScreenTouchCore"),
        .executableTarget(name: "ScreenTouchMapper", dependencies: ["ScreenTouchCore"]),
        .testTarget(name: "ScreenTouchCoreTests", dependencies: ["ScreenTouchCore"]),
    ]
)
```

`.gitignore`:

```
.build/
.swiftpm/
build/
.DS_Store
```

`Sources/ScreenTouchMapper/main.swift`:

```swift
import ScreenTouchCore
```

- [x] **Step 2: Write the failing tests**

`Tests/ScreenTouchCoreTests/CoordinateMapperTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import ScreenTouchCore

final class CoordinateMapperTests: XCTestCase {
    let range = AxisRange(min: 0, max: 1000)
    let bounds = CGRect(x: 1728, y: 0, width: 1920, height: 1080)

    private func map(_ x: Int, _ y: Int, flipX: Bool = false, flipY: Bool = false) -> CGPoint {
        CoordinateMapper.map(rawX: x, rawY: y, rangeX: range, rangeY: range,
                             bounds: bounds, flipX: flipX, flipY: flipY)
    }

    func testTopLeftCorner() {
        XCTAssertEqual(map(0, 0), CGPoint(x: 1728, y: 0))
    }

    func testBottomRightCornerStaysInsideBounds() {
        XCTAssertEqual(map(1000, 1000), CGPoint(x: 1728 + 1919, y: 1079))
    }

    func testCentre() {
        XCTAssertEqual(map(500, 500), CGPoint(x: 1728 + 959.5, y: 539.5))
    }

    func testFlippedAxes() {
        XCTAssertEqual(map(0, 0, flipX: true, flipY: true), CGPoint(x: 1728 + 1919, y: 1079))
    }

    func testNonZeroLogicalMinimum() {
        let p = CoordinateMapper.map(rawX: 100, rawY: 1100,
                                     rangeX: AxisRange(min: 100, max: 1100),
                                     rangeY: AxisRange(min: 100, max: 1100), bounds: bounds)
        XCTAssertEqual(p, CGPoint(x: 1728, y: 1079))
    }

    func testOutOfRangeValuesAreClamped() {
        XCTAssertEqual(map(-50, 5000), CGPoint(x: 1728, y: 1079))
    }

    func testDisplayWithNegativeOrigin() {
        let left = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let p = CoordinateMapper.map(rawX: 0, rawY: 1000, rangeX: range, rangeY: range, bounds: left)
        XCTAssertEqual(p, CGPoint(x: -1920, y: -200 + 1079))
    }

    func testZeroSpanAxisDoesNotCrash() {
        let flat = AxisRange(min: 5, max: 5)
        let p = CoordinateMapper.map(rawX: 5, rawY: 5, rangeX: flat, rangeY: flat, bounds: bounds)
        XCTAssertEqual(p, CGPoint(x: 1728, y: 0))
    }
}
```

- [x] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter CoordinateMapperTests`
Expected: FAIL — compile error, `cannot find 'AxisRange' in scope`.

- [x] **Step 4: Write the implementation**

`Sources/ScreenTouchCore/CoordinateMapper.swift`:

```swift
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
```

- [x] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter CoordinateMapperTests`
Expected: PASS, 8 tests.

- [x] **Step 6: Commit**

```bash
git add Package.swift .gitignore Sources Tests
git commit -F - <<'EOF'
NO-TICKET Map absolute HID positions to a display

Mouse-mode touchscreens report absolute X/Y in
their own logical range. The mapper scales that
range onto the paired display, including screens
at negative origins and descriptors with a flat
axis.
EOF
```

---

### Task 2: ClickStateMachine

**Files:**
- Create: `Sources/ScreenTouchCore/ClickStateMachine.swift`
- Test: `Tests/ScreenTouchCoreTests/ClickStateMachineTests.swift`

**Interfaces:**
- Produces: `enum PointerEvent: Equatable { case move(CGPoint); case down(CGPoint, clickCount: Int); case drag(CGPoint); case up(CGPoint, clickCount: Int) }`,
  `struct ClickStateMachine { init(doubleClickInterval: TimeInterval = 0.5, doubleClickDistance: CGFloat = 20); mutating func update(isDown: Bool, point: CGPoint, time: TimeInterval) -> [PointerEvent]; mutating func cancel(at point: CGPoint) -> [PointerEvent] }`

- [x] **Step 1: Write the failing tests**

`Tests/ScreenTouchCoreTests/ClickStateMachineTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import ScreenTouchCore

final class ClickStateMachineTests: XCTestCase {
    let a = CGPoint(x: 100, y: 100)
    let b = CGPoint(x: 300, y: 300)

    func testTapProducesMoveDownUp() {
        var m = ClickStateMachine()
        XCTAssertEqual(m.update(isDown: true, point: a, time: 0), [.move(a), .down(a, clickCount: 1)])
        XCTAssertEqual(m.update(isDown: false, point: a, time: 0.1), [.up(a, clickCount: 1)])
    }

    func testHeldPressProducesDrag() {
        var m = ClickStateMachine()
        _ = m.update(isDown: true, point: a, time: 0)
        XCTAssertEqual(m.update(isDown: true, point: b, time: 0.1), [.drag(b)])
        XCTAssertEqual(m.update(isDown: false, point: b, time: 0.2), [.up(b, clickCount: 1)])
    }

    func testDoubleTapInTimeAndNear() {
        var m = ClickStateMachine()
        _ = m.update(isDown: true, point: a, time: 0)
        _ = m.update(isDown: false, point: a, time: 0.1)
        let near = CGPoint(x: 105, y: 105)
        XCTAssertEqual(m.update(isDown: true, point: near, time: 0.3), [.move(near), .down(near, clickCount: 2)])
        XCTAssertEqual(m.update(isDown: false, point: near, time: 0.4), [.up(near, clickCount: 2)])
    }

    func testTripleTapCountsThree() {
        var m = ClickStateMachine()
        for (i, t) in [0.0, 0.3, 0.6].enumerated() {
            let events = m.update(isDown: true, point: a, time: t)
            XCTAssertEqual(events.last, .down(a, clickCount: i + 1))
            _ = m.update(isDown: false, point: a, time: t + 0.1)
        }
    }

    func testSecondTapTooLateIsASingleClick() {
        var m = ClickStateMachine()
        _ = m.update(isDown: true, point: a, time: 0)
        _ = m.update(isDown: false, point: a, time: 0.1)
        XCTAssertEqual(m.update(isDown: true, point: a, time: 0.8).last, .down(a, clickCount: 1))
    }

    func testSecondTapTooFarIsASingleClick() {
        var m = ClickStateMachine()
        _ = m.update(isDown: true, point: a, time: 0)
        _ = m.update(isDown: false, point: a, time: 0.1)
        XCTAssertEqual(m.update(isDown: true, point: b, time: 0.3).last, .down(b, clickCount: 1))
    }

    func testReleaseWithoutPressIsOnlyAMove() {
        var m = ClickStateMachine()
        XCTAssertEqual(m.update(isDown: false, point: a, time: 0), [.move(a)])
    }

    func testCancelWhilePressedReleasesTheButton() {
        var m = ClickStateMachine()
        _ = m.update(isDown: true, point: a, time: 0)
        XCTAssertEqual(m.cancel(at: b), [.up(b, clickCount: 1)])
        XCTAssertEqual(m.update(isDown: false, point: b, time: 0.1), [.move(b)])
    }

    func testCancelWhileReleasedDoesNothing() {
        var m = ClickStateMachine()
        XCTAssertEqual(m.cancel(at: a), [])
    }
}
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ClickStateMachineTests`
Expected: FAIL — compile error, `cannot find 'ClickStateMachine' in scope`.

- [x] **Step 3: Write the implementation**

`Sources/ScreenTouchCore/ClickStateMachine.swift`:

```swift
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
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ClickStateMachineTests`
Expected: PASS, 9 tests.

- [x] **Step 5: Commit**

```bash
git add Sources/ScreenTouchCore/ClickStateMachine.swift Tests/ScreenTouchCoreTests/ClickStateMachineTests.swift
git commit -F - <<'EOF'
NO-TICKET Turn touch button states into clicks

The controller only reports whether a finger is
down. Apps need move, down, drag and up events
with a click count for double-clicks, and a held
press must be released when a session stops.
EOF
```

---

### Task 3: Pairing keys and PairingStore

**Files:**
- Create: `Sources/ScreenTouchCore/Pairing.swift`
- Create: `Sources/ScreenTouchCore/PairingStore.swift`
- Test: `Tests/ScreenTouchCoreTests/PairingTests.swift`

**Interfaces:**
- Produces:
  - `struct DeviceKey: Codable, Hashable { var vendorID: Int; var productID: Int; var serialNumber: String; var locationID: Int; func matches(_ other: DeviceKey) -> Bool }`
  - `struct DisplayKey: Codable, Hashable { var vendor: UInt32; var model: UInt32; var serialNumber: UInt32; var displayID: UInt32; func matches(_ other: DisplayKey) -> Bool }`
  - `struct Pairing: Codable, Equatable { var device: DeviceKey; var display: DisplayKey; var flipX: Bool; var flipY: Bool }`
  - `extension Array where Element == Pairing { func pairing(for device: DeviceKey) -> Pairing?; mutating func setPairing(_ pairing: Pairing?, for device: DeviceKey) }`
  - `struct PairingStore { init(fileURL: URL = PairingStore.defaultURL); static var defaultURL: URL; func load() -> [Pairing]; func save(_ pairings: [Pairing]) throws }`

- [x] **Step 1: Write the failing tests**

`Tests/ScreenTouchCoreTests/PairingTests.swift`:

```swift
import XCTest
@testable import ScreenTouchCore

final class PairingTests: XCTestCase {
    let verbatim = DeviceKey(vendorID: 0x27c0, productID: 0x859, serialNumber: "", locationID: 0x0210_0000)
    let display = DisplayKey(vendor: 0x1234, model: 0x0001, serialNumber: 0, displayID: 4)
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testDeviceWithoutSerialMatchesByLocation() {
        var sameSpot = verbatim
        var otherPort = verbatim
        otherPort.locationID = 0x0110_0000
        sameSpot.serialNumber = ""
        XCTAssertTrue(verbatim.matches(sameSpot))
        XCTAssertFalse(verbatim.matches(otherPort))
    }

    func testDevicesWithSerialsMatchBySerialOnly() {
        let one = DeviceKey(vendorID: 1, productID: 2, serialNumber: "A", locationID: 10)
        var moved = one
        moved.locationID = 20
        var twin = one
        twin.serialNumber = "B"
        XCTAssertTrue(one.matches(moved))
        XCTAssertFalse(one.matches(twin))
    }

    func testDifferentModelNeverMatches() {
        var other = verbatim
        other.productID = 0x860
        XCTAssertFalse(verbatim.matches(other))
    }

    func testDisplayMatchesBySerialThenByID() {
        let withSerial = DisplayKey(vendor: 1, model: 2, serialNumber: 99, displayID: 4)
        var renumbered = withSerial
        renumbered.displayID = 7
        XCTAssertTrue(withSerial.matches(renumbered))
        var noSerialMoved = display
        noSerialMoved.displayID = 5
        XCTAssertFalse(display.matches(noSerialMoved))
        XCTAssertTrue(display.matches(display))
    }

    func testSetPairingReplacesAndRemoves() {
        var list: [Pairing] = []
        list.setPairing(Pairing(device: verbatim, display: display), for: verbatim)
        var flipped = Pairing(device: verbatim, display: display)
        flipped.flipX = true
        list.setPairing(flipped, for: verbatim)
        XCTAssertEqual(list, [flipped])
        XCTAssertEqual(list.pairing(for: verbatim), flipped)
        list.setPairing(nil, for: verbatim)
        XCTAssertEqual(list, [])
    }

    func testStoreRoundTripCreatesFolder() throws {
        let store = PairingStore(fileURL: tempDir.appendingPathComponent("sub/pairings.json"))
        let pairings = [Pairing(device: verbatim, display: display, flipX: true, flipY: false)]
        try store.save(pairings)
        XCTAssertEqual(store.load(), pairings)
    }

    func testMissingFileLoadsEmpty() {
        let store = PairingStore(fileURL: tempDir.appendingPathComponent("none.json"))
        XCTAssertEqual(store.load(), [])
    }

    func testDamagedFileLoadsEmpty() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let url = tempDir.appendingPathComponent("pairings.json")
        try Data("{ not json".utf8).write(to: url)
        XCTAssertEqual(PairingStore(fileURL: url).load(), [])
    }

    func testDefaultURL() {
        XCTAssertTrue(PairingStore.defaultURL.path.hasSuffix(
            "Library/Application Support/ScreenTouch Mapper/pairings.json"))
    }
}
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter PairingTests`
Expected: FAIL — compile error, `cannot find 'DeviceKey' in scope`.

- [x] **Step 3: Write the implementation**

`Sources/ScreenTouchCore/Pairing.swift`:

```swift
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
```

`Sources/ScreenTouchCore/PairingStore.swift`:

```swift
import Foundation

public struct PairingStore {
    public let fileURL: URL

    public init(fileURL: URL = PairingStore.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenTouch Mapper", isDirectory: true)
            .appendingPathComponent("pairings.json")
    }

    /// A missing or unreadable file gives an empty list.
    public func load() -> [Pairing] {
        guard let data = try? Data(contentsOf: fileURL),
              let pairings = try? JSONDecoder().decode([Pairing].self, from: data)
        else { return [] }
        return pairings
    }

    public func save(_ pairings: [Pairing]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(pairings).write(to: fileURL, options: .atomic)
    }
}
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `swift test`
Expected: PASS, all 26 tests.

- [x] **Step 5: Commit**

```bash
git add Sources/ScreenTouchCore/Pairing.swift Sources/ScreenTouchCore/PairingStore.swift Tests/ScreenTouchCoreTests/PairingTests.swift
git commit -F - <<'EOF'
NO-TICKET Save device-to-display pairings

A pairing must survive replugs, restarts and
display rearrangement. Serial numbers identify a
device or display when present; otherwise the USB
location or display ID decides. A damaged file
must not stop the app from starting.
EOF
```

---

### Task 4: HID and display adapters

These parts talk to IOKit and CoreGraphics and are not unit tested. The deliverable is a `--list` diagnostic that proves they work on real hardware.

**Files:**
- Create: `Sources/ScreenTouchCore/PointerDevice.swift`
- Create: `Sources/ScreenTouchCore/DeviceScanner.swift`
- Create: `Sources/ScreenTouchCore/DisplayInfo.swift`
- Create: `Sources/ScreenTouchCore/EventPoster.swift`
- Create: `Sources/ScreenTouchCore/Session.swift`
- Create: `Sources/ScreenTouchMapper/DiagnosticList.swift`
- Modify: `Sources/ScreenTouchMapper/main.swift`

**Interfaces:**
- Consumes: `AxisRange`, `CoordinateMapper.map`, `ClickStateMachine`, `PointerEvent`, `DeviceKey`, `DisplayKey`, `Pairing` (Tasks 1–3).
- Produces:
  - `struct PointerDevice: Identifiable, Equatable { id: UInt64; key: DeviceKey; name: String; rangeX: AxisRange; rangeY: AxisRange; xCookie, yCookie, buttonCookie: IOHIDElementCookie; looksLikeTablet: Bool; init?(hidDevice: IOHIDDevice); static func registryID(of: IOHIDDevice) -> UInt64? }`
  - `final class DeviceScanner { var devices: [UInt64: (info: PointerDevice, device: IOHIDDevice)]; var onChange: (() -> Void)?; func start() }`
  - `struct DisplayInfo: Equatable { id: CGDirectDisplayID; name: String; key: DisplayKey; bounds: CGRect; isBuiltin: Bool; static func current() -> [DisplayInfo] }` and `extension Array where Element == DisplayInfo { func display(matching: DisplayKey) -> DisplayInfo? }`
  - `protocol EventPoster { func post(_ event: PointerEvent) }`, `struct CGEventPoster: EventPoster`
  - `final class Session { enum State: Equatable { case idle, running, seizeFailed(Int32) }; state: State; display: DisplayInfo; pairing: Pairing; init(device: IOHIDDevice, info: PointerDevice, display: DisplayInfo, pairing: Pairing, poster: EventPoster); func start(); func stop() }`

- [x] **Step 1: Write `PointerDevice.swift`**

```swift
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
```

- [x] **Step 2: Write `DeviceScanner.swift`**

```swift
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

    private func add(_ device: IOHIDDevice) {
        guard let info = PointerDevice(hidDevice: device) else { return }
        devices[info.id] = (info, device)
        onChange?()
    }

    private func remove(_ device: IOHIDDevice) {
        guard let id = PointerDevice.registryID(of: device),
              devices.removeValue(forKey: id) != nil
        else { return }
        onChange?()
    }
}
```

- [x] **Step 3: Write `DisplayInfo.swift`**

```swift
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
```

- [x] **Step 4: Write `EventPoster.swift`**

```swift
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
```

- [x] **Step 5: Write `Session.swift`**

```swift
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
        let queue = IOHIDQueueCreate(kCFAllocatorDefault, device, 64, IOOptionBits(kIOHIDOptionsTypeNone))
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
```

- [x] **Step 6: Write the `--list` diagnostic**

`Sources/ScreenTouchMapper/DiagnosticList.swift`:

```swift
import Foundation
import ScreenTouchCore

/// `ScreenTouchMapper --list`: prints the absolute-pointer devices and the displays.
enum DiagnosticList {
    static func run() {
        let scanner = DeviceScanner()
        scanner.start()
        CFRunLoopRunInMode(.defaultMode, 0.5, false)

        print("Absolute-pointer devices:")
        let devices = scanner.devices.values.map(\.info).sorted { $0.name < $1.name }
        if devices.isEmpty { print("  (none)") }
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
```

`Sources/ScreenTouchMapper/main.swift`:

```swift
import Foundation
import ScreenTouchCore

if CommandLine.arguments.contains("--list") {
    DiagnosticList.run()
    exit(0)
}
```

- [x] **Step 7: Build and run the diagnostic**

Run: `swift build 2>&1 | grep -E 'error|warning: ' ; swift run ScreenTouchMapper --list`
Expected: no errors. The device list contains `TouchScreen … vendor=0x27c0 product=0x0859 … X 0…16383  Y 0…9599`. The trackpad and relative mice are not listed. The display list contains `Built-in Retina Display (built-in)` and `32402`.

- [x] **Step 8: Run all tests**

Run: `swift test`
Expected: PASS, all 26 tests.

- [x] **Step 9: Commit**

```bash
git add Sources
git commit -F - <<'EOF'
NO-TICKET Read absolute pointers and post clicks

Adds the IOKit and CoreGraphics adapters: find
HID interfaces with absolute X/Y, describe the
displays, seize one interface per session and
post mouse events on its display. The --list
flag shows what the app can see on a machine.
EOF
```

---

### Task 5: Menu bar app and packaging

**Files:**
- Create: `Sources/ScreenTouchMapper/Permissions.swift`
- Create: `Sources/ScreenTouchMapper/SessionManager.swift`
- Create: `Sources/ScreenTouchMapper/ActionMenuItem.swift`
- Create: `Sources/ScreenTouchMapper/AppDelegate.swift`
- Modify: `Sources/ScreenTouchMapper/main.swift`
- Create: `Resources/Info.plist`
- Create: `Makefile`

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces: `make test`, `make app` → `build/ScreenTouch Mapper.app`, `make zip` → `build/ScreenTouchMapper-1.0.0.zip`.

- [x] **Step 1: Write `Permissions.swift`**

```swift
import AppKit
import IOKit.hid

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var inputMonitoring: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    static var allGranted: Bool { accessibility && inputMonitoring }

    /// Adds the app to both lists in System Settings and shows the system prompts.
    static func requestMissing() {
        if !accessibility {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if !inputMonitoring {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    static func openAccessibilitySettings() { open("Privacy_Accessibility") }
    static func openInputMonitoringSettings() { open("Privacy_ListenEvent") }

    private static func open(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [x] **Step 2: Write `SessionManager.swift`**

```swift
import Foundation
import ScreenTouchCore

/// Keeps one session per paired, connected device whose display is connected.
final class SessionManager {
    private let scanner = DeviceScanner()
    private let store = PairingStore()
    private let poster = CGEventPoster()
    private var sessions: [UInt64: Session] = [:]
    private(set) var pairings: [Pairing]
    private(set) var displays: [DisplayInfo] = []

    init() {
        pairings = store.load()
    }

    var devices: [PointerDevice] {
        scanner.devices.values.map(\.info).sorted { $0.name < $1.name }
    }

    func start() {
        scanner.onChange = { [weak self] in self?.reconcile() }
        scanner.start()
        reconcile()
    }

    func pairing(for device: PointerDevice) -> Pairing? {
        pairings.pairing(for: device.key)
    }

    func state(for device: PointerDevice) -> Session.State? {
        sessions[device.id]?.state
    }

    /// Pairs `device` with `display`, or turns it off when `display` is nil.
    func assign(_ display: DisplayInfo?, to device: PointerDevice) {
        let old = pairing(for: device)
        let new = display.map {
            Pairing(device: device.key, display: $0.key, flipX: old?.flipX ?? false, flipY: old?.flipY ?? false)
        }
        pairings.setPairing(new, for: device.key)
        persist()
        reconcile()
    }

    func toggleFlip(horizontal: Bool, for device: PointerDevice) {
        guard var pairing = pairing(for: device) else { return }
        if horizontal { pairing.flipX.toggle() } else { pairing.flipY.toggle() }
        pairings.setPairing(pairing, for: device.key)
        persist()
        sessions[device.id]?.pairing = pairing
    }

    /// Starts, updates or stops sessions to match devices, displays, pairings and permissions.
    func reconcile() {
        displays = DisplayInfo.current()
        let live = scanner.devices
        let granted = Permissions.allGranted

        for (id, session) in sessions where live[id] == nil {
            session.stop()
            sessions[id] = nil
        }

        for (id, entry) in live {
            guard granted,
                  let pairing = pairings.pairing(for: entry.info.key),
                  let display = displays.display(matching: pairing.display)
            else {
                sessions[id]?.stop()
                sessions[id] = nil
                continue
            }
            let session = sessions[id] ?? Session(device: entry.device, info: entry.info,
                                                  display: display, pairing: pairing, poster: poster)
            session.display = display
            session.pairing = pairing
            if session.state != .running { session.start() }
            sessions[id] = session
        }
    }

    func stopAll() {
        sessions.values.forEach { $0.stop() }
        sessions.removeAll()
    }

    private func persist() {
        do {
            try store.save(pairings)
        } catch {
            NSLog("ScreenTouch Mapper: could not save pairings: \(error)")
        }
    }
}
```

- [x] **Step 3: Write `ActionMenuItem.swift`**

```swift
import AppKit

/// A menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, state: NSControl.StateValue = .off, enabled: Bool = true, handler: @escaping () -> Void = {}) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        self.state = state
        isEnabled = enabled
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func fire() {
        handler()
    }
}
```

- [x] **Step 4: Write `AppDelegate.swift`**

```swift
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
```

- [x] **Step 5: Update `main.swift`**

```swift
import AppKit
import ScreenTouchCore

if CommandLine.arguments.contains("--list") {
    DiagnosticList.run()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [x] **Step 6: Write `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>com.kivanov.ScreenTouchMapper</string>
	<key>CFBundleName</key>
	<string>ScreenTouch Mapper</string>
	<key>CFBundleDisplayName</key>
	<string>ScreenTouch Mapper</string>
	<key>CFBundleExecutable</key>
	<string>ScreenTouchMapper</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2026 Konstantin Ivanov. MIT licence.</string>
</dict>
</plist>
```

- [x] **Step 7: Write the `Makefile`**

```make
APP_NAME := ScreenTouch Mapper
BUILD    := build
APP      := $(BUILD)/$(APP_NAME).app
VERSION  := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
SWIFT_RELEASE := swift build -c release --arch arm64 --arch x86_64

.PHONY: test app zip clean

test:
	swift test

app:
	$(SWIFT_RELEASE)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp "$$($(SWIFT_RELEASE) --show-bin-path)/ScreenTouchMapper" "$(APP)/Contents/MacOS/ScreenTouchMapper"
	codesign --force --sign - "$(APP)"

zip: app
	cd "$(BUILD)" && rm -f "ScreenTouchMapper-$(VERSION).zip" && \
		ditto -c -k --keepParent "$(APP_NAME).app" "ScreenTouchMapper-$(VERSION).zip"

clean:
	rm -rf .build "$(BUILD)"
```

- [x] **Step 8: Build the app and the zip**

Run: `make test && make zip && lipo -archs "build/ScreenTouch Mapper.app/Contents/MacOS/ScreenTouchMapper" && codesign -dv "build/ScreenTouch Mapper.app" 2>&1 | grep -E 'Identifier|Signature'`
Expected: tests PASS; `x86_64 arm64`; `Identifier=com.kivanov.ScreenTouchMapper`; `Signature=adhoc`; `build/ScreenTouchMapper-1.0.0.zip` exists.

- [x] **Step 9: Commit**

```bash
git add Sources Resources Makefile
git commit -F - <<'EOF'
NO-TICKET Add the menu bar app and packaging

Users pair a device with a display from the menu
bar, so no config file is needed. Sessions follow
device, display and permission changes, and the
device returns to macOS whenever its display is
gone. make zip produces the release archive.
EOF
```

---

### Task 6: README, manual test and cleanup

**Files:**
- Modify: `README.md`

- [x] **Step 1: Write `README.md`**

````markdown
# ScreenTouch Mapper

A macOS menu bar app that pins a **mouse-mode touchscreen** to its own display.

## The problem

Many cheap USB touchscreens (for example the Verbatim PMT-15 portable monitor)
run their touch controller in *mouse mode*: every touch arrives as an absolute
mouse position. macOS has no touchscreen support, so it moves the pointer on the
display that has focus. With a second display, your touch lands on the wrong
screen.

ScreenTouch Mapper takes exclusive access to that mouse interface and sends each
touch to the display you choose.

## Does my screen need this?

Your screen probably runs in mouse mode when:

- a touch moves the pointer, but on the display that has focus, and
- `hidutil list` shows a `UsagePage 1 / Usage 2` (mouse) entry for the touchscreen.

After installation, run:

```sh
"/Applications/ScreenTouch Mapper.app/Contents/MacOS/ScreenTouchMapper" --list
```

Your touchscreen must appear under *Absolute-pointer devices*.

Screens that send real multi-touch data are not mouse-mode screens. For those,
use [Touch Up](https://github.com/shueber/Touch-Up).

## Install

1. Download `ScreenTouchMapper-<version>.zip` from the releases page and unzip it.
2. Move **ScreenTouch Mapper.app** to **Applications**.
3. The app is not notarized. At the first start, right-click the app and select
   **Open**, then click **Open** again.
4. Grant both permissions in **System Settings → Privacy & Security**:
   - **Input Monitoring**: to take exclusive access to the touchscreen.
   - **Accessibility**: to send clicks.
5. Click the hand icon in the menu bar, open your touchscreen and select its display.
6. Optional: turn on **Start at Login** in the same menu.

## Use

| Touch | Result |
|---|---|
| Tap | Click |
| Two quick taps | Double-click |
| Touch and move | Drag |

If the touches are mirrored, turn on **Flip Horizontally** or **Flip Vertically**
in the device menu.

## Limits

- Single touch only. Scroll and pinch gestures are not supported, because
  mouse-mode controllers report one point.
- The app never takes a device by itself. Drawing tablets also report absolute
  positions; they are marked "(tablet?)" in the menu.
- When you quit the app, or the paired display disconnects, the touchscreen
  goes back to the default macOS behaviour.

## Build from source

Requires Xcode 15 or later.

```sh
make test   # run the unit tests
make app    # build "build/ScreenTouch Mapper.app" (universal, ad-hoc signed)
make zip    # build "build/ScreenTouchMapper-<version>.zip"
```

Each ad-hoc build has a new signature. After you install a new build, grant the
two permissions again.

## Licence

MIT. See [LICENSE](LICENSE).
````

- [x] **Step 2: Commit the README**

```bash
git add README.md
git commit -F - <<'EOF'
NO-TICKET Document install, use and limits

Users must understand what mouse mode is, how to
check their screen, and why the app needs two
permissions and a right-click Open at first
start.
EOF
```

- [x] **Step 3: Install and grant permissions**

Run: `pkill -f VerbatimTouch.app; rm -rf "/Applications/ScreenTouch Mapper.app" && cp -R "build/ScreenTouch Mapper.app" /Applications/ && open "/Applications/ScreenTouch Mapper.app"`
Then the user adds the app in Input Monitoring and Accessibility.

- [x] **Step 4: Manual test with the Verbatim PMT-15**

1. In the menu, select the Verbatim display for `TouchScreen`. Give focus to a window on the built-in display, then tap, drag and double-tap on the Verbatim. Expected: all land on the Verbatim.
2. Unplug the Verbatim USB-C cable and plug it in again. Expected: touches land on the Verbatim again without any menu action.
3. Quit the app. Expected: touches follow the focused display again (default macOS behaviour).

- [x] **Step 5: Remove the prototype after the user confirms the test**

Run: `rm -rf /Applications/VerbatimTouch.app ~/Developer/VerbatimTouch`
The user removes the `VerbatimTouch` entries from Accessibility and Input Monitoring.
