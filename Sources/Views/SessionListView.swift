import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.sessions) { s in
                            Button {
                                model.select(s)
                                dismiss()
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
                                    if model.currentSession?.id == s.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Theme.panel)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await model.refreshSessions() }

                if model.sessions.isEmpty {
                    Text(L("沒有工作階段")).font(Theme.ui(13)).foregroundStyle(.white.opacity(0.75))
                }
            }
            .safeAreaInset(edge: .top) {
                SheetHeader(title: L("工作階段"), onDone: { dismiss() })
            }
            .navigationTitle("工作階段")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
