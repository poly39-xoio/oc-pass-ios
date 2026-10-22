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

    private var draftKey: String { "ocpass.draft." + (model.currentSession?.id ?? "none") }

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
        .onAppear { restoreDraft() }
        .onChange(of: model.currentSession?.id) { _, _ in restoreDraft() }
        .onChange(of: draft) { _, v in persistDraft(v) }
    }

    /// 離開 App / 切換 session 都還在
    private func restoreDraft() {
        let perSession = UserDefaults.standard.string(forKey: draftKey) ?? ""
        let last = UserDefaults.standard.string(forKey: "ocpass.draft.last") ?? ""
        draft = perSession.isEmpty ? last : perSession
        inputHeight = Theme.inputMin
    }

    private func persistDraft(_ value: String) {
        if value.isEmpty {
            UserDefaults.standard.removeObject(forKey: draftKey)
            UserDefaults.standard.removeObject(forKey: "ocpass.draft.last")
        } else {
            UserDefaults.standard.set(value, forKey: draftKey)
            UserDefaults.standard.set(value, forKey: "ocpass.draft.last")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text(model.displayName)
                .font(Theme.ui(15, .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            if model.isDemo {
                Text("DEMO")
                    .font(Theme.ui(11, .black))
                    .tracking(0.5)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Theme.panel)
                    .foregroundStyle(Theme.accent)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
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
                    ForEach(model.messages.filter { !$0.isHidden }) { m in
                        MessageBubble(message: m).id(m.id)
                    }
                    if model.awaitingReply {
                        HStack { TypingBubble(); Spacer(minLength: 40) }
                            .id("typing-indicator")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture { inputFocused = false }   // 點空白處收起鍵盤(像 Telegram)
            .onAppear {
                if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: model.messages.count) { _, _ in
                if let last = model.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: model.awaitingReply) { _, typing in
                if typing { withAnimation { proxy.scrollTo("typing-indicator", anchor: .bottom) } }
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
                    .frame(width: 30, height: 30)
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
                    .font(.system(size: 27))
                    .foregroundStyle(canSend ? Theme.accent : Theme.muted.opacity(0.6))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
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
        persistDraft("")
        Task {
            do {
                try await model.sendAsync(text, attachments: files)
            } catch {
                // 送不出去 → 把文字與附件還原,不要讓你的字消失
                draft = text
                pending = files
                persistDraft(text)
            }
        }
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
            Button { model.showDashboard = true } label: {
                Label("控制台", systemImage: "rectangle.3.group")
            }
            Spacer()
            Button { model.showSettings = true } label: {
                Image(systemName: "link")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 34, height: 22)
            }
            .accessibilityLabel("連線")
        }
        .font(Theme.ui(12, .semibold))
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(Theme.accent.opacity(0.92))
        .sheet(isPresented: $model.showDashboard) {
            DashboardView()
        }
    }
}

/// 思考中的循環動畫(三個點)
struct TypingBubble: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    let wave = 0.35 + 0.65 * max(0, sin(t * 3.2 - Double(i) * 0.7))
                    Circle().fill(Theme.ink.opacity(wave)).frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
