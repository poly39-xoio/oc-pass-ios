import SwiftUI
import UIKit

/// 一鍵連線:建立通道 → 複製一行指令到電腦 → App 自動接上(不用掃 QR、不用貼配對碼)
struct RelayTrialView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SheetHeader(title: L("一鍵連線"), onDone: { dismiss() })

                        Text(L("免費 3 天 · 之後 $2.99/月 或 $24.99/年（年繳省 30%）"))
                            .font(Theme.ui(12))
                            .foregroundStyle(.white.opacity(0.7))

                        if model.trialLoading {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text(L("正在建立連線通道…")).foregroundStyle(.white)
                            }
                            .font(Theme.ui(14))
                        } else if let err = model.trialError {
                            Text(err).foregroundStyle(Theme.warn).font(Theme.ui(14))
                            bigButton(L("重新試一次")) { model.startTrial() }
                        } else if let cmd = model.trialCommand {
                            stepText("1", L("在跑 OpenClaw 的電腦上，貼上這行並按 Enter"))
                            Text(cmd)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.ink)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.panel)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            bigButton(copied ? L("已複製 ✓") : L("複製指令")) {
                                UIPasteboard.general.string = cmd
                                copied = true
                            }

                            stepText("2", L("不用做其他事 — 電腦裝好後，這支 App 會自動接上"))
                            HStack(spacing: 8) {
                                if model.relayConnected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(L("已連線")).foregroundStyle(.white)
                                } else {
                                    ProgressView().tint(.white)
                                    Text(L("等待電腦端連上…")).foregroundStyle(.white.opacity(0.85))
                                }
                            }
                            .font(Theme.ui(14, .semibold))

                            if let exp = model.trialExpiresAt {
                                let f = DateFormatter()
                                let _ = f.dateFormat = "MM/dd HH:mm"
                                Text("\(L("免費到"))：\(f.string(from: exp))")
                                    .font(Theme.ui(12))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        } else {
                            Text(L("按下面按鈕，30 秒內就能連上你的 OpenClaw"))
                                .font(Theme.ui(14))
                                .foregroundStyle(.white)
                            bigButton(L("開始免費連線")) { model.startTrial() }
                            Text(L("不需要註冊帳號，也不必自己有網域或公網 IP。"))
                                .font(Theme.ui(12))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            if model.trialCommand == nil { model.startTrial() }
            else if model.trialChannel != nil { model.startTrialWatch() }
        }
    }

    private func stepText(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n)
                .font(Theme.ui(12, .black))
                .foregroundStyle(Theme.ink)
                .frame(width: 20, height: 20)
                .background(Theme.panel)
                .clipShape(Circle())
            Text(text)
                .font(Theme.ui(13, .semibold))
                .foregroundStyle(.white)
        }
    }

    private func bigButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.ui(15, .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
