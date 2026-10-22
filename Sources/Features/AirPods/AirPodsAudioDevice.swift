import AudioToolbox
import CoreAudio

/// The CoreAudio output device of the connected AirPods: its volume and, through
/// private BTAudioHAL properties, its noise-control mode. Look it up again for
/// every refresh; the audio route can appear later than the Bluetooth link.
/// `defaultOutput()` wraps the default output device the same way, for the
/// notice that the Mac's speakers took over.
struct AirPodsAudioDevice {
    let device: AudioObjectID

    /// The current default output device; `nil` when there is none.
    static func defaultOutput() -> AirPodsAudioDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        guard status == noErr, device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return AirPodsAudioDevice(device: device)
    }

    /// The Mac's own speakers. On Apple silicon their UID is "BuiltInSpeakerDevice";
    /// the headphone jack is a separate built-in device ("BuiltInHeadphoneOutputDevice").
    var isBuiltInSpeaker: Bool {
        var transport: UInt32 = 0
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard read(address, into: &transport), transport == kAudioDeviceTransportTypeBuiltIn else { return false }
        return string(kAudioDevicePropertyDeviceUID)?.contains("Speaker") == true
    }

    /// The Bluetooth output device whose UID carries `address`, else the one named
    /// `name`; `nil` when there is none (yet).
    static func find(address: String?, name: String?) -> AirPodsAudioDevice? {
        for device in allDevices() {
            let candidate = AirPodsAudioDevice(device: device)
            guard candidate.isBluetooth, candidate.hasOutputStreams else { continue }
            if AudioDeviceMatching.matches(
                uid: candidate.string(kAudioDevicePropertyDeviceUID),
                name: candidate.string(kAudioObjectPropertyName),
                address: address,
                deviceName: name
            ) {
                return candidate
            }
        }
        return nil
    }

    // MARK: Volume

    var canSetVolume: Bool { isSettable(Self.volumeAddress) }

    /// The level in 0…1.
    var volume: Float? {
        var value: Float32 = 0
        return read(Self.volumeAddress, into: &value) ? value : nil
    }

    func setVolume(_ volume: Float) {
        var value = Float32(min(max(volume, 0), 1))
        write(Self.volumeAddress, value: &value)
    }

    /// `nil` when the device has no mute control.
    var isMuted: Bool? {
        var value: UInt32 = 0
        return read(Self.muteAddress, into: &value) ? value != 0 : nil
    }

    // MARK: Noise control (private)

    /// The raw `'lstm'` value; 1 is Off, see `ListeningMode` for the rest.
    var listeningModeRawValue: UInt32? {
        guard has(Self.listeningModeAddress) else { return nil }
        var value: UInt32 = 0
        return read(Self.listeningModeAddress, into: &value) ? value : nil
    }

    /// The `'lsms'` support mask; `nil` when the device has none.
    var supportedListeningModeMask: UInt32? {
        guard has(Self.supportedListeningModesAddress) else { return nil }
        var value: UInt32 = 0
        return read(Self.supportedListeningModesAddress, into: &value) ? value : nil
    }

    var canSetListeningMode: Bool {
        isSettable(Self.listeningModeAddress) && dataSize(Self.listeningModeAddress) == UInt32(MemoryLayout<UInt32>.size)
    }

    /// Whether the write was accepted. The HAL caches the value optimistically, so
    /// only reading it back later shows whether the AirPods took it.
    @discardableResult
    func setListeningMode(_ mode: ListeningMode) -> Bool {
        guard canSetListeningMode else { return false }
        var value = mode.rawValue
        return write(Self.listeningModeAddress, value: &value)
    }

    // MARK: Addresses

    private static let volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    /// `'lstm'`: the current noise-control mode (UInt32, settable).
    private static let listeningModeAddress = AudioObjectPropertyAddress(
        mSelector: 0x6C73_746D,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    /// `'lsms'`: the supported noise-control modes (UInt32 bitmask, read-only).
    private static let supportedListeningModesAddress = AudioObjectPropertyAddress(
        mSelector: 0x6C73_6D73,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    // MARK: Helpers

    private static func allDevices() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return Array(devices.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private var isBluetooth: Bool {
        var transport: UInt32 = 0
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard read(address, into: &transport) else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private var hasOutputStreams: Bool {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        return (dataSize(address) ?? 0) > 0
    }

    private func string(_ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private func has(_ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(device, &address)
    }

    private func dataSize(_ address: AudioObjectPropertyAddress) -> UInt32? {
        var address = address
        var size: UInt32 = 0
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr
        else { return nil }
        return size
    }

    private func isSettable(_ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private func read<Value: BitwiseCopyable>(_ address: AudioObjectPropertyAddress, into value: inout Value) -> Bool {
        var address = address
        var size = UInt32(MemoryLayout<Value>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
    }

    @discardableResult
    private func write<Value: BitwiseCopyable>(_ address: AudioObjectPropertyAddress, value: inout Value) -> Bool {
        var address = address
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Value>.size), &value) == noErr
    }
}

/// Calls `onChange` whenever a property of the audio system changes, such as the
/// device list (AirPods connecting for audio or switching to another device) or
/// the default output device.
@MainActor
final class AudioHardwareObserver {
    private let address: AudioObjectPropertyAddress
    private let onChange: @MainActor () -> Void
    /// Removing a listener takes the very block that was added.
    private var listener: AudioObjectPropertyListenerBlock?

    init(property: AudioObjectPropertySelector, onChange: @escaping @MainActor () -> Void) {
        address = AudioObjectPropertyAddress(
            mSelector: property,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        self.onChange = onChange
    }

    isolated deinit {
        stop()
    }

    /// `false` when CoreAudio refuses the listener.
    @discardableResult
    func start() -> Bool {
        guard listener == nil else { return true }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // Added with the main queue below, so it always runs on the main thread.
            MainActor.assumeIsolated {
                self?.onChange()
            }
        }
        var address = address
        guard AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, listener
        ) == noErr else { return false }
        self.listener = listener
        return true
    }

    func stop() {
        guard let listener else { return }
        var address = address
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        self.listener = nil
    }
}
