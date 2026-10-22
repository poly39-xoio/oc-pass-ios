import SwiftUI

struct ChatView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = ""
    @State private var inputHeight: CGFloat = 38

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 0) {
                header
                if case .connecting = model.state { reconnectingBanner }
                messageList
                inputBar
                bottomBar
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button { model.showSessions = true } label: {
                Image(systemName: "list.bullet").foregroundStyle(.white)
            }
            Text(model.currentSession?.title ?? "OC Pass")
                .font(Theme.ui(16, .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            if model.isDemo {
                Text("DEMO")
                    .font(Theme.ui(10, .bold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.warn.opacity(0.9))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            if model.streaming { ProgressView().tint(.white).controlSize(.small) }
            Button { model.showSettings = true } label: {
                Image(systemName: "gearshape").foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var reconnectingBanner: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(.white)
            Text("連線中斷,正在重連…")
                .font(Theme.ui(12, .medium))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Theme.warn.opacity(0.85))
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
                .padding(.vertical, 12)
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
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button {
                let text = draft
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                draft = ""
                inputHeight = 38
                model.send(text)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.accent)
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
        }
        .font(Theme.ui(11, .semibold))
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Theme.accent.opacity(0.92))
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
                .font(Theme.ui(15))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(bubbleColor)
                .foregroundStyle(textColor)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .textSelection(.enabled)
            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user: return Theme.accent          // 深石板(白字)
        case .assistant: return Theme.panel      // 淡霧藍(深字)
        case .system: return Theme.warn.opacity(0.15)
        }
    }

    private var textColor: Color {
        switch message.role {
        case .user: return .white
        case .assistant: return Theme.ink
        case .system: return Theme.warn
        }
    }
}
