import Foundation
import Testing
@testable import UsageFeature

@MainActor
struct GoogleUsageTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// The shape `agy -p /usage --output-format json` returns: Gemini's two
    /// buckets, a separate Argon weekly bucket, and the Claude/GPT group that
    /// the Gemini card ignores.
    private func usage(argonRemaining: Double = 1) -> Any {
        [
            "status": "SUCCESS",
            "command": [
                "name": "usage",
                "data": [
                    "groups": [
                        [
                            "name": "Gemini Models",
                            "buckets": [
                                ["id": "gemini-weekly", "window": "weekly", "remaining_fraction": 0.847, "reset_time": "2026-11-27T18:08:52Z"],
                                ["id": "gemini-5h", "window": "5h", "remaining_fraction": 0.466, "reset_time": "2026-11-20T23:08:52Z"],
                            ],
                        ],
                        [
                            "name": "Claude and GPT models",
                            "buckets": [
                                ["id": "3p-weekly", "window": "weekly", "remaining_fraction": 1, "reset_time": "2026-11-27T21:13:39Z"],
                                ["id": "3p-5h", "window": "5h", "remaining_fraction": 1, "reset_time": "2026-11-21T02:13:39Z"],
                            ],
                        ],
                        [
                            "name": "Gemini 4 Argon",
                            "buckets": [
                                ["id": "gemini-argon-wtu-weekly", "window": "weekly", "remaining_fraction": argonRemaining, "reset_time": "2026-11-27T21:13:39Z"],
                            ],
                        ],
                    ],
                ],
            ],
        ]
    }

    @Test func geminiGivesAFiveHourAndWeeklyWindow() throws {
        let report = try GoogleUsage.parse(usage(), now: now)
        #expect(report.plan.isEmpty)
        #expect(report.windows.count == 2)

        let fiveHour = report.windows[0]
        #expect(fiveHour.duration == GoogleUsage.fiveHourDuration)
        #expect(abs(fiveHour.percent - 53.4) < 0.001)
        #expect(fiveHour.resetsAt == UsageJSON.date("2026-11-20T23:08:52Z"))

        let weekly = report.windows[1]
        #expect(weekly.duration == GoogleUsage.weeklyDuration)
        #expect(abs(weekly.percent - 15.3) < 0.001)
        // Argon fully remaining: not shown as a part.
        #expect(weekly.scoped.isEmpty)
    }

    @Test func aUsedArgonBucketBecomesAWeeklyPart() throws {
        let report = try GoogleUsage.parse(usage(argonRemaining: 0.4), now: now)
        let weekly = try #require(report.windows.last)
        #expect(weekly.scoped.count == 1)
        #expect(weekly.scoped.first?.label == "Argon")
        #expect(abs((weekly.scoped.first?.percent ?? 0) - 60) < 0.001)
    }

    @Test func aNonSuccessRunReadsAsSignedOut() {
        #expect(throws: UsageFetchError.signedOut) {
            try GoogleUsage.parse(["status": "ERROR", "command": [:]], now: now)
        }
    }

    @Test func missingGroupsIsAFormatChange() {
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try GoogleUsage.parse(["status": "SUCCESS"], now: now)
        }
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try GoogleUsage.parse("nope", now: now)
        }
    }

    @Test func noGeminiBucketIsAFormatChange() {
        let onlyThirdParty: Any = [
            "status": "SUCCESS",
            "command": ["data": ["groups": [
                ["buckets": [["id": "3p-weekly", "window": "weekly", "remaining_fraction": 1]]],
            ]]],
        ]
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try GoogleUsage.parse(onlyThirdParty, now: now)
        }
    }
}
