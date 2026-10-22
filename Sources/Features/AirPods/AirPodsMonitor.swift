import CoreBluetooth
import Foundation
import IOBluetooth

/// Asks for Bluetooth access when it has not been decided yet. IOBluetooth must
/// not be touched before access is granted: without it `pairedDevices()` can
/// block forever.
@MainActor
final class BluetoothAuthorizer: NSObject, CBCentralManagerDelegate {
    /// Exists only while the system prompt is pending; creating it raises the prompt.
    private var manager: CBCentralManager?
    private var onGranted: (@MainActor () -> Void)?

    static var isGranted: Bool { CBManager.authorization == .allowedAlways }
    static var isUndecided: Bool { CBManager.authorization == .notDetermined }

    func request(onGranted: @escaping @MainActor () -> Void) {
        guard manager == nil else { return }
        self.onGranted = onGranted
        manager = CBCentralManager(delegate: self, queue: nil)
    }

    func cancel() {
        manager?.delegate = nil
        manager = nil
        onGranted = nil
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // The manager was created with a nil queue, so its delegate calls arrive
        // on the main queue.
        MainActor.assumeIsolated {
            authorizationMayHaveChanged()
        }
    }

    private func authorizationMayHaveChanged() {
        switch CBManager.authorization {
        case .notDetermined:
            // Still waiting for the user's answer; a later state update follows it.
            return
        case .allowedAlways:
            let onGranted = onGranted
            cancel()
            onGranted?()
        default:
            cancel()
        }
    }
}

/// Follows which supported AirPods are connected to this Mac, judged by their
/// CoreAudio output device: it appears when the AirPods connect for audio and
/// disappears when they disconnect or switch to another device. Calls `onChange`
/// with the most recently connected one (`nil` when none is left) and whether it
/// just connected; AirPods already connected when monitoring starts do not count
/// as just connected.
///
/// IOBluetooth's connect and disconnect notifications are not used. Its link can
/// come up minutes before the AirPods play here, or stay up while they play
/// elsewhere, and on macOS 27 its per-device disconnect notification was not
/// delivered at all. IOBluetooth only supplies the paired devices and which of
/// them are AirPods.
///
/// Only start it once Bluetooth access is granted (see `BluetoothAuthorizer`).
@MainActor
final class AirPodsMonitor {
    private let onChange: @MainActor (_ current: IOBluetoothDevice?, _ isNewConnection: Bool) -> Void
    private var observer: AudioHardwareObserver?
    /// Connected supported AirPods by address, with the addresses oldest first in `order`.
    private var devices: [String: IOBluetoothDevice] = [:]
    private var order: [String] = []

    init(onChange: @escaping @MainActor (_ current: IOBluetoothDevice?, _ isNewConnection: Bool) -> Void) {
        self.onChange = onChange
    }

    isolated deinit {
        stop()
    }

    var current: IOBluetoothDevice? {
        order.last.flatMap { devices[$0] }
    }

    func start() {
        guard observer == nil else { return }
        let observer = AudioHardwareObserver(property: kAudioHardwarePropertyDevices) { [weak self] in
            self?.update(isStart: false)
        }
        // Without the listener only the AirPods connected right now are seen.
        observer.start()
        self.observer = observer
        update(isStart: true)
    }

    func stop() {
        observer?.stop()
        observer = nil
        devices = [:]
        order = []
    }

    /// Compares the connected AirPods with the last look, and reports a change of
    /// the current one or a new arrival.
    private func update(isStart: Bool) {
        guard observer != nil else { return }
        let connected = Self.connectedAirPods()
        let previous = order.last
        order.removeAll { connected[$0] == nil }
        // Several pairs arriving at once are ordered by address, so the choice of
        // the current one is stable.
        let arrived = connected.keys.filter { !order.contains($0) }.sorted()
        order.append(contentsOf: arrived)
        devices = connected

        let isNewConnection = !isStart && !arrived.isEmpty
        guard isNewConnection || order.last != previous else { return }
        onChange(current, isNewConnection)
    }

    /// Paired AirPods that have a CoreAudio output device, by address. The audio
    /// device alone proves the connection; IOBluetooth's own connected flag may
    /// lag behind it.
    private static func connectedAirPods() -> [String: IOBluetoothDevice] {
        var connected: [String: IOBluetoothDevice] = [:]
        for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] {
            guard
                let address = device.addressString,
                device.airPodsProduct != nil,
                AirPodsAudioDevice.find(address: address, name: device.name) != nil
            else { continue }
            connected[address] = device
        }
        return connected
    }
}

extension IOBluetoothDevice {
    /// The AirPods model this device is; `nil` for anything else.
    var airPodsProduct: AirPodsProduct? {
        guard let vendorID = privateUInt16("vendorID"), let productID = privateUInt16("productID") else { return nil }
        return AirPodsProduct.lookup(vendorID: vendorID, productID: productID)
    }

    /// The levels the device reports right now. Max report only the single level.
    func airPodsBattery(for product: AirPodsProduct) -> AirPodsBattery {
        func level(_ name: String) -> Int? {
            privateUInt8(name).flatMap(AirPodsBattery.level(fromRaw:))
        }
        if product.hasSingleBattery {
            return AirPodsBattery(single: level("batteryPercentSingle"))
        }
        return AirPodsBattery(
            left: level("batteryPercentLeft"),
            right: level("batteryPercentRight"),
            chargingCase: level("batteryPercentCase")
        )
    }

    // These getters are private IOBluetooth API, so each call checks that the
    // method exists. KVC is no alternative: `value(forKey:)` raises on an unknown key.

    private func privateUInt16(_ name: String) -> UInt16? {
        let selector = NSSelectorFromString(name)
        guard responds(to: selector) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> UInt16
        return unsafeBitCast(method(for: selector), to: Getter.self)(self, selector)
    }

    private func privateUInt8(_ name: String) -> UInt8? {
        let selector = NSSelectorFromString(name)
        guard responds(to: selector) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> UInt8
        return unsafeBitCast(method(for: selector), to: Getter.self)(self, selector)
    }
}
