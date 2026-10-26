import AppKit
import CalendarFeature
import HomeFeature
import NotchKit
import NotchUI
import NotificationsFeature
import NowPlayingFeature
import Observation
import SwiftUI
import SystemHUDFeature
import UsageFeature
import WeatherFeature

/// Tells the settings controller that its window is closing.
@MainActor
private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: () -> Void = {}

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

/// The settings window: a sidebar of pages in groups (General; Island: Volume and
/// Brightness, Now Playing, Notifications; Home: Layout, Weather, Calendar,
/// Usage; and Debug while debug mode is on) beside the selected page
/// (`SettingsRootView`). Built on first use and kept for later openings. Also
/// owns the Usage page's sign-in windows.
@MainActor
final class SettingsWindowController {
    static let initialSize = NSSize(width: 700, height: 640)
    static let minimumSize = NSSize(width: 700, height: 420)

    private var window: NSWindow?
    private let launchAtLogin = LaunchAtLogin()
    private let usageSignIn = UsageSignInWindows()
    /// Whether debug mode was on at the last check, to notice it going off.
    private var wasDebugEnabled = false
    /// The page shown, kept for later openings.
    private let selection = SettingsSelection()

    /// What the Debug page lists; set before the window is first shown.
    var debugSources = DebugSources(islandItems: { [] }, features: [])
    /// Ends the island pins the Debug page makes; called when debug mode goes off
    /// and when the window closes, so a pin never outlives the page that undoes it.
    var onEndDebugPins: () -> Void = {}
    private let windowDelegate = SettingsWindowDelegate()

    func show() {
        // An accessory app is never active on its own; without this the window
        // would open behind the frontmost app. Since macOS 14 this only asks, and
        // the system may decline a request that no longer follows the click, so
        // it goes out first, not after the slow first build of the window.
        NSApp.activate()
        launchAtLogin.refresh()
        SystemHUDSettings.shared.refreshAccessibilityAccess()
        NotificationsSettings.shared.refreshAccessibilityAccess()
        NotificationsSettings.shared.refreshFullDiskAccess()
        LocalCalendars.shared.refreshAccess()
        let window = window ?? makeWindow()
        window.makeKeyAndOrderFront(nil)
        // In front even if the activation is declined or still pending; it takes
        // the keyboard once the app is active, or at the user's first click on it.
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsRootView(
            selection: selection,
            launchAtLogin: launchAtLogin,
            debug: .shared,
            debugSources: debugSources
        ) { [usageSignIn] provider in
            usageSignIn.show(provider)
        }
        let controller = NSHostingController(rootView: root)
        // The window keeps the size it is given; pages scroll inside it.
        controller.sizingOptions = []
        // The selected page's title becomes the window title.
        controller.sceneBridgingOptions = [.title, .toolbars]

        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(Self.initialSize)
        window.contentMinSize = Self.minimumSize
        window.isReleasedWhenClosed = false
        windowDelegate.onClose = { [weak self] in self?.onEndDebugPins() }
        window.delegate = windowDelegate
        window.center()
        self.window = window

        wasDebugEnabled = DebugSettings.shared.isEnabled
        followDebugMode()
        return window
    }

    /// Ends the Debug page's pins when debug mode goes off, again on every switch;
    /// the sidebar drops the page by itself.
    private func followDebugMode() {
        let isEnabled = withObservationTracking {
            DebugSettings.shared.isEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.followDebugMode()
            }
        }
        if wasDebugEnabled, !isEnabled {
            onEndDebugPins()
        }
        wasDebugEnabled = isEnabled
    }
}

/// A page of the settings window.
private enum SettingsPage: Hashable {
    case general
    case systemHUD, nowPlaying, notifications
    case homeLayout, weather, calendar, usage
    case debug

    /// Its name in the sidebar, under its group's heading.
    @MainActor var label: String {
        switch self {
        case .general: localized(en: "General", zh: "通用")
        case .systemHUD: localized(en: "Volume and Brightness", zh: "音量与亮度")
        case .nowPlaying: localized(en: "Now Playing", zh: "正在播放")
        case .notifications: localized(en: "Notifications", zh: "通知")
        case .homeLayout: localized(en: "Layout", zh: "布局")
        case .weather: localized(en: "Weather", zh: "天气")
        case .calendar: localized(en: "Calendar", zh: "日历")
        case .usage: localized(en: "Usage", zh: "用量")
        case .debug: localized(en: "Debug", zh: "调试")
        }
    }

