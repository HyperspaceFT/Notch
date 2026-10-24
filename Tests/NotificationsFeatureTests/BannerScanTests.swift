import Foundation
import Testing
@testable import NotificationsFeature

/// A hand-built element of NotificationCenter's tree.
final class FakeNode: BannerNode {
    var role: String?
    var subrole: String?
    var identifier: String?
    var stackingIdentifier: String?
    var value: String?
    var attributedDescription: String?
    var children: [FakeNode]

    var nodeKey: Int { ObjectIdentifier(self).hashValue }

    init(
        role: String? = nil,
        subrole: String? = nil,
        identifier: String? = nil,
        stackingIdentifier: String? = nil,
        value: String? = nil,
        description: String? = nil,
        children: [FakeNode] = []
    ) {
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.stackingIdentifier = stackingIdentifier
        self.value = value
        attributedDescription = description
        self.children = children
    }

    static func text(_ identifier: String, _ value: String) -> FakeNode {
        FakeNode(role: "AXStaticText", identifier: identifier, value: value)
    }

    static func window(_ children: FakeNode...) -> FakeNode {
        FakeNode(role: "AXWindow", children: children)
    }
}

private func banners(in window: FakeNode) -> [BannerCapture]? {
    guard case .banners(let banners) = BannerScan.scan(window: window) else { return nil }
    return banners
}

struct BannerScanTests {
    @Test func bannerWithTitleSubtitleAndBody() throws {
        let banner = FakeNode(
            subrole: "AXNotificationCenterBanner",
            identifier: "banner-1",
            description: "Messages, Anna, See you at 8",
            children: [
                FakeNode(children: [.text("title", " Anna "), .text("subtitle", "Dinner")]),
                .text("body", "See you at 8\n"),
            ]
        )
        let window = FakeNode.window(banner)
        let found = try #require(banners(in: window))
        #expect(found.count == 1)
        let capture = try #require(found.first)
        #expect(capture.token == "banner-1")
        #expect(capture.windowKey == window.nodeKey)
        #expect(capture.appName == "Messages")
        // Trimmed of surrounding whitespace.
        #expect(capture.title == "Anna")
        #expect(capture.subtitle == "Dinner")
        #expect(capture.body == "See you at 8")
        #expect(capture.hasContent)
    }

    @Test func headerStandsInForAMissingTitle() throws {
        let headerOnly = FakeNode(
            subrole: "AXNotificationCenterNotification",
            identifier: "a",
            children: [.text("header", "Calendar"), .text("body", "Standup")]
        )
        let both = FakeNode(
            subrole: "AXNotificationCenterNotification",
            identifier: "b",
            children: [.text("header", "Header"), .text("title", "Title")]
        )
        let found = try #require(banners(in: .window(headerOnly, both)))
        #expect(found.map(\.title) == ["Calendar", "Title"])
        #expect(found.first?.body == "Standup")
    }

    @Test func emptyAndBlankTextsAreNil() throws {
        let banner = FakeNode(
            subrole: "AXNotificationCenterBanner",
            identifier: "a",
            children: [.text("title", "  "), .text("body", "")]
        )
        let capture = try #require(banners(in: .window(banner))?.first)
        #expect(capture.title == nil)
        #expect(capture.body == nil)
        #expect(capture.appName == nil)
        #expect(!capture.hasContent)
    }

    @Test func nestedBannerIsPartOfItsOuterBanner() throws {
        let inner = FakeNode(
            subrole: "AXNotificationCenterBanner",
            identifier: "inner",
            children: [.text("title", "Inner")]
        )
        let outer = FakeNode(subrole: "AXNotificationCenterAlertStack", identifier: "outer", children: [inner])
        let found = try #require(banners(in: .window(outer)))
        #expect(found.map(\.token) == ["outer"])
        #expect(found.first?.title == "Inner")
    }

    @Test func everyBannerSubroleCounts() throws {
        let subroles = [
            "AXNotificationCenterBanner",
            "AXNotificationCenterAlert",
            "AXNotificationCenterNotification",
            "AXNotificationCenterBannerWindow",
            "AXNotificationCenterAlertStack",
        ]
        let nodes = subroles.enumerated().map { index, subrole in
            FakeNode(subrole: subrole, identifier: "b\(index)")
        }
        let found = try #require(banners(in: FakeNode(role: "AXWindow", children: nodes)))
        #expect(found.map(\.subrole) == subroles)
        #expect(banners(in: .window(FakeNode(subrole: "AXNotificationCenterSomethingElse"))) == [])
    }

    @Test func sharedChildIsVisitedOnce() throws {
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", identifier: "a")
        // "AXChildren" and "AXOrderedChildren" list the same element.
        let window = FakeNode.window(banner, banner)
        #expect(try #require(banners(in: window)).count == 1)
    }

