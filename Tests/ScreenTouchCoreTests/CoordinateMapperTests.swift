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
