import Foundation
import Observation

/// A language the interface is translated into.
public enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    /// The language's name in that language, as the language picker lists it.
    public var nativeName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    /// The first supported language in `identifiers` (most preferred first, as in
    /// `Locale.preferredLanguages`). Any Chinese variant maps to Simplified Chinese;
    /// with no supported language in the list, English.
    public static func preferred(from identifiers: [String]) -> AppLanguage {
        for identifier in identifiers {
            switch Locale.Language(identifier: identifier).languageCode {
            case .english?: return .english
            case .chinese?: return .simplifiedChinese
            default: continue
            }
        }
        return .english
    }
}

/// The interface language: the user's choice from the settings window, or the
/// system language when there is none. Views that read strings through
/// `localized(en:zh:)` redraw when it changes, so switching needs no relaunch.
@MainActor
@Observable
public final class Localization {
    public static let shared = Localization(defaults: .standard, systemLanguages: Locale.preferredLanguages)

    static let overrideKey = "NotchLanguage"

    /// The language picked in the settings window; `nil` follows the system.
    public var override: AppLanguage? {
        didSet { defaults.set(override?.rawValue, forKey: Self.overrideKey) }
    }

    /// The best match for the system language list, read once at launch
    /// (macOS relaunches apps for a change of system language anyway).
    public let systemLanguage: AppLanguage

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults, systemLanguages: [String]) {
        self.defaults = defaults
        systemLanguage = AppLanguage.preferred(from: systemLanguages)
        override = defaults.string(forKey: Self.overrideKey).flatMap(AppLanguage.init(rawValue:))
    }

    /// The language the interface is shown in.
    public var language: AppLanguage {
        override ?? systemLanguage
    }
}

/// The string for the current interface language. Read it while a view draws
/// (or right before AppKit shows it), not once up front, so it follows a switch.
@MainActor
public func localized(en english: String, zh chinese: String) -> String {
    switch Localization.shared.language {
    case .english: english
    case .simplifiedChinese: chinese
    }
}
