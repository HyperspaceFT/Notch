import Foundation
import SwiftUI

/// A subscription whose usage limits Notch reads from the provider's website,
/// with the sign-in the user made in Notch's own sign-in window.
public enum UsageProvider: String, CaseIterable, Sendable {
    /// claude.ai (Pro, Max, Team).
    case claude
    /// ChatGPT's Codex limits, read from chatgpt.com.
    case codex
    /// grok.com (SuperGrok and its tiers, or a free account).
    case grok

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .grok: "Grok"
        }
    }

    /// The website every request for this provider goes to, and nothing else.
    public var origin: URL {
        switch self {
        case .claude: URL(string: "https://claude.ai")!
        case .codex: URL(string: "https://chatgpt.com")!
        case .grok: URL(string: "https://grok.com")!
        }
    }

    /// Where the sign-in window starts.
    public var signInURL: URL {
        switch self {
        case .claude: URL(string: "https://claude.ai/login")!
        case .codex: URL(string: "https://chatgpt.com/auth/login")!
        case .grok: URL(string: "https://grok.com/")!
        }
    }

    /// The provider's own usage page, opened from the provider's name.
    public var usagePageURL: URL {
        switch self {
        case .claude: URL(string: "https://claude.ai/settings/usage")!
        case .codex: URL(string: "https://chatgpt.com/codex/settings/usage")!
        case .grok: URL(string: "https://grok.com/?_s=usage")!
        }
    }

    /// The registrable domains whose website data "Sign Out" removes: the site
    /// and the domains its sign-in passes through.
    public var signOutDomains: [String] {
        switch self {
        case .claude: ["claude.ai"]
        case .codex: ["chatgpt.com", "openai.com"]
        case .grok: ["grok.com", "x.ai"]
        }
    }

    /// How many limit windows the provider usually reports (Claude and Codex a
    /// session and a weekly one, Grok one weekly pool), for the Home module's width.
    var expectedWindowCount: Int {
        switch self {
        case .claude, .codex: 2
        case .grok: 1
        }
    }

    /// The provider's color, for its bars; Claude's and Codex's match their
    /// logos (`UsageProviderLogo`).
    public var accentColor: Color {
        switch self {
        case .claude: Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
        case .codex: Color(red: 0x7A / 255, green: 0x9D / 255, blue: 0xFF / 255)
        case .grok: Color(red: 0x9F / 255, green: 0xB3 / 255, blue: 0xC8 / 255)
        }
    }
}
