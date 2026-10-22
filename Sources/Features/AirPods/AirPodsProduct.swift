import Foundation

/// A supported AirPods model, identified by its Bluetooth vendor and product IDs.
struct AirPodsProduct: Equatable, Sendable {
    /// SF Symbol for the model. All of them exist on macOS 26.
    let symbol: String
    /// AirPods Max report one level (`batteryPercentSingle`) and have no case.
    let hasSingleBattery: Bool

    static let appleVendorID: UInt16 = 0x004C

    /// The AirPods model with these IDs; `nil` for anything else, Beats included.
    static func lookup(vendorID: UInt16, productID: UInt16) -> AirPodsProduct? {
        guard vendorID == appleVendorID else { return nil }
        // Product IDs from community data (github.com/raulgg/pods-control,
        // AppleAudioProducts.swift); Apple does not document them.
        switch productID {
        case 0x2002, 0x200F:
            return AirPodsProduct(symbol: "airpods", hasSingleBattery: false)
        case 0x2013:
            return AirPodsProduct(symbol: "airpods.gen3", hasSingleBattery: false)
        case 0x2019, 0x201B, 0x201C, 0x201E, 0x2020, 0x2030, 0x2036:
            return AirPodsProduct(symbol: "airpods.gen4", hasSingleBattery: false)
        case 0x200E, 0x2014, 0x2024, 0x2027:
            return AirPodsProduct(symbol: "airpods.pro", hasSingleBattery: false)
        case 0x200A, 0x201F, 0x202D:
            return AirPodsProduct(symbol: "airpods.max", hasSingleBattery: true)
        default:
            return nil
        }
    }
}

/// Battery levels in percent; `nil` where the device reports none.
struct AirPodsBattery: Equatable, Sendable {
    var left: Int?
    var right: Int?
    /// Only reported while a bud is in the case.
    var chargingCase: Int?
    /// AirPods Max.
    var single: Int?

    /// A raw level as the private getters return it: 0 means "not reported",
    /// and anything above 100 is not a percentage.
    static func level(fromRaw raw: UInt8) -> Int? {
        raw == 0 || raw > 100 ? nil : Int(raw)
    }

    /// The level worth warning about: the emptier bud, else the single battery.
    /// The case is left out, since it does not run out while listening.
    var lowestLevel: Int? {
        [left, right].compactMap { $0 }.min() ?? single
    }
}

/// A noise-control mode, as the private BTAudioHAL property `'lstm'` stores it.
/// Off (1) is not a case: it is never offered, and reads as no selection.
enum ListeningMode: UInt32, CaseIterable, Sendable {
    case noiseCancellation = 2
    case transparency = 3
    case adaptive = 4

    /// The modes in the `'lsms'` support mask, in display order. Bit 0 is noise
    /// cancellation, bit 1 transparency, bit 2 adaptive; other bits are ignored.
    /// The mask has no bit for Off.
    static func supported(mask: UInt32) -> [ListeningMode] {
        var modes: [ListeningMode] = []
        if mask & 0b001 != 0 { modes.append(.noiseCancellation) }
        if mask & 0b010 != 0 { modes.append(.transparency) }
        if mask & 0b100 != 0 { modes.append(.adaptive) }
        return modes
    }
}

/// Pairs a CoreAudio device with a Bluetooth device.
enum AudioDeviceMatching {
    /// Lowercase hex digits of `text`, everything else dropped.
    static func hexDigits(_ text: String) -> String {
        String(text.lowercased().filter(\.isHexDigit))
    }

    /// Whether a CoreAudio device UID contains the Bluetooth address
    /// ("ac-90-85-12-34-56"), whatever separators either uses.
    static func uid(_ uid: String, containsAddress address: String) -> Bool {
        let address = hexDigits(address)
        guard address.count == 12 else { return false }
        return hexDigits(uid).contains(address)
    }

    /// The UID carries the Bluetooth address ("70-AE-2A-7A-9D-7C:output" on macOS
    /// 27), but its format is not documented, so an exact name match is the fallback.
    static func matches(uid: String?, name: String?, address: String?, deviceName: String?) -> Bool {
        if let uid, let address, self.uid(uid, containsAddress: address) { return true }
        // A UID with an address of its own belongs to another device, whatever its
        // name: two pairs of AirPods can share one.
        if let uid, hexDigits(uid).count >= 12 { return false }
        guard let name, let deviceName, !name.isEmpty else { return false }
        return name == deviceName
    }
}
