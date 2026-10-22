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

/// Follows which supported AirPods are connected, through IOBluetooth's connect
/// and disconnect notifications. Calls `onChange` with the most recently
/// connected one (`nil` when none is left) and whether it just connected; AirPods
/// already connected when monitoring starts do not count as just connected.
///
/// Only start it once Bluetooth access is granted (see `BluetoothAuthorizer`).
@MainActor
final class AirPodsMonitor: NSObject {
    private struct Tracked {
        let device: IOBluetoothDevice
        let disconnectNotification: IOBluetoothUserNotification?
    }

    private let onChange: @MainActor (_ current: IOBluetoothDevice?, _ isNewConnection: Bool) -> Void
    private var connectNotification: IOBluetoothUserNotification?
    /// Connected supported AirPods by address, oldest first in `order`.
    private var tracked: [String: Tracked] = [:]
    private var order: [String] = []
    /// False once stopped, so a notification already on its way does nothing.
    private var isRunning = false

    init(onChange: @escaping @MainActor (_ current: IOBluetoothDevice?, _ isNewConnection: Bool) -> Void) {
        self.onChange = onChange
    }

    isolated deinit {
        stop()
    }

    var current: IOBluetoothDevice? {
        order.last.flatMap { tracked[$0]?.device }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] where device.isConnected() {
            track(device)
        }
        if current != nil {
            onChange(current, false)
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        connectNotification?.unregister()
        connectNotification = nil
        for entry in tracked.values {
            entry.disconnectNotification?.unregister()
        }
        tracked = [:]
        order = []
    }

    /// Starts following `device` if it is a supported AirPods not yet tracked.
    @discardableResult
    private func track(_ device: IOBluetoothDevice) -> Bool {
        guard
            let address = device.addressString,
            tracked[address] == nil,
            device.airPodsProduct != nil
        else { return false }
        let notification = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )
        tracked[address] = Tracked(device: device, disconnectNotification: notification)
        order.append(address)
        return true
    }

    // IOBluetooth delivers both notifications on its own queue, not on the main
    // thread they were registered from (macOS 27 uses its coordinator queue). The
    // device object is not Sendable, so only its address crosses to the main
    // queue, where the device is looked up again. `DispatchQueue.main` keeps a
    // connect and a disconnect in the order they arrived.

    @objc private nonisolated func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.connected(address: address)
            }
        }
    }

    @objc private nonisolated func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.disconnected(address: address)
            }
        }
    }

    private func connected(address: String) {
        // Also fires for devices already connected and for failed attempts.
        guard
            isRunning,
            let device = IOBluetoothDevice(addressString: address),
            device.isConnected(),
            track(device)
        else { return }
        onChange(device, true)
    }

    private func disconnected(address: String) {
        guard isRunning, let entry = tracked.removeValue(forKey: address) else { return }
        entry.disconnectNotification?.unregister()
        order.removeAll { $0 == address }
        onChange(current, false)
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
