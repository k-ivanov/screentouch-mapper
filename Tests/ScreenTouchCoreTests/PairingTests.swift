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
