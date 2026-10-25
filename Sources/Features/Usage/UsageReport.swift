import Foundation
import NotchKit

/// One provider's usage as its website reports it: the plan and its limit windows.
public struct UsageReport: Equatable, Sendable {
    /// The plan's display name, such as "Max 5x"; empty when unknown.
    public var plan: String
    /// The limits in the order the provider lists them, the shortest first.
    public var windows: [UsageWindow]

    public init(plan: String, windows: [UsageWindow]) {
        self.plan = plan
        self.windows = windows
    }
}

/// One limit: how much of it is used and when it starts over.
public struct UsageWindow: Equatable, Sendable {
    /// The window's length in seconds, such as 18000 for five hours; `nil` when unknown.
    public var duration: TimeInterval?
    /// Percent used, at least 0; may exceed 100.
    public var percent: Double
    public var resetsAt: Date?
    /// Parts of the limit with their own allowance, such as one model's weekly
    /// limit or one product's share of the pool.
    public var scoped: [UsageScope]

    public init(duration: TimeInterval?, percent: Double, resetsAt: Date?, scoped: [UsageScope] = []) {
        self.duration = duration
        self.percent = percent
        self.resetsAt = resetsAt
        self.scoped = scoped
    }
}

/// A part of a limit, shown as "Fable 74%" after the window's own percent.
public struct UsageScope: Equatable, Sendable {
    /// The model or product; `nil` shows the provider's fallback name
    /// (`UsageFormat.scopeLabel`).
    public var label: String?
    public var percent: Double
    public var resetsAt: Date?

    public init(label: String?, percent: Double, resetsAt: Date?) {
        self.label = label
        self.percent = percent
        self.resetsAt = resetsAt
    }
}

/// Why a refresh failed, turned into text only when shown. Never holds a
/// token, a cookie, or a response body.
public enum UsageFailure: Equatable, Sendable {
    /// No connection, a timeout, or another transport error.
    case network
    /// The site answered with this HTTP status.
    case status(Int)
    /// The answer did not have the shape the reader expects (or was too large).
    case formatChanged
    /// A gRPC error with the server's own (percent-decoded) message.
    case server(String)
}

/// What a fetch ends in when it yields no report.
enum UsageFetchError: Error, Equatable, Sendable {
    /// Not signed in, or the sign-in expired.
    case signedOut
    /// The site answered with a page (likely a Cloudflare challenge or a login
    /// page) instead of data.
    case needsVerification
    case failed(UsageFailure)
    /// The refresh was cancelled; the previous status stays.
    case cancelled
}

/// What Notch knows about one provider.
public struct UsageStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// Never checked.
        case loading
        case ok
        case signedOut
        case needsVerification
        case failed(UsageFailure)
    }

    public var state: State
    /// The last report read, kept when a later refresh fails.
    public var report: UsageReport?
    /// When the last refresh ended; `nil` while never checked.
    public var checkedAt: Date?

    public init(state: State = .loading, report: UsageReport? = nil, checkedAt: Date? = nil) {
        self.state = state
        self.report = report
        self.checkedAt = checkedAt
    }
}

/// How close a limit is to running out.
public enum UsageLevel: Int, Comparable, Sendable {
    case normal
    /// From 70%.
    case warning
    /// From 90%.
    case danger

    public init(percent: Double) {
        self = percent >= 90 ? .danger : percent >= 70 ? .warning : .normal
    }

