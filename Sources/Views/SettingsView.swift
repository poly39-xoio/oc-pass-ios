import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("手動連線") {
                    TextField("wss://your-gateway/oc", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Gateway token", text: $token)
                    Button("連線") {
                        if let u = URL(string: url) { model.connect(url: u, token: token); dismiss() }
                    }
                }
                Section("關於") {
                    Link("隱私政策", destination: URL(string: "https://xoio.io/privacy.html")!)
                    Text("版本 0.1.0").foregroundStyle(.secondary)
                }
                Section {
                    Button("中斷連線", role: .destructive) { model.disconnect(); dismiss() }
                }
            }
            .navigationTitle("設定")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}
