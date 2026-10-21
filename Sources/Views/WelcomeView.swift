import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("OpenClaw")
                .font(.system(size: 40, weight: .black))
            Text("手機上的 agent 遙控器")
                .foregroundStyle(.secondary)

            Spacer()

            Button { model.showScanner = true } label: {
                Label("掃描 QR 連線", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)

            Button("手動輸入 gateway") { model.showSettings = true }
                .frame(maxWidth: .infinity, minHeight: 44)

            Button("先看 Demo") { model.startDemo() }
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
        .overlay(alignment: .bottom) {
            if case .failed(let msg) = model.state {
                Text(msg).font(.footnote).foregroundStyle(.red).padding(.bottom, 8)
            }
        }
    }
}
