import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = "wss://xoio.io/oc"
    @State private var token = String()
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("手動連線") {
                    TextField("wss://your-gateway/oc", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Gateway token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let e = localError {
                        Text(e).font(.footnote).foregroundStyle(.red)
                    }
                    Button {
                        connect()
                    } label: {
                        HStack {
                            Text("連線")
                            if isBusy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isBusy)
                }
                Section("關於") {
                    Link("隱私政策", destination: URL(string: "https://xoio.io/privacy.html")!)
                    Text("版本 0.1.0").foregroundStyle(.secondary)
                }
                Section {
                    Button("中斷連線 / 離開 Demo", role: .destructive) {
                        model.disconnect(); model.exitDemo(); dismiss()
                    }
                }
            }
            .navigationTitle("設定")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
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
