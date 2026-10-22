import AppKit
import CoreGraphics

/// Intercepts the volume, mute, and brightness keys with a session event tap.
/// Needs Accessibility access; `start()` fails without it.
///
/// `onKeyDown` gets every key down with the step for its modifiers and returns
/// whether it handled the key. A handled key's events are swallowed, so macOS
/// neither changes the level a second time nor shows its own HUD; an unhandled
/// one passes through and the system takes care of it. Repeats of a held key go
/// wherever its press went.
@MainActor
final class MediaKeyTap {
    /// `NX_SYSDEFINED`, the event type media keys arrive as.
    private static let systemDefinedType: UInt32 = 14
    /// `NX_SUBTYPE_AUX_CONTROL_BUTTONS`.
    private static let auxControlButtonsSubtype: Int16 = 8

    private let onKeyDown: @MainActor (MediaKeyEvent, Float) -> Bool
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Keys whose down event was swallowed. Their up event is swallowed too, so
    /// the system never sees a release without its press.
    private var swallowedKeys: Set<MediaKey> = []

    init(onKeyDown: @escaping @MainActor (MediaKeyEvent, Float) -> Bool) {
        self.onKeyDown = onKeyDown
    }

    isolated deinit {
        stop()
    }

    var isRunning: Bool { machPort != nil }

    /// Creates and enables the tap; `false` when macOS refuses it (no Accessibility access).
    @discardableResult
    func start() -> Bool {
        guard machPort == nil else { return true }

        // The C callback cannot capture context, so `self` travels as an unretained
        // pointer. This is safe because `stop()` (called at the latest from deinit)
        // invalidates the tap before `self` is freed.
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << CGEventMask(Self.systemDefinedType),
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                // The tap's source is added to the main run loop below, so the
                // callback always runs on the main thread.
                let swallow = MainActor.assumeIsolated {
                    Unmanaged<MediaKeyTap>.fromOpaque(context).takeUnretainedValue()
                        .shouldSwallow(type: type, event: event)
                }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: context
        ) else { return false }

        guard let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            CFMachPortInvalidate(port)
            return false
        }
        // Common modes so keys are also handled while a menu or drag is tracking.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        machPort = port
        runLoopSource = source
        return true
    }

    func stop() {
        guard let machPort else { return }
        CGEvent.tapEnable(tap: machPort, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(machPort)
        self.machPort = nil
        runLoopSource = nil
        swallowedKeys = []
    }

    private func shouldSwallow(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns a tap off when a callback is slow or on secure input; turn it back on.
            if let machPort {
                CGEvent.tapEnable(tap: machPort, enable: true)
            }
            return false
        default:
            break
        }

        guard
            type.rawValue == Self.systemDefinedType,
            let nsEvent = NSEvent(cgEvent: event),
            nsEvent.subtype.rawValue == Self.auxControlButtonsSubtype,
            let keyEvent = MediaKeyEvent(data1: nsEvent.data1)
        else { return false }

        guard keyEvent.isDown else {
            return swallowedKeys.remove(keyEvent.key) != nil
        }
        if keyEvent.isRepeat {
            // A held key stays with whoever took its press, so the system never
            // sees part of a hold: pressing Option or switching the output device
            // mid-hold neither hands repeats to the system nor takes them from it.
            guard swallowedKeys.contains(keyEvent.key) else { return false }
            if let step = LevelStep.step(
                option: event.flags.contains(.maskAlternate),
                shift: event.flags.contains(.maskShift)
            ) {
                _ = onKeyDown(keyEvent, step)
            }
            return true
        }
        guard let step = LevelStep.step(
            option: event.flags.contains(.maskAlternate),
            shift: event.flags.contains(.maskShift)
        ) else {
            swallowedKeys.remove(keyEvent.key)
            return false
        }
        if onKeyDown(keyEvent, step) {
            swallowedKeys.insert(keyEvent.key)
            return true
        }
        swallowedKeys.remove(keyEvent.key)
        return false
    }
}