    public static func < (lhs: UsageLevel, rhs: UsageLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// When a provider's usage is read again.
enum UsageRefreshPolicy {
    /// How long a good report stays fresh.
    static let staleAfter: TimeInterval = 5 * 60
    /// How soon a provider that is signed out, needs verification, or failed
    /// is tried again (for one, right after signing in elsewhere).
    static let retryAfter: TimeInterval = 30

    static func isDue(_ status: UsageStatus, isInFlight: Bool, now: Date) -> Bool {
        guard !isInFlight else { return false }
        guard let checkedAt = status.checkedAt else { return true }
        let age = now.timeIntervalSince(checkedAt)
        return age >= (status.state == .ok ? staleAfter : retryAfter)
    }
}

/// The texts the usage views show, in a given language so tests cover both.
@MainActor
enum UsageFormat {
    /// "5 hours", "Weekly", "3 days", "90 min", or "Usage" without a length.
    static func windowLabel(_ duration: TimeInterval?, language: AppLanguage = Localization.shared.language) -> String {
        guard let seconds = duration, seconds != 0 else {
            return text(language, en: "Usage", zh: "用量")
        }
        if seconds.truncatingRemainder(dividingBy: 86400) == 0 {
            let days = Int(seconds / 86400)
            if days == 7 { return text(language, en: "Weekly", zh: "每周") }
            return text(language, en: days == 1 ? "1 day" : "\(days) days", zh: "\(days) 天")
        }
        if seconds.truncatingRemainder(dividingBy: 3600) == 0 {
            let hours = Int(seconds / 3600)
            return text(language, en: hours == 1 ? "1 hour" : "\(hours) hours", zh: "\(hours) 小时")
        }
        let minutes = Int((seconds / 60).rounded())
        return text(language, en: "\(minutes) min", zh: "\(minutes) 分钟")
    }

    /// "5h", "7d", "90m" for the narrow Home module; `nil` without a length.
    static func compactWindowLabel(_ duration: TimeInterval?) -> String? {
        guard let seconds = duration, seconds > 0 else { return nil }
        if seconds.truncatingRemainder(dividingBy: 86400) == 0 { return "\(Int(seconds / 86400))d" }
        if seconds.truncatingRemainder(dividingBy: 3600) == 0 { return "\(Int(seconds / 3600))h" }
        return "\(Int((seconds / 60).rounded()))m"
    }

    /// Minutes from `now` to `date`, rounded as the reference rounds them.
    private static func minutes(until date: Date, now: Date) -> Int {
        Int((date.timeIntervalSince(now) / 60).rounded(.toNearestOrAwayFromZero))
    }

    /// "Resets in 23 min", "Resets in 2h 18m", "Resets in 3 h", or past a day
    /// "Resets Thu 09:00".
    static func resetText(
        _ date: Date,
        now: Date,
        language: AppLanguage = Localization.shared.language,
        calendar: Calendar = .current
    ) -> String {
        let minutes = minutes(until: date, now: now)
        if minutes <= 0 { return text(language, en: "Resets soon", zh: "即将重置") }
        if minutes < 60 { return text(language, en: "Resets in \(minutes) min", zh: "\(minutes) 分钟后重置") }
        if minutes < 24 * 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            if rest == 0 { return text(language, en: "Resets in \(hours) h", zh: "\(hours) 小时后重置") }
            return text(language, en: "Resets in \(hours)h \(rest)m", zh: "\(hours) 小时 \(rest) 分后重置")
        }
        let day = weekday(date, language: language, calendar: calendar)
        let time = clockTime(date, calendar: calendar)
        return text(language, en: "Resets \(day) \(time)", zh: "\(day) \(time) 重置")
    }

    /// "23m", "2h18m", "3h", or past a day the weekday ("Thu", "周四").
    static func shortResetText(
        _ date: Date,
        now: Date,
        language: AppLanguage = Localization.shared.language,
        calendar: Calendar = .current
    ) -> String {
        let minutes = max(minutes(until: date, now: now), 0)
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 24 * 60 {
            let rest = minutes % 60
            return rest == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h\(rest)m"
        }
        return weekday(date, language: language, calendar: calendar)
    }

    /// The name shown for a part of a limit without its own name.
    static func scopeLabel(_ scope: UsageScope, provider: UsageProvider, language: AppLanguage = Localization.shared.language) -> String {
        if let label = scope.label { return label }
        switch provider {
        case .grok: return text(language, en: "Other", zh: "其它")
        case .claude, .codex: return text(language, en: "Other", zh: "单项")
        }
    }

    static func failureText(_ failure: UsageFailure, language: AppLanguage = Localization.shared.language) -> String {
        switch failure {
        case .network:
            text(language, en: "Network error", zh: "网络错误")
        case .status(let code):
            text(language, en: "The site answered \(code)", zh: "网站返回 \(code)")
        case .formatChanged:
            text(language, en: "The usage data's format has changed", zh: "用量数据的格式已变化")
        case .server(let message):
            text(language, en: "Server error: \(message)", zh: "服务器错误：\(message)")
        }
    }

    /// What a state without a good report says, as a short title; `nil` for
    /// loading and ok.
    static func stateTitle(_ state: UsageStatus.State, language: AppLanguage = Localization.shared.language) -> String? {
        switch state {
        case .loading, .ok: nil
        case .signedOut: text(language, en: "Not signed in", zh: "未登录")
        case .needsVerification: text(language, en: "Verification needed", zh: "需要验证")
        case .failed(let failure): failureText(failure, language: language)
        }
    }

    /// The settings pane's line for a provider: "Max 5x · 5 hours 42% · Weekly 18%",
    /// or what keeps it from showing.
    static func summary(_ status: UsageStatus, language: AppLanguage = Localization.shared.language) -> String {
        switch status.state {
        case .loading:
            return text(language, en: "Loading…", zh: "正在读取…")
        case .ok:
            guard let report = status.report else { return "" }
            var parts = report.plan.isEmpty ? [] : [report.plan]
            parts += report.windows.map { "\(windowLabel($0.duration, language: language)) \(Int($0.percent.rounded()))%" }
            return parts.joined(separator: " · ")
        case .signedOut:
            return text(language, en: "Not signed in", zh: "未登录")
        case .needsVerification:
            return verificationHint(language: language)
        case .failed(let failure):
            return failureText(failure, language: language)
        }
    }

    static func signInHint(language: AppLanguage = Localization.shared.language) -> String {
        text(language, en: "Sign in under Settings → Usage.", zh: "在「设置 → 用量」中登录。")
    }

    static func verificationHint(language: AppLanguage = Localization.shared.language) -> String {
        text(
            language,
            en: "Open the sign-in window under Settings → Usage.",
            zh: "在「设置 → 用量」中打开登录窗口完成验证。"
        )
    }

    private static func weekday(_ date: Date, language: AppLanguage, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .english ? "en_US_POSIX" : "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private static func clockTime(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func text(_ language: AppLanguage, en english: String, zh chinese: String) -> String {
        switch language {
        case .english: english
        case .simplifiedChinese: chinese
        }
    }
}

extension UsageStatus {
    /// The settings pane's line: "Max 5x · 5 hours 42% · Weekly 18%", or what
    /// keeps the usage from showing, in the interface language.
    @MainActor public var summary: String {
        UsageFormat.summary(self)
    }
}
