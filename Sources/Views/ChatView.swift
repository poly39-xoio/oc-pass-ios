import SwiftUI

struct ChatView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = ""
    @State private var recording = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.showSessions = true } label: {
                    Image(systemName: "list.bullet")
                }
                Text(model.currentSession?.title ?? "OpenClaw").font(.headline).lineLimit(1)
                Spacer()
                if model.isDemo {
                    Text("DEMO").font(.caption2).padding(4).background(.orange).cornerRadius(4)
                    Button("退出") { model.exitDemo() }
                        .font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(0.12)).cornerRadius(8)
                }
                if model.streaming { ProgressView().controlSize(.small) }
                Button { model.showSettings = true } label: { Image(systemName: "gearshape") }
            }
            .padding()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.messages) { m in
                            MessageBubble(message: m).id(m.id)
                        }
                    }.padding()
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let last = model.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            HStack(spacing: 10) {
                Button { recording.toggle() } label: {
                    Image(systemName: recording ? "waveform" : "mic")
                        .frame(width: 36, height: 36)
                }
                TextField("訊息…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    model.send(draft); draft = ""
                } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            Text(message.text)
                .padding(10)
                .background(message.role == .user ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.18))
                .foregroundStyle(message.role == .user ? .white : .primary)
                .cornerRadius(14)
                .opacity(message.pending ? 0.6 : 1)
            if message.role != .user { Spacer() }
        }
    }
}
