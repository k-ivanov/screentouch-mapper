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
        scanner.rescan()
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
