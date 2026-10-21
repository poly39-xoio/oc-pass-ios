import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.sessions) { s in
                    Button {
                        model.select(s)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).font(.body).lineLimit(1)
                                Text(s.id).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if s.unread > 0 {
                                Text("\(s.unread)").font(.caption2).padding(4)
                                    .background(Color.accentColor).cornerRadius(8)
                            }
                            if model.currentSession?.id == s.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
            .refreshable { await model.refreshSessions() }
            .navigationTitle("工作階段")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .overlay {
                if model.sessions.isEmpty {
                    Text("沒有工作階段").foregroundStyle(.secondary)
                }
            }
        }
    }
}
