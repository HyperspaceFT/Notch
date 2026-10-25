import NotchKit
import SwiftUI
import UsageFeature

/// The Usage pane: per provider a switch for showing it in the Usage tab and
/// Home module, how its last read went, and its sign-in.
struct UsageSettingsView: View {
    let settings: UsageSettings
    let model: UsageModel
    /// Opens (or brings forward) the provider's sign-in window.
    let openSignIn: @MainActor (UsageProvider) -> Void

    var body: some View {
        Form {
            ForEach(UsageProvider.allCases, id: \.self) { provider in
                section(provider, isLast: provider == UsageProvider.allCases.last)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            model.refreshIfNeeded()
        }
    }

    @ViewBuilder
    private func section(_ provider: UsageProvider, isLast: Bool) -> some View {
        let content = Group {
            Toggle(isOn: shownBinding(provider)) {
                Label {
                    Text(localized(en: "Show \(provider.displayName)", zh: "显示 \(provider.displayName)"))
                    Text(statusText(provider))
                } icon: {
                    Image(systemName: provider.glyph)
                        .foregroundStyle(provider.accentColor)
                }
            }
            .toggleStyle(.switch)
            HStack {
                Spacer()
                Button(localized(en: "Sign Out", zh: "退出登录")) {
                    model.signOut(provider)
                }
                .disabled(model.status(of: provider).state == .signedOut)
                Button(localized(en: "Sign In…", zh: "登录…")) {
                    openSignIn(provider)
                }
            }
        }
        if isLast {
            Section {
                content
            } footer: {
                Text(localized(
                    en: "Notch reads the internal endpoints the claude.ai, chatgpt.com, and grok.com web pages use for their usage pages. You sign in once in Notch's own sign-in window, and that sign-in stays in Notch's web data on this Mac; Notch does not read your browser's sign-ins. The endpoints are undocumented and may stop working at any time. Google sign-in is not available in the sign-in window (Google blocks embedded browsers), and other third-party sign-ins may not work there either, since pop-ups open in the same view; use an email code or a password.",
                    zh: "Notch 读取 claude.ai、chatgpt.com 和 grok.com 网页版的用量页面所用的内部接口。你只需在 Notch 自己的登录窗口中登录一次，登录状态保存在这台 Mac 上 Notch 的网页数据里；Notch 不会读取浏览器中的登录。这些接口没有公开文档，随时可能失效。登录窗口中无法使用 Google 登录（Google 不允许内嵌浏览器），其他第三方登录也可能无法完成（弹出窗口会在同一视图中打开），请使用邮箱验证码或密码。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        } else {
            Section {
                content
            }
        }
    }

    private func shownBinding(_ provider: UsageProvider) -> Binding<Bool> {
        Binding(
            get: { settings.isShown(provider) },
            set: { shown in
                // An action on the real usage ends any debug sample.
                model.dropSample()
                settings.setProvider(provider, shown: shown)
                if shown {
                    model.refresh(provider, force: true)
                }
            }
        )
    }

    private func statusText(_ provider: UsageProvider) -> String {
        let status = model.status(of: provider)
        if model.isRefreshing(provider), status.checkedAt == nil {
            return localized(en: "Loading…", zh: "正在读取…")
        }
        // A provider never read and not shown is not being read either.
        if status.checkedAt == nil, !settings.isShown(provider) {
            return localized(en: "Off", zh: "未开启")
        }
        return status.summary
    }
}
