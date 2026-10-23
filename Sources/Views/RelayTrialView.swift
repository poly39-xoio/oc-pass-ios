import SwiftUI
import UIKit

/// 免費試用 1 天:顯示安裝指令,複製到電腦貼上即可
struct RelayTrialView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        SheetHeader(title: L("免費試用 1 天"), onDone: { dismiss() })

                        if model.trialLoading {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text(L("正在建立試用通道…")).foregroundStyle(.white)
                            }
                        } else if let err = model.trialError {
                            Text(err).foregroundStyle(Theme.warn).font(Theme.ui(14))
                            Button(L("重新試一次")) { model.startTrial() }
                                .font(Theme.ui(14, .bold))
                        } else if let cmd = model.trialCommand {
                            Text(L("1. 在跑 OpenClaw 的電腦上，貼上這行並執行一次"))
                                .font(Theme.ui(13, .semibold)).foregroundStyle(.white)
                            Text(cmd)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.ink)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.panel)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Button {
                                UIPasteboard.general.string = cmd
                                copied = true
                            } label: {
                                Text(copied ? L("已複製") : L("複製指令"))
                                    .font(Theme.ui(15, .bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(Theme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            Text(L("2. 安裝完成後，終端機會顯示 QR；用這支 App 掃描即可連線"))
                                .font(Theme.ui(13)).foregroundStyle(.white.opacity(0.85))
                            Text(L("3. 之後開機自動啟動，不用再做任何事"))
                                .font(Theme.ui(13)).foregroundStyle(.white.opacity(0.85))

                            if let exp = model.trialExpiresAt {
                                let f = DateFormatter()
                                let _ = f.dateFormat = "MM/dd HH:mm"
                                Text("\(L("試用到期"))：\(f.string(from: exp))")
                                    .font(Theme.ui(12)).foregroundStyle(.white.opacity(0.7))
                            }
                            Text(L("試用 1 天後，可選擇 $3/月 或 $30/年 繼續使用"))
                                .font(Theme.ui(12)).foregroundStyle(Theme.panel.opacity(0.9))
                        } else {
                            Text(L("按下面的按鈕開始"))
                                .foregroundStyle(.white)
                            Button(L("開始免費試用")) { model.startTrial() }
                                .font(Theme.ui(15, .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Theme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            if model.trialCommand == nil && !model.trialLoading { model.startTrial() }
        }
    }
}
