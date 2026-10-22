import SwiftUI

/// 連上 gateway 後的第一站:由使用者自己選要進哪個對話,或開一個全新的
struct SessionPickerView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Theme.background
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("選擇工作階段")
                        .font(Theme.ui(22, .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button { model.showSettings = true } label: {
                        Image(systemName: "gearshape").foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)

                Text("選一個現有對話,或開一個新的(不同於 Telegram 的獨立對話)")
                    .font(Theme.ui(12))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                Button {
                    model.createSession()
                } label: {
                    HStack(spacing: 8) {
                        if model.creatingSession {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "plus.bubble.fill")
                        }
                        Text("開新對話")
                            .font(Theme.ui(15, .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(model.creatingSession)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                if let err = model.sessionError {
                    Text(err)
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.warn)
                        .padding(.horizontal, 20)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.sessions) { s in
                            Button {
                                model.select(s)
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(s.title)
                                            .font(Theme.ui(15, .semibold))
                                            .foregroundStyle(Theme.ink)
                                            .lineLimit(1)
                                        Text(s.id)
                                            .font(Theme.ui(10))
                                            .foregroundStyle(Theme.muted)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if s.unread > 0 {
                                        Text("\(s.unread)")
                                            .font(Theme.ui(11, .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 7).padding(.vertical, 3)
                                            .background(Theme.warn)
                                            .clipShape(Capsule())
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Theme.muted)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Theme.panel)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .refreshable { await model.refreshSessions() }

                if model.sessions.isEmpty && model.sessionError == nil {
                    Text("還沒有任何工作階段 — 按上面的「開新對話」開始")
                        .font(Theme.ui(12))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 20)
                }
            }
        }
    }
}
