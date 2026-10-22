import CoreGraphics
import Darwin

/// Brightness of the built-in display. macOS has no public API for it, so this
/// calls the private DisplayServices framework, loaded at run time rather than
/// linked: if a macOS update removes it or a symbol, brightness keys simply pass
/// through to the system again.
@MainActor
struct DisplayBrightness {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeBrightness = @convention(c) (CGDirectDisplayID) -> Bool

    private struct Functions {
        let get: GetBrightness
        let set: SetBrightness
        let canChange: CanChangeBrightness
    }

    /// Loaded once; `nil` when the framework or one of its symbols is missing.
    private static let functions: Functions? = {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard
            let handle = dlopen(path, RTLD_LAZY),
            let get = dlsym(handle, "DisplayServicesGetBrightness"),
            let set = dlsym(handle, "DisplayServicesSetBrightness"),
            let canChange = dlsym(handle, "DisplayServicesCanChangeBrightness")
        else { return nil }
        return Functions(
            get: unsafeBitCast(get, to: GetBrightness.self),
            set: unsafeBitCast(set, to: SetBrightness.self),
            canChange: unsafeBitCast(canChange, to: CanChangeBrightness.self)
        )
    }()

    let display: CGDirectDisplayID
    /// The level in 0…1 when the display was looked up.
    let brightness: Float
    private let functions: Functions

    /// The active built-in display, if its brightness can be read and changed.
    static func builtIn() -> DisplayBrightness? {
        guard let functions else { return nil }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }
        guard
            let display = displays.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }),
            functions.canChange(display)
        else { return nil }
        var brightness: Float = 0
        guard functions.get(display, &brightness) == 0 else { return nil }
        return DisplayBrightness(display: display, brightness: brightness, functions: functions)
    }

    func setBrightness(_ brightness: Float) {
        _ = functions.set(display, brightness)
    }
}
