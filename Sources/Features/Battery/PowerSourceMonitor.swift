import Foundation
import IOKit.ps

/// A snapshot of the internal battery and power adapter.
struct PowerStatus: Equatable, Sendable {
    var percent: Int
    var isOnACPower: Bool
    var isCharging: Bool
    var isCharged: Bool
    /// Minutes until empty / full; `nil` while macOS is still estimating or not applicable.
    var minutesToEmpty: Int?
    var minutesToFull: Int?

    /// Reads the current state via IOKit. `nil` on Macs without an internal battery.
    static func read() -> PowerStatus? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]

        for source in sources {
            guard
                let unmanaged = IOPSGetPowerSourceDescription(info, source),
                let description = unmanaged.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let state = description[kIOPSPowerSourceStateKey] as? String

            return PowerStatus(
                percent: max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current,
                isOnACPower: state == kIOPSACPowerValue,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false,
                // IOKit reports -1 while it is still calculating.
                minutesToEmpty: (description[kIOPSTimeToEmptyKey] as? Int).flatMap { $0 > 0 ? $0 : nil },
                minutesToFull: (description[kIOPSTimeToFullChargeKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
            )
        }
        return nil
    }
}

/// Calls `onChange` on the main actor whenever any power source changes
/// (percentage, charging state, adapter plugged or unplugged).
@MainActor
final class PowerSourceMonitor {
    private let onChange: @MainActor () -> Void
    private var runLoopSource: CFRunLoopSource?

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    isolated deinit {
        stop()
    }

    func start() {
        guard runLoopSource == nil else { return }

        // The C callback cannot capture context, so `self` travels as an unretained
        // pointer. This is safe because `stop()` (called at the latest from deinit)
        // invalidates the source before `self` is freed.
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            // The source is added to the main run loop below, so the callback
            // always runs on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue().onChange()
            }
        }, context)?.takeRetainedValue() else { return }

        // Common modes so updates also arrive while a menu or drag is tracking.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    func stop() {
        guard let runLoopSource else { return }
        CFRunLoopSourceInvalidate(runLoopSource)
        self.runLoopSource = nil
    }
}
