import SwiftUI
import UIKit
import QuickLook
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
    @State private var sizeWarning: String?
    @StateObject private var speech = SpeechInput()
    @State private var dictationBase = ""

    private var draftKey: String { "ocpass.draft." + (model.currentSession?.id ?? "none") }

    var body: some View {
        let _ = model.languageRevision
        return ZStack {
            Theme.background
            VStack(spacing: 0) {
                header
                if case .connecting = model.state { reconnectingBanner }
                if let warn = model.versionWarning { versionBanner(warn) }
                messageList
                attachmentChips
                inputBar
                bottomBar
            }
        }
        .alert(L("太大"), isPresented: Binding(get: { sizeWarning != nil || speech.error != nil }, set: { if !$0 { sizeWarning = nil; speech.error = nil } })) {
            Button(L("完成")) { sizeWarning = nil }
        } message: {
            Text(sizeWarning ?? speech.error ?? "")
        }
        .onAppear { restoreDraft() }
        .onChange(of: model.currentSession?.id) { _, _ in restoreDraft() }
        .onChange(of: draft) { _, v in persistDraft(v) }
        .onChange(of: speech.transcript) { _, t in
            guard speech.isRecording, !t.isEmpty else { return }
            draft = dictationBase.isEmpty ? t : dictationBase + " " + t
        }
    }

    /// 滾到底:不帶動畫、分幾個時點重試。
    /// 送出訊息時輸入框高度/附件列會變動,只用一次動畫滾動容易停在內容外→整頁空白。
    private func scrollToBottom(_ proxy: ScrollViewProxy, delay: Double, anchor: String = "bottom-anchor") {
        for extra in [0.0, 0.08, 0.18, 0.34] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + extra) {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { proxy.scrollTo(anchor, anchor: .bottom) }
            }
        }
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

    /// 直接從最上層 VC 呈現分享面板(避免包在 SwiftUI .sheet 裡偶發空白頁)
    private func presentShare(_ items: [Any]) {
        guard !items.isEmpty else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
            let window = scene.windows.first(where: { $0.isKeyWindow }),
            let root = window.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let avc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let pop = avc.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        top.present(avc, animated: true)
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
                Text(L("DEMO"))
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

    @ViewBuilder
    private func versionBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12))
            Text(text).font(Theme.ui(11, .medium)).lineLimit(2)
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Theme.warn.opacity(0.75))
    }

    private var reconnectingBanner: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(.white)
            Text(L("連線中斷,正在重連…"))
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
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.messages.filter { !$0.isHidden }) { m in
                        MessageBubble(
                            message: m,
                            onShare: { items in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { presentShare(items) }
                            },
                            onDelete: { model.deleteMessage(m) },
                            onDeleteAttachment: { model.deleteAttachment(of: m) }
                        )
                        .id(m.id)
                    }
                    if model.awaitingReply {
                        HStack { TypingBubble(); Spacer(minLength: 40) }
                            .id("typing-indicator")
                    }
                    Color.clear.frame(height: 1).id("bottom-anchor")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture { inputFocused = false }   // 點空白處收起鍵盤(像 Telegram)
            .onAppear { scrollToBottom(proxy, delay: 0.35) }
            .onChange(of: model.state) { _, newState in
                if case .ready = newState { scrollToBottom(proxy, delay: 0.45) }
            }
            .onChange(of: model.messages.count) { _, _ in scrollToBottom(proxy, delay: 0.05) }
            .onChange(of: model.messages.last?.id) { _, _ in scrollToBottom(proxy, delay: 0.05) }
            .onChange(of: inputHeight) { _, _ in scrollToBottom(proxy, delay: 0.02) }
            .onChange(of: model.streaming) { _, _ in scrollToBottom(proxy, delay: 0.02) }
            .onChange(of: pending.isEmpty) { _, _ in scrollToBottom(proxy, delay: 0.02) }
            .onChange(of: model.awaitingReply) { _, typing in
                if typing { scrollToBottom(proxy, delay: 0.05, anchor: "typing-indicator") }
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
                .frame(minWidth: UIScreen.main.bounds.width, alignment: .trailing)
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

            Button {
                toggleDictation()
            } label: {
                Image(systemName: speech.isRecording ? "mic.circle.fill" : "mic")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(speech.isRecording ? Theme.warn : .white)
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
            Button(L("照片")) { showPhotoPicker = true }
            Button(L("檔案")) { showFileImporter = true }
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
                    // 壓縮放到背景執行,避免大圖卡住主執行緒被系統砍掉
                    let att = await Task.detached { Self.makeImageAttachment(data) }.value
                    await MainActor.run {
                        if let att { pending.append(att) }
                        else { sizeWarning = L("無法讀取這個檔案") }
                    }
                }
                await MainActor.run { photoItem = nil }
            }
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pending.isEmpty
    }

    private func toggleDictation() {
        if speech.isRecording {
            speech.stop()
        } else {
            dictationBase = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            speech.start()
        }
    }

    private func sendNow() {
        guard canSend else { return }
        let text = draft
        let files = pending
        // 先清空 UI,再送出(避免文字殘留在輸入框、框不縮回)
        if speech.isRecording { speech.stop() }
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

    /// 圖片 > 6 MB 自動壓縮(縮尺寸 + 降品質)
    static func makeImageAttachment(_ data: Data) -> PendingAttachment? {
        guard let img = UIImage(data: data) else { return nil }
        let limit = 6 * 1024 * 1024
        var out = img.jpegData(compressionQuality: 0.9) ?? data
        var quality: CGFloat = 0.9
        while out.count > limit && quality > 0.35 {
            quality -= 0.1
            out = img.jpegData(compressionQuality: quality) ?? out
        }
        if out.count > limit {
            let scale = sqrt(Double(limit) / Double(out.count))
            let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(size, false, 1)
            img.draw(in: CGRect(origin: .zero, size: size))
            let small = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            if let s = small?.jpegData(compressionQuality: 0.85) { out = s }
        }
        guard out.count <= limit else { return nil }
        return PendingAttachment(name: "photo-\(Int(Date().timeIntervalSince1970)).jpg", mimeType: "image/jpeg", data: out)
    }

    private func loadFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            sizeWarning = L("無法讀取這個檔案"); return
        }
        if data.count > 18 * 1024 * 1024 {
            sizeWarning = L("這個檔案超過 18 MB,請壓縮後再傳"); return
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        pending.append(PendingAttachment(name: url.lastPathComponent, mimeType: mime, data: data))
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Button { model.showSessions = true } label: {
                Label(L("會話"), systemImage: "bubble.left.and.bubble.right")
            }
            Spacer()
            Button { model.showDashboard = true } label: {
                Label(L("控制台"), systemImage: "rectangle.3.group")
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
    var onShare: ([Any]) -> Void = { _ in }
    var onDelete: () -> Void = {}
    var onDeleteAttachment: () -> Void = {}
    @State private var previewURL: URL?

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                if let data = message.imageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contextMenu {
                            Button {
                                UIPasteboard.general.image = ui
                            } label: {
                                Label(L("複製圖片"), systemImage: "doc.on.doc")
                            }
                            Button {
                                onShare([ui])
                            } label: {
                                Label(L("分享"), systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) { onDelete() } label: {
                                Label(L("刪除照片"), systemImage: "trash")
                            }
                        }
                }
                if let path = message.attachmentPath, FileManager.default.fileExists(atPath: path) {
                    fileCard(path: path, name: message.attachmentName ?? URL(fileURLWithPath: path).lastPathComponent)
                }
                if !visibleText.isEmpty {
                    Text(visibleText)
                        .font(Theme.ui(15))
                        .textSelection(.enabled)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = visibleText
                            } label: {
                                Label(L("複製"), systemImage: "doc.on.doc")
                            }
                            Button {
                                onShare([visibleText])
                            } label: {
                                Label(L("分享文字"), systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) { onDelete() } label: {
                                Label(L("刪除訊息"), systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(bubbleColor)
            .foregroundStyle(textColor)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            if message.role != .user { Spacer(minLength: 40) }
        }

    }

    /// 複製到 tmp 並保留原檔名(分享面板才不會轉圈)
    static func copyToTemp(path: String, name: String) -> URL? {
        let src = URL(fileURLWithPath: path)
        let safe = name.replacingOccurrences(of: "/", with: "_")
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent(safe)
        try? FileManager.default.removeItem(at: dst)
        do { try FileManager.default.copyItem(at: src, to: dst); return dst } catch { return nil }
    }

    @ViewBuilder
    private func fileCard(path: String, name: String) -> some View {
        let url = URL(fileURLWithPath: path)
        HStack(spacing: 8) {
            Image(systemName: "doc.fill")
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(Theme.ui(13, .semibold)).lineLimit(1)
                Text(fileSize(path)).font(Theme.ui(10)).opacity(0.75)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.panel2.opacity(0.9))
        .foregroundStyle(Theme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { previewURL = url }
        .contextMenu {
            Button {
                if let tmp = MessageBubble.copyToTemp(path: path, name: name) {
                    onShare([tmp])
                }
            } label: {
                Label(L("分享"), systemImage: "square.and.arrow.up")
            }
            Button { previewURL = url } label: { Label(L("快速查看"), systemImage: "eye") }
            Button(role: .destructive) { onDeleteAttachment() } label: {
                Label(L("刪除檔案"), systemImage: "trash")
            }
        }
        .quickLookPreview($previewURL)
    }

    private func fileSize(_ path: String) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let bytes = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        if bytes >= 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        if bytes >= 1024 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        return "\(bytes) B"
    }

    static func tempImageURL(_ data: Data) -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let name = "ocpass-" + String(data.hashValue) + ".jpg"
        let url = dir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url)
        }
        return url
    }

    /// 隱藏 gateway 留下的媒體標記
    private var visibleText: String {
        message.text
            .replacingOccurrences(of: #"\[media attached: [^\]]*\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