    @Test func notificationCenterPanelIgnoresTheWindow() {
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", identifier: "a")
        let panel = FakeNode(subrole: "AXNotificationCenterPanel")
        #expect(BannerScan.scan(window: FakeNode.window(banner, panel)) == .panel)
        #expect(BannerScan.scan(window: FakeNode(subrole: "AXNotificationCenterPanel", children: [banner])) == .panel)
    }

    @Test func widgetEditorButtonIgnoresTheWindow() {
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", identifier: "a")
        let editor = FakeNode(role: "AXButton", identifier: "widget-editor-button")
        #expect(BannerScan.scan(window: FakeNode.window(banner, editor)) == .panel)
    }

    @Test func notificationStackInTheListIgnoresTheWindow() {
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", identifier: "a")
        let stack = FakeNode(role: "AXButton", stackingIdentifier: "stack-com.apple.MobileSMS")
        let list = FakeNode(identifier: "AXNotificationListItems", children: [FakeNode(children: [stack])])
        #expect(BannerScan.scan(window: FakeNode.window(banner, list)) == .panel)
    }

    @Test func stackButtonInsideABannerIsNoPanel() throws {
        let stack = FakeNode(role: "AXButton", stackingIdentifier: "stack-com.apple.MobileSMS")
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", identifier: "a", children: [stack])
        let list = FakeNode(identifier: "AXNotificationListItems", children: [banner])
        #expect(try #require(banners(in: .window(list))).map(\.token) == ["a"])
    }

    @Test func stackButtonOutsideTheListIsNoPanel() throws {
        let stack = FakeNode(role: "AXButton", stackingIdentifier: "stack-com.apple.MobileSMS")
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", identifier: "a")
        #expect(try #require(banners(in: .window(stack, banner))).count == 1)
        // Neither a non-button nor another stacking identifier marks the panel.
        let list = FakeNode(identifier: "AXNotificationListItems", children: [
            FakeNode(role: "AXGroup", stackingIdentifier: "stack-x"),
            FakeNode(role: "AXButton", stackingIdentifier: "group-x"),
            banner,
        ])
        #expect(try #require(banners(in: .window(list))).count == 1)
    }

    @Test func desktopWidgetIgnoresTheWindow() {
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", identifier: "a")
        let widget = FakeNode(identifier: "widget-local:com.apple.weather")
        #expect(BannerScan.scan(window: FakeNode.window(banner, FakeNode(children: [widget]))) == .desktopWidget)
    }

    @Test func panelOrWidgetElementsAreRecognizedOnTheirOwn() {
        #expect(BannerScan.isPanelOrWidget(FakeNode(subrole: "AXNotificationCenterPanel")))
        #expect(BannerScan.isPanelOrWidget(FakeNode(identifier: "widget-editor-button")))
        #expect(BannerScan.isPanelOrWidget(FakeNode(identifier: "widget-local:x")))
        #expect(!BannerScan.isPanelOrWidget(FakeNode(subrole: "AXNotificationCenterBanner", identifier: "a")))
    }

    @Test func windowPastTheLimitIsSkipped() {
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", identifier: "a")
        let filler = (0..<BannerScan.windowNodeLimit).map { _ in FakeNode() }
        #expect(BannerScan.scan(window: FakeNode(children: [banner] + filler)) == .tooLarge)
        let fitting = (0..<(BannerScan.windowNodeLimit - 2)).map { _ in FakeNode() }
        #expect(banners(in: FakeNode(children: [banner] + fitting))?.count == 1)
    }

    @Test func tokenPrefersTheIdentifier() {
        let node = FakeNode(identifier: "id", stackingIdentifier: "stack")
        #expect(BannerScan.token(for: node) == "id")
    }

    @Test func tokenSkipsEmptyAndSharedIdentifiers() {
        #expect(BannerScan.token(for: FakeNode(identifier: "", stackingIdentifier: "stack")) == "stack")
        #expect(BannerScan.token(for: FakeNode(identifier: "AXNotificationListItems", stackingIdentifier: "stack")) == "stack")
        #expect(BannerScan.token(for: FakeNode(identifier: "widgets-overlay-view", stackingIdentifier: "stack")) == "stack")
        #expect(BannerScan.token(for: FakeNode(stackingIdentifier: "stack")) == "stack")
    }

    @Test func tokenFallsBackToTheElementHash() {
        let node = FakeNode(identifier: "widgets-overlay-view", stackingIdentifier: "")
        #expect(BannerScan.token(for: node) == "ax-\(node.nodeKey)")
        let bare = FakeNode()
        #expect(BannerScan.token(for: bare) == "ax-\(bare.nodeKey)")
    }

    @Test func appNameIsTheDescriptionUpToTheFirstComma() {
        #expect(BannerScan.appName(fromDescription: "Messages, Anna, Hi, there") == "Messages")
        #expect(BannerScan.appName(fromDescription: "  Mail  ") == "Mail")
        #expect(BannerScan.appName(fromDescription: "Calendar") == "Calendar")
        #expect(BannerScan.appName(fromDescription: ", title") == nil)
        #expect(BannerScan.appName(fromDescription: "") == nil)
        #expect(BannerScan.appName(fromDescription: nil) == nil)
    }

