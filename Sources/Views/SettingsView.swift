import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = "wss://xoio.io/oc"
    @State private var name = ""
    @State private var token = String()
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        section("使用者名稱") {
                            VStack(alignment: .leading, spacing: 8) {
                                field("你的名字") {
                                    TextField("你的名字", text: $name)
                                        .textInputAutocapitalization(.words)
                                        .autocorrectionDisabled()
                                        .font(Theme.ui(15))
                                        .foregroundStyle(Theme.ink)
                                        .onChange(of: name) { _, v in model.setUserName(v) }
                                }
                                Text("只顯示在這支 App(App 裡的名字),不會改到 gateway 帳號")
                                    .font(Theme.ui(11))
                                    .foregroundStyle(Theme.muted)
                            }
                        }

                        section("手動連線") {
                            VStack(spacing: 10) {
                                field("wss://your-gateway/oc") {
                                    TextField("wss://your-gateway/oc", text: $url)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .keyboardType(.URL)
                                        .font(Theme.ui(15))
                                        .foregroundStyle(Theme.ink)
                                }
                                field("Gateway token") {
                                    SecureField("Gateway token", text: $token)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .font(Theme.ui(15))
                                        .foregroundStyle(Theme.ink)
                                }
                                if let e = localError {
                                    Text(e).font(Theme.ui(12)).foregroundStyle(Theme.warn)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Button {
                                    connect()
                                } label: {
                                    HStack {
                                        Text("連線").font(Theme.ui(15, .bold))
                                        if isBusy { Spacer(); ProgressView().controlSize(.small) }
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(Theme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .disabled(isBusy)
                            }
                        }

                        section("關於") {
                            VStack(spacing: 10) {
                                Link(destination: URL(string: "https://xoio.io/privacy.html")!) {
                                    HStack {
                                        Text("隱私政策").font(Theme.ui(15)).foregroundStyle(Theme.ink)
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(Theme.muted)
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(height: 46)
                                    .background(Theme.panel2)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                Text("版本 \(appVersion)")
                                    .font(Theme.ui(12))
                                    .foregroundStyle(Theme.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        Button("中斷連線 / 離開 Demo") {
                            model.disconnect(); model.exitDemo(); dismiss()
                        }
                        .font(Theme.ui(15, .semibold))
                        .foregroundStyle(Theme.warn)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(18)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: model.state) { _, newValue in
                if case .ready = newValue { dismiss() }
            }
            .onAppear { name = model.userName }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.ui(12, .bold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.leading, 4)
            content()
                .padding(14)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
    }

    private func field<Content: View>(_ placeholder: String, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(Theme.panel2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var isBusy: Bool {
        model.state == .connecting || model.state == .authenticating
    }

    private func connect() {
        localError = nil
        guard let normalized = normalize(url) else {
            localError = "網址格式不對（例:wss://xoio.io/oc）"
            return
        }
        let tk = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tk.isEmpty else { localError = "請貼上 Gateway token"; return }
        model.connect(url: normalized, token: tk)
    }

    /// 接受 xoio.io/oc、https://xoio.io/oc、wss://xoio.io/oc 三種寫法
    private func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "wss://" + s }
        if s.hasPrefix("https://") { s = "wss://" + s.dropFirst("https://".count) }
        if s.hasPrefix("http://") { s = "ws://" + s.dropFirst("http://".count) }
        if !s.hasSuffix("/oc") && !s.hasSuffix("/oc/") {
            if s.hasSuffix("/") { s += "oc" } else { s += "/oc" }
        }
        return URL(string: s)
    }
}
