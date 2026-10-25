import AppKit
import NotchKit
import Observation
import SwiftUI
import WebKit

/// The sign-in window's content: a thin bar (back, reload, a lock with the
/// current page's host, Done) over a web view that browses with
/// `UsageWebSession`'s data store, starting at the provider's sign-in page.
/// The host is always in view, so the user sees which site gets the password.
public struct UsageSignInView: View {
    private let page: UsageSignInPage
    private let onDone: @MainActor () -> Void

    public init(provider: UsageProvider, onDone: @escaping @MainActor () -> Void) {
        // Created with the view, which the window keeps (`@State` needs a macro
        // plugin the Command Line Tools do not ship).
        page = UsageSignInPage(provider: provider, session: .shared)
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    page.webView.goBack()
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .disabled(!page.canGoBack)
                .help(localized(en: "Back", zh: "返回"))
                Button {
                    page.webView.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(localized(en: "Reload", zh: "重新载入"))
                HStack(spacing: 4) {
                    Image(systemName: page.isSecure ? "lock.fill" : "lock.open")
                        .foregroundStyle(.secondary)
                    Text(page.host)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.callout)
                .padding(.leading, 4)
                if page.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer(minLength: 8)
                Button(localized(en: "Done", zh: "完成")) {
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            SignInWebView(webView: page.webView)
        }
        .frame(minWidth: 420, minHeight: 480)
    }
}

/// The sign-in web view and what the bar shows about it.
@MainActor
@Observable
final class UsageSignInPage {
    private(set) var host = ""
    private(set) var isSecure = true
    private(set) var canGoBack = false
    private(set) var isLoading = false

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private let delegate: SignInDelegate

    init(provider: UsageProvider, session: UsageWebSession) {
        webView = WKWebView(frame: .zero, configuration: session.makeConfiguration())
        delegate = SignInDelegate(session: session)
        host = Self.hostText(provider.signInURL)
        delegate.page = self
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.load(URLRequest(url: provider.signInURL))
    }

    /// Follows the web view's history and loading. `committed` comes only from
    /// `didCommit`: the host changes once the new page replaces the old one,
    /// never for a navigation still under way (whose provisional URL
    /// `webView.url` already reports while the old page and its form show).
    func update(committed: Bool = false) {
        if committed, let url = webView.url {
            host = Self.hostText(url)
            isSecure = url.scheme == "https"
        }
        canGoBack = webView.canGoBack
        isLoading = webView.isLoading
    }

    /// "claude.ai", or "host:port" when the URL names a port.
    private static func hostText(_ url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        return url.port.map { "\(host):\($0)" } ?? host
    }
}

/// Keeps the sign-in web view on https pages it can show, in one view, and
/// records its user agent for the usage requests.
@MainActor
private final class SignInDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var page: UsageSignInPage?
    private let session: UsageWebSession

    init(session: UsageWebSession) {
        self.session = session
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        // Nothing is downloaded.
        guard !navigationAction.shouldPerformDownload, let url = navigationAction.request.url else { return .cancel }
        let scheme = url.scheme?.lowercased()
        if scheme == "https" || url.absoluteString == "about:blank" {
            return .allow
        }
        // Challenge widgets may build their frames from srcdoc, blob, or data
        // URLs; the page itself stays on https.
        if navigationAction.targetFrame?.isMainFrame == false, ["about", "blob", "data"].contains(scheme) {
            return .allow
        }
        return .cancel
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        // Nothing is downloaded: what the view cannot show is dropped.
        navigationResponse.canShowMIMEType ? .allow : .cancel
    }

    /// `window.open` and target="_blank" open in this view instead of a new
    /// window, for https pages only: an empty `window.open('')` must not replace
    /// the sign-in page with about:blank.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.request.url?.scheme?.lowercased() == "https" {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        page?.update()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        page?.update(committed: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        page?.update()
        // Read in a world of Notch's own, where no page script can redefine
        // `navigator.userAgent`.
        webView.evaluateJavaScript("navigator.userAgent", in: nil, in: .defaultClient) { [weak self] result in
            guard case .success(let value) = result, let userAgent = value as? String else { return }
            self?.session.recordUserAgent(userAgent)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        page?.update()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        page?.update()
    }
}

private struct SignInWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
