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