    /// Its name as the window title, where no group heading is beside it.
    @MainActor var title: String {
        self == .homeLayout ? localized(en: "Home Layout", zh: "主页布局") : label
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .systemHUD: "speaker.wave.2"
        case .nowPlaying: "play.circle"
        case .notifications: "bell.badge"
        case .homeLayout: "square.grid.2x2"
        case .weather: "cloud.sun"
        case .calendar: "calendar"
        case .usage: "gauge.with.needle"
        case .debug: "ladybug"
        }
    }
}

/// The settings page shown, held by the controller rather than the view
/// (`@State` needs a macro plugin the Command Line Tools do not ship).
@MainActor
@Observable
private final class SettingsSelection {
    var page: SettingsPage? = .general
}

/// The sidebar and the selected page. Pages keep their own width and scroll
/// when taller than the window.
private struct SettingsRootView: View {
    @Bindable var selection: SettingsSelection
    let launchAtLogin: LaunchAtLogin
    @Bindable var debug: DebugSettings
    let debugSources: DebugSources
    let showUsageSignIn: @MainActor (UsageProvider) -> Void

    var body: some View {
        NavigationSplitView {
            List(selection: $selection.page) {
                row(.general)
                Section(localized(en: "Island", zh: "灵动岛")) {
                    row(.systemHUD)
                    row(.nowPlaying)
                    row(.notifications)
                }
                Section(localized(en: "Home", zh: "主页")) {
                    row(.homeLayout)
                    row(.weather)
                    row(.calendar)
                    row(.usage)
                }
                if debug.isEnabled {
                    Section {
                        row(.debug)
                    }
                }
            }
            .navigationSplitViewColumnWidth(190)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            let page = selection.page ?? .general
            ScrollView {
                content(of: page)
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle(page.title)
        }
        .onChange(of: debug.isEnabled) { _, isEnabled in
            if !isEnabled, selection.page == .debug {
                selection.page = .general
            }
        }
    }

    private func row(_ page: SettingsPage) -> some View {
        Label(page.label, systemImage: page.symbol)
            .tag(page)
    }

    @ViewBuilder
    private func content(of page: SettingsPage) -> some View {
        switch page {
        case .general:
            GeneralSettingsView(localization: .shared, launchAtLogin: launchAtLogin, appearance: .shared, debug: debug)
        case .systemHUD:
            SystemHUDSettingsView(systemHUD: .shared)
        case .nowPlaying:
            NowPlayingSettingsView(nowPlaying: .shared)
        case .notifications:
            NotificationsSettingsView(notifications: .shared)
        case .homeLayout:
            HomeSettingsView(settings: .shared)
        case .weather:
            WeatherSettingsView(settings: .shared, model: .shared)
        case .calendar:
            CalendarSettingsView(settings: .shared, local: .shared, feeds: .shared)
        case .usage:
            UsageSettingsView(settings: .shared, model: .shared, openSignIn: showUsageSignIn)
        case .debug:
            DebugSettingsView(sources: debugSources)
        }
    }
}

private struct GeneralSettingsView: View {
    @Bindable var localization: Localization
    @Bindable var launchAtLogin: LaunchAtLogin
    @Bindable var appearance: NotchAppearance
    @Bindable var debug: DebugSettings

    var body: some View {
        Form {
            Toggle(isOn: $launchAtLogin.isEnabled) {
                Text(localized(en: "Open at Login", zh: "登录时打开"))
                if let note = launchAtLoginNote {
                    Text(note)
                }
            }
            .toggleStyle(.switch)
            Toggle(isOn: $appearance.isLightAndColorEnabled) {
                Text(localized(en: "Light and Color", zh: "光影与色彩"))
                Text(localized(
                    en: "Gives cards depth and colors them by what they show. The open island's edge follows the local sun and moon phase, with sunrise and sunset from the weather.",
                    zh: "为卡片加入立体光影和随内容变化的颜色。展开时，岛的边缘会随当地的太阳位置和月相变化，日出日落时间来自天气。"
                ))
            }
            .toggleStyle(.switch)
            Picker(localized(en: "Language", zh: "语言"), selection: $localization.override) {
                Text(localized(en: "System", zh: "跟随系统"))
                    .tag(AppLanguage?.none)
                Divider()
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.nativeName)
                        .tag(AppLanguage?.some(language))
                }
            }
            Toggle(isOn: $debug.isEnabled) {
                Text(localized(en: "Debug Mode", zh: "调试模式"))
                Text(localized(
                    en: "Adds a Debug pane to Settings that shows each part of the island at once, with sample data where needed, for checking how it looks.",
                    zh: "在设置中加入「调试」面板，可立即显示岛的各个界面（必要时使用示例数据），用于检查界面。"
                ))
                Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(localized(en: "If you don't know what you're doing, leave this off.", zh: "如果你不知道自己在做什么，请不要打开。"))")
                    .foregroundStyle(.orange)
            }
            .toggleStyle(.switch)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        // Coming back from System Settings, where the login item may have changed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }

