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
            VStack(spacing: 6) {
                if case .connecting = model.state { ProgressView("連線中…") }
                if case .authenticating = model.state { ProgressView("認證中…") }
                if case .pairing(let id) = model.state {
                    Text("需要配對核准:\(id)").font(.footnote).foregroundStyle(.orange)
                }
                if case .failed(let msg) = model.state {
                    Text(msg).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
            }
            .padding(.bottom, 8)
        }
    }
}
