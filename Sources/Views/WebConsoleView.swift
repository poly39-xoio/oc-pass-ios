import SwiftUI
import WebKit

/// 官方 Control UI 的 WebView 外殼(設定 / cron / activity / 節點 / 用量都在裡面)
struct WebConsoleView: View {
    let baseURL: URL
    let token: TokenString
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ZStack {
                WebView(url: consoleURL, loading: $loading)
                if loading { ProgressView() }
            }
            .navigationTitle("控制台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
    }

    private var consoleURL: URL {
        // wss://host/oc → https://host/oc/#token=...
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        comps?.scheme = (baseURL.scheme == "ws") ? "http" : "https"
        var url = comps?.url ?? baseURL
        if !url.path.hasSuffix("/oc") { url.appendPathComponent("oc") }
        return URL(string: url.absoluteString + "/#token=" + token) ?? url
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var loading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: WebView
        init(_ parent: WebView) { self.parent = parent }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.loading = false
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.loading = false
        }
    }
}