    /// Shown under the switch: why turning it on or off failed, or what is left to do.
    private var launchAtLoginNote: String? {
        if let error = launchAtLogin.errorMessage { return error }
        if launchAtLogin.status == .requiresApproval {
            return localized(
                en: "Allow Notch in System Settings → General → Login Items.",
                zh: "请在「系统设置 → 通用 → 登录项」中允许 Notch。"
            )
        }
        return nil
    }
}

/// Whether the island replaces the system volume and brightness HUD.
private struct SystemHUDSettingsView: View {
    @Bindable var systemHUD: SystemHUDSettings

    var body: some View {
        Form {
            Toggle(isOn: $systemHUD.isEnabled) {
                Text(localized(en: "Replace Volume and Brightness HUD", zh: "替换系统音量和亮度提示"))
                if needsAccessibilityAccess {
                    Text(localized(
                        en: "Allow Notch in System Settings → Privacy & Security → Accessibility.",
                        zh: "请在「系统设置 → 隐私与安全性 → 辅助功能」中允许 Notch。"
                    ))
                }
            }
            .toggleStyle(.switch)
            if needsAccessibilityAccess {
                Button(localized(en: "Open Accessibility Settings…", zh: "打开辅助功能设置…")) {
                    systemHUD.requestAccessibilityAccess()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        // Coming back from System Settings, where Accessibility access may have changed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            systemHUD.refreshAccessibilityAccess()
        }
    }

    /// The HUD is on but cannot intercept the keys until the user grants access.
    private var needsAccessibilityAccess: Bool {
        systemHUD.isEnabled && !systemHUD.hasAccessibilityAccess
    }
}

/// Where Now Playing reads the track from.
private struct NowPlayingSettingsView: View {
    @Bindable var nowPlaying: NowPlayingSettings

    var body: some View {
        Form {
            Toggle(isOn: $nowPlaying.usesMediaRemote) {
                Text(localized(en: "Read Now Playing from Any App", zh: "读取任意 App 的正在播放"))
                Text(localized(
                    en: "Shows what any app plays, browser tabs such as YouTube or Bilibili included, through the bundled third-party mediaremote-adapter. When off, only Music and Spotify are shown.",
                    zh: "通过随 App 附带的第三方组件 mediaremote-adapter，显示任意 App（包括浏览器里的 YouTube、哔哩哔哩）正在播放的内容。关闭时只显示「音乐」和 Spotify。"
                ))
            }
            .toggleStyle(.switch)
            // The risk, spelled out under the switch so it is read before turning it on.
            Label {
                Text(localized(
                    en: "This is a risky feature. Since macOS 15.4 only Apple-signed programs may read what is playing. To get around that, Notch has the system's own /usr/bin/perl load a prebuilt third-party library (mediaremote-adapter): code that is not Apple's then runs under an Apple identity and passes a privacy restriction macOS sets on purpose. Notch cannot check what that library does beyond its published source, and any macOS update may block it. Although most notch apps on the market use this method, that does not stop it from being a fairly dangerous way to do it.",
                    zh: "这是一项有一定风险的功能。macOS 15.4 起，只有 Apple 签名的程序才能读取正在播放的信息。为了绕过这一限制，Notch 会让系统自带的 /usr/bin/perl 加载一个第三方预编译库（mediaremote-adapter）：不属于 Apple 的代码因此以 Apple 程序的身份运行，绕开了 macOS 有意设置的隐私限制。除了它公开的源码，Notch 无法核实这个库实际做了什么，而且任何一次 macOS 更新都可能让它失效。虽说市面上绝大多数的 Notch 均采用了此方法，但是这并不妨碍该方法是一种较为危险的实现。"
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Whether the island shows other apps' notifications, hides the system's
/// banners, and also reads the notification database.
private struct NotificationsSettingsView: View {
    @Bindable var notifications: NotificationsSettings

    var body: some View {
        Form {
            Toggle(isOn: $notifications.isEnabled) {
                Text(localized(en: "Show Notifications in the Island", zh: "在灵动岛显示通知"))
                Text(localized(
                    en: "Banners from other apps show beside the notch, with their full text in a Notifications tab. Notch reads them through Accessibility and keeps them only in memory.",
                    zh: "其他 App 的通知横幅会显示在刘海两侧，完整内容在「通知」标签页中。Notch 通过辅助功能读取通知，且只保存在内存中。"
                ))
                if needsNotificationsAccess {
                    Text(localized(
                        en: "Allow Notch in System Settings → Privacy & Security → Accessibility.",
                        zh: "请在「系统设置 → 隐私与安全性 → 辅助功能」中允许 Notch。"
                    ))
                }
            }
            .toggleStyle(.switch)
            if needsNotificationsAccess {
                Button(localized(en: "Open Accessibility Settings…", zh: "打开辅助功能设置…")) {
                    notifications.requestAccessibilityAccess()
                }
            }
            Toggle(isOn: $notifications.hidesSystemBanners) {
                Text(localized(en: "Hide System Banners", zh: "隐藏系统通知横幅"))
                Text(localized(
                    en: "While the island shows a notification, the system's banner moves off screen. It can still flash for a moment first, and its buttons, such as Reply, are out of reach, so open the app from the island. Alerts that wait for an answer stay on screen.",
                    zh: "灵动岛显示通知时，系统横幅会移到屏幕之外。横幅仍可能先闪现片刻；横幅上的按钮（如「回复」）将无法点按，请从灵动岛打开 App。需要你回应的提醒会继续留在屏幕上。"
                ))
            }
            .toggleStyle(.switch)
            .disabled(!notifications.isEnabled)
            Toggle(isOn: $notifications.readsDatabase) {
                Text(localized(en: "Read the Notification Database Directly", zh: "直接读取通知数据库"))
                Text(localized(
                    en: "Needs Full Disk Access. When many notifications arrive within a short time, macOS shows only some of them as banners, so the island misses the rest; reading the system's notification database fills them in, a few seconds late. Notifications a Focus holds back stay hidden.",
                    zh: "需要「完全磁盘访问权限」。短时间内出现大量通知时，macOS 本身只会把其中一部分弹成横幅，灵动岛因此会漏掉其余的；直接读取系统的通知数据库可以有效补上这些通知，但会晚几秒出现。被专注模式拦下的通知仍不显示。"
                ))
                if needsFullDiskAccess {
                    Text(localized(
                        en: "Add Notch in System Settings → Privacy & Security → Full Disk Access.",
                        zh: "请在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中添加并允许 Notch。"
                    ))
                }
                if isDatabaseBroken {
                    Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(localized(en: "Because of a macOS update, this feature no longer works.", zh: "由于系统更新，该功能已经失效。"))")
                        .foregroundStyle(.orange)
                }
            }
            .toggleStyle(.switch)
            .disabled(!notifications.isEnabled)
            if needsFullDiskAccess {
                Button(localized(en: "Open Full Disk Access Settings…", zh: "打开完全磁盘访问权限设置…")) {
                    notifications.requestFullDiskAccess()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        // Coming back from System Settings, where Accessibility or Full Disk Access may have changed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            notifications.refreshAccessibilityAccess()
            notifications.refreshFullDiskAccess()
        }
    }

    /// Notifications are on but cannot be read until the user grants access.
    private var needsNotificationsAccess: Bool {
        notifications.isEnabled && !notifications.hasAccessibilityAccess
    }

    private var readsDatabase: Bool {
        notifications.isEnabled && notifications.readsDatabase
    }

    /// Reading the notification database is on but needs Full Disk Access.
    private var needsFullDiskAccess: Bool {
        readsDatabase && !isDatabaseBroken
            && (!notifications.hasFullDiskAccess || notifications.databaseStatus == .noAccess)
    }

    /// Reading the notification database is on, and the database is no longer
    /// what Notch reads.
    private var isDatabaseBroken: Bool {
        readsDatabase && notifications.databaseStatus == .broken
    }
}
