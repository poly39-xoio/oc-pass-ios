import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var name = ""
    @State private var token: TokenString = ""
    @State private var localError: String?
    @State private var showHelp = false
    @State private var mode = "direct"
    @State private var relayCode = ""
    @State private var showPaywall = false
    @State private var showTrial = false

    var body: some View {
        let _ = model.languageRevision
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        section(L("使用者名稱")) {
                            VStack(alignment: .leading, spacing: 8) {
                                field("name") {
                                    TextField(L("你的名字"), text: $name)
                                        .textInputAutocapitalization(.words)
                                        .autocorrectionDisabled()
                                        .font(Theme.ui(15))
                                        .foregroundStyle(Theme.ink)
                                        .onChange(of: name) { _, v in model.setUserName(v) }
                                }
                                Text(L("只顯示在這支 App(App 裡的名字),不會改到 gateway 帳號"))
                                    .font(Theme.ui(11))
                                    .foregroundStyle(Theme.muted)
                            }
                        }

                        section(L("手動連線")) {
                            VStack(spacing: 10) {
                                Picker("", selection: $mode) {
                                    Text(L("自己的網址")).tag("direct")
                                    Text("XOIO Relay").tag("relay")
                                }
                                .pickerStyle(.segmented)

                                if mode == "relay" {
                                    field("relay") {
                                        TextField(L("貼上 Relay 配對碼"), text: $relayCode)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                            .font(Theme.ui(14))
                                            .foregroundStyle(Theme.ink)
                                    }
                                } else {
                                field("url") {
                                    TextField("ws://192.168.1.20:18789 或 wss://your-gateway", text: $url)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .keyboardType(.URL)
                                        .font(Theme.ui(15))
                                        .foregroundStyle(Theme.ink)
                                }
                                }
                                if mode == "direct" {
                                    Text(L("填你自己 gateway 的位址；沒有網域或公網 IP，請用上面的 XOIO Relay。"))
                                        .font(Theme.ui(11))
                                        .foregroundStyle(Theme.muted)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    field("token") {
                                        SecureField("Gateway token", text: $token)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                            .font(Theme.ui(15))
                                            .foregroundStyle(Theme.ink)
                                    }
                                }
                                if let e = localError {
                                    Text(e).font(Theme.ui(12)).foregroundStyle(Theme.warn)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Button {
                                    connect()
                                } label: {
                                    HStack {
                                        Text(L("連線")).font(Theme.ui(15, .bold))
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

                        section("XOIO Relay") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L("不用網域、不用開 port，出門也能連。免費 100MB/月；訂閱 $2.99/月 或 $24.99/年（前 3 天免費，1GB/月）。"))
                                    .font(Theme.ui(12)).foregroundStyle(Theme.ink)
                                Button(L("免費連線（100MB/月）")) { showTrial = true }
                                    .font(Theme.ui(15, .bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background(Theme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                Button(L("訂閱 / 還原購買")) { showPaywall = true }
                                    .font(Theme.ui(14, .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .frame(maxWidth: .infinity, minHeight: 42)
                                    .background(Theme.panel)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }

                        section(L("使用說明")) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L("OC Pass 是針對 OpenClaw Gateway 所設計的優化器。"))
                                Text(L("我們不會收集你的對話與資料,內容只會送到你自己的 gateway。"))
                                Text(L("1. 在你的電腦或伺服器安裝 OpenClaw,並啟動 gateway。"))
                                Text(L("2. 在 gateway 上執行 openclaw qr,用手機掃描產生的 QR。"))
                                Text(L("3. 沒有網域或公網 IP?可在設定改用 XOIO Relay(訂閱制)。"))
                                Text(L("檔案上限:圖片 6 MB、其他檔案 18 MB。"))
                                Text(L("隨時可在設定頁「移除這台裝置」斷開配對。"))
                                Link(destination: URL(string: "mailto:io@xoio.io")!) {
                                    Text("✉️ io@xoio.io")
                                        .font(Theme.ui(13, .semibold))
                                        .foregroundStyle(Theme.accent)
                                }
                                Text(L("有問題或需要協助，歡迎寫信給我們。"))
                                    .font(Theme.ui(12))
                                    .foregroundStyle(Theme.ink.opacity(0.75))
                            }
                            .font(Theme.ui(12))
                            .foregroundStyle(Theme.ink)
                            .lineSpacing(3)
                        }

                        Button(L("中斷連線（保留配對）")) {
                            model.disconnect(); dismiss()
                        }
                        .font(Theme.ui(15, .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Button(L("移除這台裝置（清除配對）")) {
                            model.forgetDevice(); dismiss()
                        }
                        .font(Theme.ui(15, .semibold))
                        .foregroundStyle(Theme.warn)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        section(L("語言")) {
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("", selection: Binding(
                                    get: { Language.current },
                                    set: { model.setLanguage($0) }
                                )) {
                                    Text("中文").tag("zh")
                                    Text("English").tag("en")
                                }
                                .pickerStyle(.segmented)
                            }
                        }

                        // 隱私 / 關於 → 最下層
                        section(L("關於")) {
                            VStack(spacing: 10) {
                                Link(destination: URL(string: "https://xoio.io/privacy.html")!) {
                                    HStack {
                                        Text(L("隱私政策")).font(Theme.ui(15)).foregroundStyle(Theme.ink)
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
                                Text("\(L("版本")) \(appVersion)")
                                    .font(Theme.ui(12))
                                    .foregroundStyle(Theme.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(18)
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
            }
            .safeAreaInset(edge: .top) {
                SheetHeader(title: L("設定"), onDone: { dismiss() })
            }
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: model.state) { _, newValue in
                if case .ready = newValue { dismiss() }
            }
            .onAppear { name = model.userName }
            .sheet(isPresented: $showTrial) { RelayTrialView().environmentObject(model) }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("收鍵盤")) { hideKeyboard() }
                }
            }
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

    private func field<Content: View>(_ id: String, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(Theme.panel2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var isBusy: Bool {
        model.state == .connecting || model.state == .authenticating
    }

    private func connect() {
        localError = nil
        let tk0 = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == "relay" {
            guard !relayCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                localError = L("請貼上 Relay 配對碼"); return
            }
            model.connectRelay(code: relayCode, token: tk0)
            return
        }
        guard let normalized = normalize(url) else {
            localError = L("網址格式不對（例：ws://192.168.1.20:18789）")
            return
        }
        let tk = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tk.isEmpty else { localError = L("請貼上 Gateway token"); return }
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