    @Test func appNameLosesBidiControls() {
        let marks = ["\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
                     "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}"]
        for mark in marks {
            #expect(BannerScan.appName(fromDescription: "\(mark)Slack\(mark), hello") == "Slack")
        }
        #expect(BannerScan.appName(fromDescription: "\u{2068}微信\u{2069}, 张三, 你好") == "微信")
    }

    @Test func appNameFromTheBannerDescription() throws {
        let banner = FakeNode(
            subrole: "AXNotificationCenterBanner",
            identifier: "a",
            description: "\u{200E}Google Chrome\u{200E}, Download complete"
        )
        #expect(try #require(banners(in: .window(banner))).first?.appName == "Google Chrome")
    }

    @Test func alertsAreNotParkable() {
        func capture(_ subrole: String) -> BannerCapture {
            BannerCapture(token: "t", windowKey: 1, elementKey: 2, subrole: subrole)
        }
        #expect(!capture("AXNotificationCenterAlert").isParkable)
        #expect(!capture("AXNotificationCenterAlertStack").isParkable)
        #expect(capture("AXNotificationCenterBanner").isParkable)
        #expect(capture("AXNotificationCenterNotification").isParkable)
        #expect(capture("AXNotificationCenterBannerWindow").isParkable)
    }

    /// A banner capture with the given token, element, and text.
    func capture(_ token: String?, element: Int, title: String = "Test", body: String? = "Hello") -> BannerCapture {
        BannerCapture(
            token: token ?? BannerScan.fallbackToken(elementKey: element),
            windowKey: 1,
            elementKey: element,
            subrole: "AXNotificationCenterBanner",
            appName: "Script Editor",
            title: title,
            body: body
        )
    }

    @Test func ownTokensAreToldFromTheElementHashFallback() {
        #expect(capture("banner-1", element: 7).hasOwnToken)
        #expect(!capture(nil, element: 7).hasOwnToken)
        let bare = FakeNode()
        #expect(BannerScan.token(for: bare) == BannerScan.fallbackToken(elementKey: bare.nodeKey))
    }

    @Test func sameElementReadAgainIsNotNew() {
        var seen = SeenBanners()
        let banner = capture("t", element: 1)
        #expect(seen.update([banner]) == [banner])
        #expect(seen.update([banner]) == [])
    }

    @Test func identicalContentInANewElementWithAnotherTokenIsNew() {
        var seen = SeenBanners()
        let first = capture("a", element: 1)
        let second = capture("b", element: 2)
        #expect(seen.update([first]) == [first])
        #expect(seen.update([first, second]) == [second])
    }

    @Test func ownTokenRebuildReplacingAVanishedTwinIsNotNew() {
        var seen = SeenBanners()
        let original = capture("stack-script", element: 1)
        let rebuilt = capture("stack-script", element: 2)
        #expect(seen.update([original]) == [original])
        #expect(seen.update([rebuilt]) == [])
        // Remembered as the banner now on screen.
        #expect(seen.update([rebuilt]) == [])
    }

    @Test func identicalBannerBesideItsLiveTwinIsNew() {
        var seen = SeenBanners()
        let first = capture("stack-script", element: 1)
        let second = capture("stack-script", element: 2)
        #expect(seen.update([first]) == [first])
        #expect(seen.update([first, second]) == [second])
    }

    @Test func elementHashTokenReplacingAVanishedTwinIsNew() {
        var seen = SeenBanners()
        let first = capture(nil, element: 1)
        let second = capture(nil, element: 2)
        #expect(seen.update([first]) == [first])
        #expect(seen.update([second]) == [second])
    }

    @Test func inPlaceTextChangeIsNew() {
        var seen = SeenBanners()
        let before = capture("t", element: 1, body: "Hi")
        let after = capture("t", element: 1, body: "Are you there?")
        #expect(seen.update([before]) == [before])
        #expect(seen.update([after]) == [after])
    }

    @Test func bannerThatLeftAndComesBackIdenticalLaterIsNew() {
        var seen = SeenBanners()
        let first = capture("stack-script", element: 1)
        let again = capture("stack-script", element: 2)
        #expect(seen.update([first]) == [first])
        #expect(seen.update([]) == [])
        #expect(seen.update([again]) == [again])
    }

    @Test func rebuildMatchesOneToOne() {
        var seen = SeenBanners()
        let one = capture("stack-script", element: 1)
        let two = capture("stack-script", element: 2)
        #expect(seen.update([one]) == [one])
        // One vanished twin covers one rebuild; the other is a second banner.
        let rebuiltA = capture("stack-script", element: 3)
        #expect(seen.update([rebuiltA, two]) == [two])
    }
}
