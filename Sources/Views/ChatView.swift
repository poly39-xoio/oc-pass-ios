import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = ""
    @State private var inputHeight: CGFloat = Theme.inputMin
    @State private var inputFocused = false
    @State private var pending: [PendingAttachment] = []
    @State private var showAttachMenu = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 0) {
                header
                if case .connecting = model.state { reconnectingBanner }
                messageList
                attachmentChips
                inputBar
                bottomBar
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName)
                    .font(Theme.ui(16, .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(model.currentSession?.title ?? "OC Pass")
                    .font(Theme.ui(10))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
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
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture { inputFocused = false }   // 點空白處收起鍵盤(像 Telegram)
            .onChange(of: model.messages.count) { _, _ in
                if let last = model.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Attachment chips

    @ViewBuilder
    private var attachmentChips: some View {
        if !pending.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pending) { a in
                        HStack(spacing: 6) {
                            Image(systemName: a.isImage ? "photo" : "doc")
                                .font(.system(size: 12, weight: .semibold))
                            Text(a.name)
                                .font(Theme.ui(12, .medium))
                                .lineLimit(1)
                            Button {
                                pending.removeAll { $0.id == a.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.panel2)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                showAttachMenu = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
            }

            GrowingTextField(text: $draft, height: $inputHeight, focused: $inputFocused,
                             minHeight: Theme.inputMin, maxHeight: Theme.inputMax)
                .frame(height: inputHeight)
                .padding(.horizontal, 10)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                sendNow()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Theme.accent : Theme.muted.opacity(0.6))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .confirmationDialog("附加檔案", isPresented: $showAttachMenu, titleVisibility: .visible) {
            Button("照片") { showPhotoPicker = true }
            Button("檔案") { showFileImporter = true }
            Button("取消", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): urls.forEach(loadFile)
            case .failure: break
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let name = "photo-\(Int(Date().timeIntervalSince1970)).jpg"
                    await MainActor.run {
                        pending.append(PendingAttachment(name: name, mimeType: "image/jpeg", data: data))
                    }
                }
                await MainActor.run { photoItem = nil }
            }
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pending.isEmpty
    }

    private func sendNow() {
        guard canSend else { return }
        let text = draft
        let files = pending
        // 先清空 UI,再送出(避免文字殘留在輸入框、框不縮回)
        draft = ""
        pending = []
        inputHeight = Theme.inputMin
        model.send(text, attachments: files)
    }

    private func loadFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        pending.append(PendingAttachment(name: url.lastPathComponent, mimeType: mime, data: data))
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
                let tk = model.gatewayToken
                WebConsoleView(baseURL: url, token: tk)
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
