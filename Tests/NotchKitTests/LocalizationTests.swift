import Foundation
import Testing
@testable import NotchKit

struct AppLanguageTests {
    @Test func picksTheFirstSupportedLanguage() {
        #expect(AppLanguage.preferred(from: ["zh-Hans-CN", "en-US"]) == .simplifiedChinese)
        #expect(AppLanguage.preferred(from: ["en-GB", "zh-Hans"]) == .english)
        #expect(AppLanguage.preferred(from: ["ja-JP", "zh-Hans-CN", "en"]) == .simplifiedChinese)
    }

    @Test func mapsEveryChineseVariantToSimplifiedChinese() {
        #expect(AppLanguage.preferred(from: ["zh-Hant-TW"]) == .simplifiedChinese)
        #expect(AppLanguage.preferred(from: ["zh-HK"]) == .simplifiedChinese)
    }

    @Test func fallsBackToEnglish() {
        #expect(AppLanguage.preferred(from: ["ja-JP", "fr-FR"]) == .english)
        #expect(AppLanguage.preferred(from: []) == .english)
    }
}

@MainActor
struct LocalizationTests {
    private let suiteName = "LocalizationTests.\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    @Test func followsTheSystemWithoutAnOverride() {
        let localization = Localization(defaults: defaults, systemLanguages: ["zh-Hans-CN"])
        #expect(localization.override == nil)
        #expect(localization.language == .simplifiedChinese)
    }

    @Test func overrideWinsAndPersists() {
        let localization = Localization(defaults: defaults, systemLanguages: ["zh-Hans-CN"])
        localization.override = .english
        #expect(localization.language == .english)

        let relaunched = Localization(defaults: defaults, systemLanguages: ["zh-Hans-CN"])
        #expect(relaunched.override == .english)
        #expect(relaunched.language == .english)

        relaunched.override = nil
        #expect(Localization(defaults: defaults, systemLanguages: ["zh-Hans-CN"]).override == nil)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func ignoresAnUnknownStoredLanguage() {
        defaults.set("xx", forKey: Localization.overrideKey)
        let localization = Localization(defaults: defaults, systemLanguages: ["en-US"])
        #expect(localization.override == nil)
        #expect(localization.language == .english)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
