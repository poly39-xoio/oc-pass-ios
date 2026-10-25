import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let _ = model.languageRevision
        ZStack {
            Theme.background

            VStack(spacing: 0) {
                Spacer()

                // Logo tile
                Text(L("OC"))
                    .font(Theme.ui(26, .black))
                    .foregroundStyle(Theme.panel)
                    .frame(width: 86, height: 86)
                    .background(
                        LinearGradient(colors: [Theme.accentHi, Theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: Theme.ink.opacity(0.28), radius: 12, y: 8)

                Text(L("OC Pass"))
                    .font(Theme.ui(30, .black))
                    .foregroundStyle(.white)
                    .padding(.top, 14)

                Text(L("openclaw dashboard"))
                    .font(Theme.ui(14, .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.top, 4)
                    .padding(.bottom, 26)

                // Panel
                VStack(spacing: 10) {
                    Button {
                        model.showScanner = true
                    } label: {
                        VStack(spacing: 3) {
                            Text(L("掃描 QR 連線")).font(Theme.ui(16, .bold))
                            Text(L("用電腦執行 openclaw qr，掃它產生的 QR")).font(Theme.ui(11)).opacity(0.85)
                        }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Button {
                        model.showSettings = true
                    } label: {
                        VStack(spacing: 3) {
                            Text(L("手動輸入 gateway")).font(Theme.ui(16, .semibold))
                            Text(L("自己填 URL 與 token（進階）")).font(Theme.ui(11)).opacity(0.75)
                        }
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Theme.panel2)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Theme.bg.opacity(0.35), lineWidth: 1)
                            )
                    }

                    Button {
                        model.startDemo()
                    } label: {
                        VStack(spacing: 3) {
                            Text(L("Demo")).font(Theme.ui(14, .bold))
                            Text(L("不用連線，先看看介面")).font(Theme.ui(11)).opacity(0.7)
                        }
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.panel2)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(.top, 4)
                }
                .padding(18)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .shadow(color: Theme.ink.opacity(0.18), radius: 14, y: 10)

                Spacer()

                statusLine
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 30)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                model.setLanguage(Language.isEnglish ? "zh" : "en")
            } label: {
                Text(Language.isEnglish ? "中文" : "EN")
                    .font(Theme.ui(13, .black))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            }
            .padding(.top, 52)
            .padding(.trailing, 16)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        VStack(spacing: 6) {
            switch model.state {
            case .connecting: ProgressView().tint(.white)
            case .authenticating: ProgressView().tint(.white)
            case .pairing(let id):
                Text(String(format: L("需要配對核准:%@"), id))
                    .font(Theme.ui(12)).foregroundStyle(.white.opacity(0.85))
            case .failed(let msg):
                Text(msg)
                    .font(Theme.ui(12)).foregroundStyle(Theme.warn)
                    .multilineTextAlignment(.center)
            default:
                EmptyView()
            }
        }
    }
}
