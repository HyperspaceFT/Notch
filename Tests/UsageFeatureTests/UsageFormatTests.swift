import Foundation
import NotchKit
import Testing
@testable import UsageFeature

/// Texts and thresholds from the reference widget (`windowLabel`, `formatReset`,
/// `levelClass`) in both languages.
@MainActor
struct UsageFormatTests {
    @Test func windowLabels() {
        let en = AppLanguage.english
        let zh = AppLanguage.simplifiedChinese
        #expect(UsageFormat.windowLabel(nil, language: en) == "Usage")
        #expect(UsageFormat.windowLabel(0, language: zh) == "用量")
        #expect(UsageFormat.windowLabel(604800, language: en) == "Weekly")
        #expect(UsageFormat.windowLabel(604800, language: zh) == "每周")
        #expect(UsageFormat.windowLabel(3 * 86400, language: en) == "3 days")
        #expect(UsageFormat.windowLabel(3 * 86400, language: zh) == "3 天")
        #expect(UsageFormat.windowLabel(18000, language: en) == "5 hours")
        #expect(UsageFormat.windowLabel(18000, language: zh) == "5 小时")
        #expect(UsageFormat.windowLabel(3600, language: en) == "1 hour")
        #expect(UsageFormat.windowLabel(7200, language: zh) == "2 小时")
        #expect(UsageFormat.windowLabel(5400, language: en) == "90 min")
        #expect(UsageFormat.windowLabel(5400, language: zh) == "90 分钟")
    }

    @Test func compactWindowLabels() {
        #expect(UsageFormat.compactWindowLabel(18000) == "5h")
        #expect(UsageFormat.compactWindowLabel(604800) == "7d")
        #expect(UsageFormat.compactWindowLabel(5400) == "90m")
        #expect(UsageFormat.compactWindowLabel(nil) == nil)
    }

    /// Thursday 2026-10-22 09:00 in Berlin, and a calendar fixed to that zone.
    private static let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    @Test func resetTexts() throws {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        let en = AppLanguage.english
        let zh = AppLanguage.simplifiedChinese
        func text(_ seconds: TimeInterval, _ language: AppLanguage) -> String {
            UsageFormat.resetText(now.addingTimeInterval(seconds), now: now, language: language, calendar: Self.berlin)
        }
        #expect(text(-30, en) == "Resets soon")
        #expect(text(0, zh) == "即将重置")
        // 29 s rounds to 0 minutes.
        #expect(text(29, en) == "Resets soon")
        #expect(text(23 * 60, en) == "Resets in 23 min")
        #expect(text(23 * 60, zh) == "23 分钟后重置")
        #expect(text(59 * 60, en) == "Resets in 59 min")
        #expect(text(138 * 60, en) == "Resets in 2h 18m")
        #expect(text(138 * 60, zh) == "2 小时 18 分后重置")
        #expect(text(3 * 3600, en) == "Resets in 3 h")
        #expect(text(3 * 3600, zh) == "3 小时后重置")
        #expect(text(1439 * 60, en) == "Resets in 23h 59m")

        // Past a day: weekday and 24-hour time in the calendar's zone.
        let thursday = try #require(Self.berlin.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 9)))
        let before = thursday.addingTimeInterval(-3 * 86400)
        #expect(UsageFormat.resetText(thursday, now: before, language: en, calendar: Self.berlin) == "Resets Thu 09:00")
        #expect(UsageFormat.resetText(thursday, now: before, language: zh, calendar: Self.berlin) == "周四 09:00 重置")
    }

    @Test func shortResetTexts() throws {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        func text(_ seconds: TimeInterval, _ language: AppLanguage = .english) -> String {
            UsageFormat.shortResetText(now.addingTimeInterval(seconds), now: now, language: language, calendar: Self.berlin)
        }
        #expect(text(23 * 60) == "23m")
        #expect(text(138 * 60) == "2h18m")
        #expect(text(3 * 3600) == "3h")
        let thursday = try #require(Self.berlin.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 9)))
        let before = thursday.addingTimeInterval(-2 * 86400)
        #expect(UsageFormat.shortResetText(thursday, now: before, language: .english, calendar: Self.berlin) == "Thu")
        #expect(UsageFormat.shortResetText(thursday, now: before, language: .simplifiedChinese, calendar: Self.berlin) == "周四")
    }

    @Test func levels() {
        #expect(UsageLevel(percent: 0) == .normal)
        #expect(UsageLevel(percent: 69.9) == .normal)
        #expect(UsageLevel(percent: 70) == .warning)
        #expect(UsageLevel(percent: 89.9) == .warning)
        #expect(UsageLevel(percent: 90) == .danger)
        #expect(UsageLevel(percent: 104) == .danger)
    }

    @Test func scopeFallbackNamesPerProvider() {
        let unnamed = UsageScope(label: nil, percent: 5, resetsAt: nil)
        #expect(UsageFormat.scopeLabel(unnamed, provider: .grok, language: .simplifiedChinese) == "其它")
        #expect(UsageFormat.scopeLabel(unnamed, provider: .claude, language: .simplifiedChinese) == "单项")
        #expect(UsageFormat.scopeLabel(unnamed, provider: .claude, language: .english) == "Other")
        #expect(UsageFormat.scopeLabel(UsageScope(label: "Fable", percent: 5, resetsAt: nil), provider: .claude) == "Fable")
    }

    @Test func settingsSummary() {
        let report = UsageReport(plan: "Max 5x", windows: [
            UsageWindow(duration: 18000, percent: 42.4, resetsAt: nil),
            UsageWindow(duration: 604800, percent: 17.6, resetsAt: nil),
        ])
        let status = UsageStatus(state: .ok, report: report, checkedAt: Date())
        #expect(UsageFormat.summary(status, language: .english) == "Max 5x · 5 hours 42% · Weekly 18%")
        #expect(UsageFormat.summary(status, language: .simplifiedChinese) == "Max 5x · 5 小时 42% · 每周 18%")
        #expect(UsageFormat.summary(UsageStatus(), language: .english) == "Loading…")
        #expect(UsageFormat.summary(UsageStatus(state: .signedOut), language: .simplifiedChinese) == "未登录")
    }
}

struct UsageRefreshPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func neverCheckedIsDue() {
        #expect(UsageRefreshPolicy.isDue(UsageStatus(), isInFlight: false, now: now))
    }

    @Test func goodReportStaysFreshForFiveMinutes() {
        let fresh = UsageStatus(state: .ok, checkedAt: now.addingTimeInterval(-299))
        let stale = UsageStatus(state: .ok, checkedAt: now.addingTimeInterval(-300))
        #expect(!UsageRefreshPolicy.isDue(fresh, isInFlight: false, now: now))
        #expect(UsageRefreshPolicy.isDue(stale, isInFlight: false, now: now))
    }

    @Test func otherStatesRetryAfterThirtySeconds() {
        for state: UsageStatus.State in [.signedOut, .needsVerification, .failed(.network)] {
            #expect(!UsageRefreshPolicy.isDue(UsageStatus(state: state, checkedAt: now.addingTimeInterval(-29)), isInFlight: false, now: now))
            #expect(UsageRefreshPolicy.isDue(UsageStatus(state: state, checkedAt: now.addingTimeInterval(-30)), isInFlight: false, now: now))
        }
    }

    @Test func nothingWhileInFlight() {
        #expect(!UsageRefreshPolicy.isDue(UsageStatus(), isInFlight: true, now: now))
        #expect(!UsageRefreshPolicy.isDue(UsageStatus(state: .ok, checkedAt: .distantPast), isInFlight: true, now: now))
    }
}
