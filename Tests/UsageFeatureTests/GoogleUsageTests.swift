import Foundation
import Testing
@testable import UsageFeature

@MainActor
struct GoogleUsageTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A `fetchAvailableModels` body: the Gemini models share one pool, a
    /// non-Google model sits on its own, and a local model has no reset.
    private func models() -> Any {
        [
            "models": [
                "gemini-3-flash": [
                    "apiProvider": "API_PROVIDER_GOOGLE_GEMINI",
                    "modelProvider": "MODEL_PROVIDER_GOOGLE",
                    "quotaInfo": ["remainingFraction": 0.614092, "resetTime": "2026-11-20T23:08:52Z"],
                ],
                "gemini-2.5-pro": [
                    "apiProvider": "API_PROVIDER_GOOGLE_GEMINI",
                    "modelProvider": "MODEL_PROVIDER_GOOGLE",
                    "quotaInfo": ["remainingFraction": 0.614092, "resetTime": "2026-11-20T23:08:52Z"],
                ],
                "claude-opus-5-5-low": [
                    "apiProvider": "API_PROVIDER_ANTHROPIC",
                    "modelProvider": "MODEL_PROVIDER_ANTHROPIC",
                    "quotaInfo": ["remainingFraction": 1, "resetTime": "2026-11-21T01:34:16Z"],
                ],
                "tab_flash_lite_preview": [
                    "apiProvider": "API_PROVIDER_GOOGLE_GEMINI",
                    "modelProvider": "MODEL_PROVIDER_GOOGLE",
                    "quotaInfo": ["remainingFraction": 1],
                ],
            ],
        ]
    }

    @Test func theQuotaIsTheDominantGeminiPool() throws {
        let window = try GoogleUsage.parseQuota(models(), now: now)
        #expect(window.duration == nil)
        #expect(abs(window.percent - 38.5908) < 0.001)
        #expect(window.resetsAt == UsageJSON.date("2026-11-20T23:08:52Z"))
        #expect(window.scoped.isEmpty)
    }

    @Test func aMissingFractionReadsAsNoneLeft() throws {
        let json: Any = [
            "models": [
                "gemini-3-pro": [
                    "modelProvider": "MODEL_PROVIDER_GOOGLE",
                    "quotaInfo": ["resetTime": "2026-11-20T23:08:52Z"],
                ],
            ],
        ]
        let window = try GoogleUsage.parseQuota(json, now: now)
        #expect(window.percent == 100)
    }

    @Test func noGeminiPoolIsAFormatChange() {
        let json: Any = ["models": ["tab": ["modelProvider": "MODEL_PROVIDER_GOOGLE", "quotaInfo": ["remainingFraction": 1]]]]
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try GoogleUsage.parseQuota(json, now: now)
        }
        #expect(throws: UsageFetchError.failed(.formatChanged)) {
            try GoogleUsage.parseQuota(["nope": 1], now: now)
        }
    }

    @Test func theKeychainBlobParses() {
        let json = #"{"token":{"access_token":"abc","token_type":"Bearer","refresh_token":"ref","expiry":"2026-11-20T15:20:31.809397-05:00"}}"#
        let expiry = UsageJSON.date("2026-11-20T15:20:31.809397-05:00")

        let plain = GoogleAuth.parse(Data(json.utf8))
        #expect(plain == GoogleAuth.StoredToken(accessToken: "abc", refreshToken: "ref", expiry: expiry))

        let wrapped = "go-keyring-base64:" + Data(json.utf8).base64EncodedString()
        #expect(GoogleAuth.parse(Data(wrapped.utf8)) == plain)
    }

    @Test func aBadKeychainBlobIsNil() {
        #expect(GoogleAuth.parse(Data("not json".utf8)) == nil)
        #expect(GoogleAuth.parse(Data("go-keyring-base64:!!!".utf8)) == nil)
    }

    /// The binary scan pulls each client id and `GOCSPX-` secret out of
    /// surrounding bytes, in order, without duplicates, and ignores look-alikes.
    @Test func theCredentialScanFindsClientsAndSecrets() {
        let secretA = "GOCSPX-" + String(repeating: "a", count: 28)
        let secretB = "GOCSPX-" + String(repeating: "b", count: 28)
        let idA = "123456789012-examplefixtureoneexampleoneab.apps.googleusercontent.com"
        let idB = "210987654321-examplefixturetwoexampletwocd.apps.googleusercontent.com"
        let blob = [
            "\u{0}junk\u{0}", idA, "\"", secretA, "\u{0}",
            "noise\u{0}", idB, " ", secretA, // a repeat, dropped
            "\u{0}", secretB, "\u{0}",
            "GOCSPX-short", // too short, ignored
            "x.apps.googleusercontent.com", // no leading digit, ignored
        ].joined()

        let found = GoogleCredentials.extract(Array(blob.utf8))
        #expect(found.secrets == [secretA, secretB])
        #expect(found.clientIDs == [idA, idB])
        #expect(!found.isEmpty)
    }

    @Test func anEmptyScanIsEmpty() {
        #expect(GoogleCredentials.extract(Array("nothing to see here".utf8)).isEmpty)
    }
}
