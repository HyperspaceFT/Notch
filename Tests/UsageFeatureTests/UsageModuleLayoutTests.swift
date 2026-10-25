import CoreGraphics
import Foundation
import NotchKit
import Testing
@testable import UsageFeature

/// 40 pt is a tight content width for `UsageModuleLayout.make`: the narrowest
/// Home module (68 pt less 24 pt of padding) leaves a little more.
struct UsageModuleLayoutTests {
    private let content: CGFloat = 40

    private func fits(_ layout: UsageModuleLayout, _ counts: [Int]) -> Bool {
        UsageModuleLayout.width(
            columnCounts: counts,
            columnWidth: layout.columnWidth,
            logoSize: layout.logoSize,
            groupGap: layout.groupGap
        ) <= content + 0.001
    }

    @Test func theModuleWidthFollowsTheProvidersShown() {
        let table: [([UsageProvider], CGFloat)] = [
            ([], 68),
            ([.claude], 68),
            ([.grok], 68),
            ([.claude, .codex], 86),
            ([.claude, .grok], 71),
            ([.codex, .grok], 71),
            ([.claude, .codex, .grok], 106),
        ]
        for (providers, width) in table {
            #expect(UsageModuleView.width(for: providers) == width, "\(providers)")
        }
    }

    @Test func realUsageAlwaysGetsFullColumnsAtItsWidth() {
        for providers: [UsageProvider] in [[.claude], [.claude, .codex], [.claude, .codex, .grok], [.codex, .grok]] {
            let content = UsageModuleView.width(for: providers) - 24
            let layout = UsageModuleLayout.make(contentWidth: content, columnCounts: providers.map(\.expectedWindowCount))
            #expect(layout.columnWidth == 12, "\(providers)")
            #expect(layout.showsNumbers && layout.showsIcons)
        }
    }

    @MainActor
    @Test func theSizingReadsTheUsersChoice() {
        let suite = "UsageModuleWidthTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = UsageSettings(defaults: defaults)
        settings.setProvider(.claude, shown: true)
        #expect(UsageModuleView.sizing(settings: settings) == .fixed(.points(68)))
        settings.setProvider(.codex, shown: true)
        #expect(UsageModuleView.sizing(settings: settings) == .fixed(.points(86)))
    }

    @Test func oneProviderGetsFullColumnsWithNumbersAndIcons() {
        let layout = UsageModuleLayout.make(contentWidth: content, columnCounts: [2])
        #expect(layout.columnWidth == 12)
        #expect(layout.logoSize == 12)
        #expect(layout.showsNumbers && layout.showsIcons)
    }

    @Test func twoProvidersFitWithTheStandardGap() {
        let layout = UsageModuleLayout.make(contentWidth: content, columnCounts: [2, 2])
        #expect((4...12).contains(layout.columnWidth))
        #expect(layout.groupGap == 6)
        #expect(fits(layout, [2, 2]))
        // Any wider and they would not.
        var wider = layout
        wider.columnWidth += 0.25
        #expect(!fits(wider, [2, 2]))
    }

    @Test func threeProvidersGetThinBarsOnly() {
        let counts = [2, 2, 1]
        let layout = UsageModuleLayout.make(contentWidth: content, columnCounts: counts)
        #expect(layout.columnWidth >= 4 && layout.columnWidth <= 12)
        #expect(layout.logoSize >= 9 && layout.logoSize <= 12)
        #expect(layout.groupGap >= 3 && layout.groupGap <= 6)
        #expect(fits(layout, counts))
        #expect(!layout.showsNumbers && !layout.showsIcons)
    }

    @Test func aStateProviderCountsAsOneColumn() {
        let state = UsageModuleLayout.make(contentWidth: content, columnCounts: [2, 1])
        let zero = UsageModuleLayout.make(contentWidth: content, columnCounts: [2, 0])
        #expect(state == zero)
        #expect(fits(state, [2, 1]))
        #expect(UsageModuleLayout.width(columnCounts: [1], columnWidth: 4, logoSize: 12, groupGap: 6) == CGFloat(12))
        #expect(UsageModuleLayout.width(columnCounts: [2, 1], columnWidth: 10, logoSize: 9, groupGap: 6) == CGFloat(23 + 6 + 10))
    }
}

@MainActor
struct UsageLimitNameTests {
    @Test func namesInBothLanguages() {
        let en = AppLanguage.english
        let zh = AppLanguage.simplifiedChinese
        #expect(UsageFormat.limitName(18000, language: en) == "Session Limit")
        #expect(UsageFormat.limitName(18000, language: zh) == "会话限额")
        #expect(UsageFormat.limitName(604800, language: en) == "Weekly Limit")
        #expect(UsageFormat.limitName(604800, language: zh) == "每周限额")
        #expect(UsageFormat.limitName(3 * 86400, language: en) == "3-Day Limit")
        #expect(UsageFormat.limitName(3 * 86400, language: zh) == "3 天限额")
        #expect(UsageFormat.limitName(nil, language: en) == "Limit")
        #expect(UsageFormat.limitName(0, language: zh) == "限额")
    }
}
