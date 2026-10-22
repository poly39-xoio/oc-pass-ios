import SwiftUI

struct ChatView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = ""
    @State private var inputHeight: CGFloat = 38

    var body: some View {
        VStack(spacing: 0) {
            header
            messageList
            inputBar
            bottomBar
        }
        .background(Color.black.opacity(0.02))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button { model.showSessions = true } label: {
                Image(systemName: "list.bullet")
            }
            Text(model.currentSession?.title ?? "OpenClaw")
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if model.isDemo {
                Text("DEMO")
                    .font(.caption2).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.85)).cornerRadius(5)
            }
            if model.streaming {
                ProgressView().controlSize(.small)
            }
            Button { model.showSettings = true } label: {
                Image(systemName: "gearshape")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.messages) { m in
                        MessageBubble(message: m).id(m.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: model.messages.count) { _, _ in
                if let last = model.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            GrowingTextField(text: $draft, height: $inputHeight)
                .frame(height: inputHeight)
                .padding(.horizontal, 10)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(18)

            Button {
                let text = draft
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                draft = ""                      // 先清空，避免送不出去時卡字
                inputHeight = 38               // 立刻縮回單行高度
                model.send(text)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Button { model.showSessions = true } label: {
                Label("會話", systemImage: "bubble.left.and.bubble.right")
            }
            Spacer()
            Button { model.showConsole = true } label: {
                Label("控制台", systemImage: "rectangle.3.group")
            }
            Spacer()
            Button { model.showSettings = true } label: {
                Label("設定", systemImage: "slider.horizontal.3")
            }
            Spacer()
            Button(role: .destructive) {
                model.disconnect(); model.exitDemo()
            } label: {
                Label("中斷", systemImage: "xmark.circle")
            }
        }
        .font(.caption)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
        .sheet(isPresented: $model.showConsole) {
            if let url = model.gatewayURL {
                WebConsoleView(baseURL: url, token: ***)
            } else {
                Text("尚未連線").padding()
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(message.role == .user ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.16))
                .foregroundStyle(message.role == .user ? .white : .primary)
                .cornerRadius(14)
                .textSelection(.enabled)
            if message.role != .user { Spacer(minLength: 40) }
        }
    }
}
