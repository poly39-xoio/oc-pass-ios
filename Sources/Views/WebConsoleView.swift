import SwiftUI
import WebKit

/// 官方 Control UI 的 WebView 外殼(設定 / cron / activity / 節點 / 用量都在裡面)
struct WebConsoleView: View {
    let baseURL: URL
    let token: TokenString
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true
    @State private var error: String?
    @State private var reloadToken = UUID()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                if let error {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(error)
                            .font(Theme.ui(13))
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                        Button("重新載入") { reload() }
                            .font(Theme.ui(14, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22).padding(.vertical, 10)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                } else {
                    WebView(url: consoleURL, loading: $loading, error: $error)
                        .id(reloadToken)
                    if loading {
                        VStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("載入控制台…")
                                .font(Theme.ui(12))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.bg.opacity(0.85))
                    }
                }
            }
            .navigationTitle("控制台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
    }

    private func reload() {
        error = nil
        loading = true
        reloadToken = UUID()
    }

    /// wss://host/oc  →  https://host/oc/#token=…
    private var consoleURL: URL {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        comps?.scheme = (baseURL.scheme == "ws") ? "http" : "https"
        comps?.query = nil
        comps?.fragment = nil
        var url = comps?.url ?? baseURL
        if !url.path.hasSuffix("/oc") { url.appendPathComponent("oc") }
        var base = url.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? token
        return URL(string: base + "/#token=" + encoded) ?? url
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var loading: Bool
    @Binding var error: String?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = .clear
        web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25))
        context.coordinator.startTimeout()
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: WebView
        private var timeoutTask: Task<Void, Never>?

        init(_ parent: WebView) { self.parent = parent }

        func startTimeout() {
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 26_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await MainActor.run {
                    if self.parent.loading {
                        self.parent.loading = false
                        self.parent.error = "連線逾時 — 檢查 gateway 是否可用、token 是否正確"
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            timeoutTask?.cancel()
            parent.loading = false
            parent.error = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(error)
        }

        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(.performDefaultHandling, nil)
        }

        private func finish(_ err: Error) {
            timeoutTask?.cancel()
            parent.loading = false
            let ns = err as NSError
            if ns.code == NSURLErrorCancelled { return }
            parent.error = "載入失敗:\(err.localizedDescription)"
        }
    }
}
