import AudioToolbox
import CoreAudio

/// Volume and mute of the default output device, through CoreAudio. Look the
/// device up again for every key press: the default output changes whenever
/// headphones or a display are connected.
struct SystemVolume {
    let device: AudioObjectID

    /// The current default output device; `nil` when there is none.
    static func defaultOutput() -> SystemVolume? {
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
        return SystemVolume(device: device)
    }

    /// Whether the volume can be changed. The virtual main volume covers devices
    /// that only expose per-channel volumes; without it, the system handles the keys.
    var canSetVolume: Bool { isSettable(Self.volumeAddress) }

    var canSetMute: Bool { isSettable(Self.muteAddress) }

    /// The level in 0…1.
    var volume: Float? {
        var value: Float32 = 0
        return read(Self.volumeAddress, into: &value) ? value : nil
    }

    /// `nil` when the device has no mute control.
    var isMuted: Bool? {
        var value: UInt32 = 0
        return read(Self.muteAddress, into: &value) ? value != 0 : nil
    }

    func setVolume(_ volume: Float) {
        var value = Float32(volume)
        write(Self.volumeAddress, value: &value)
    }

    func setMuted(_ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        write(Self.muteAddress, value: &value)
    }

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

    private func write<Value: BitwiseCopyable>(_ address: AudioObjectPropertyAddress, value: inout Value) {
        var address = address
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Value>.size), &value)
    }
}
