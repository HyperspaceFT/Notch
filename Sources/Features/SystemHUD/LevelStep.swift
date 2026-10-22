/// Moves a level in 0…1 (volume, brightness) along a fixed grid, the way the
/// system HUD does: 16 steps normally, 64 with Option+Shift.
enum LevelStep {
    static let normal: Float = 1.0 / 16
    static let fine: Float = 1.0 / 64
    /// A value this close to a grid point counts as on it, so a level read back
    /// slightly off (e.g. 0.49999) does not skip or repeat a step.
    static let tolerance: Float = 1e-4

    /// The step for a key press with these modifiers; `nil` when the event should
    /// pass through (Option alone makes macOS open Sound or Displays settings).
    static func step(option: Bool, shift: Bool) -> Float? {
        guard option else { return normal }
        return shift ? fine : nil
    }

    /// Where the next step starts. A device that stores volume in coarse units
    /// reads back a little off the level Notch set, and stepping from that reading
    /// can land on the same stored value again, so the level never moves. While the
    /// reading is within half a step of the last level set, step from that level.
    static func origin(current: Float, lastSet: Float?, step: Float) -> Float {
        guard let lastSet, abs(current - lastSet) <= step / 2 else { return current }
        return lastSet
    }

    /// The next grid point strictly above `value`, at most 1.
    static func up(from value: Float, step: Float) -> Float {
        let index: Float
        if let onGrid = gridIndex(of: value, step: step) {
            index = onGrid + 1
        } else {
            index = (value / step).rounded(.up)
        }
        return clamp(index * step)
    }

    /// The next grid point strictly below `value`, at least 0.
    static func down(from value: Float, step: Float) -> Float {
        let index: Float
        if let onGrid = gridIndex(of: value, step: step) {
            index = onGrid - 1
        } else {
            index = (value / step).rounded(.down)
        }
        return clamp(index * step)
    }

    private static func gridIndex(of value: Float, step: Float) -> Float? {
        let nearest = (value / step).rounded()
        return abs(value - nearest * step) <= tolerance ? nearest : nil
    }

    private static func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}

/// A media key the HUD handles.
enum MediaKey: Int, Sendable {
    // NX_KEYTYPE_* in IOKit/hidsystem/ev_keymap.h.
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
}

/// One press or release of a media key, decoded from the `data1` field of an
/// `NX_SUBTYPE_AUX_CONTROL_BUTTONS` system-defined event.
struct MediaKeyEvent: Equatable, Sendable {
    var key: MediaKey
    var isDown: Bool
    var isRepeat: Bool

    /// `nil` for keys the HUD does not handle (play, next, keyboard backlight, …)
    /// and for an unknown key state.
    init?(data1: Int) {
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let flags = data1 & 0xFFFF
        let keyState = (flags & 0xFF00) >> 8
        guard let key = MediaKey(rawValue: keyCode) else { return nil }
        switch keyState {
        case 0x0A: isDown = true
        case 0x0B: isDown = false
        default: return nil
        }
        self.key = key
        isRepeat = flags & 0x1 != 0
    }

    init(key: MediaKey, isDown: Bool, isRepeat: Bool) {
        self.key = key
        self.isDown = isDown
        self.isRepeat = isRepeat
    }
}
