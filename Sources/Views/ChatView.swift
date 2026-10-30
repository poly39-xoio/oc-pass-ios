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
    @State private var attachChoice: AttachChoice?
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var sizeWarning: String?
    @StateObject private var speech = SpeechInput()
    @State private var dictationBase = ""
    @State private var scrollTask: Task<Void, Never>?
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var zoomImage: UIImage?

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
        .overlay {
            if showAttachMenu {
                attachOverlay
            }
        }
        .fullScreenCover(isPresented: Binding(get: { zoomImage != nil }, set: { if !$0 { zoomImage = nil } })) {
            if let img = zoomImage { ZoomViewer(image: img) }
        }
        .alert(L("太大"), isPresented: Binding(get: { sizeWarning != nil || speech.error != nil }, set: { if !$0 { sizeWarning = nil; speech.error = nil } })) {
            Button(L("完成")) { sizeWarning = nil }
        } message: {
            Text(sizeWarning ?? speech.error ?? "")
        }
        .onAppear {
            restoreDraft()
            Task { await Store.shared.refreshEntitlement() }
        }
        .onChange(of: model.currentSession?.id) { _, _ in restoreDraft() }
        .onChange(of: draft) { _, v in scheduleDraftSave(v) }
        .onChange(of: showAttachMenu) { _, open in
            if !open { openPendingPicker() }
        }
        .onChange(of: speech.transcript) { _, t in
            guard speech.isRecording, !t.isEmpty else { return }
            draft = dictationBase.isEmpty ? t : dictationBase + " " + t
        }
    }

    /// 滾到底:合併多次觸發、只滾一次(先動畫、再一次無動畫校正)。
    /// 先前每次觸發都重試 4 次,送出訊息時 5 個事件同時觸發 → 畫面連續跳動。
    private func scrollToBottom(_ proxy: ScrollViewProxy, delay: Double, anchor: String = "bottom-anchor") {
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(delay, 0) * 1_000_000_000))
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.22)) { proxy.scrollTo(anchor, anchor: .bottom) }
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { proxy.scrollTo(anchor, anchor: .bottom) }
            // LazyVStack 的列高度是延遲計算的:送出後 content 高度會再變一次,
            // 只捲兩次會在第二次佈局後「跳掉」。再補一次(無動畫)把它鎖回底部。
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            var t2 = Transaction()
            t2.disablesAnimations = true
            withTransaction(t2) { proxy.scrollTo(anchor, anchor: .bottom) }
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
        // 不要在主執行緒做磁碟 I/O:手寫輸入每個字都會觸發,舊版同步寫兩個 key 會卡住鍵盤
        let key = draftKey
        DispatchQueue.global(qos: .utility).async {
            let d = UserDefaults.standard
            if value.isEmpty {
                d.removeObject(forKey: key)
                d.removeObject(forKey: "ocpass.draft.last")
            } else {
                d.set(value, forKey: key)
                d.set(value, forKey: "ocpass.draft.last")
            }
        }
    }

    /// 草稿寫入去抖:停止輸入 0.7 秒後才寫(送出/離開頁面會立即寫)
    private func scheduleDraftSave(_ value: String) {
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            persistDraft(value)
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
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Button {
                    model.exitDemo()
                } label: {
                    Text(L("退出"))
                        .font(Theme.ui(12, .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 56, height: 30)
                        .background(Theme.panel2)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
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

    private static let bisectPlain = false

    private var messageList: some View {
        if Self.bisectPlain {
            return AnyView(ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.messages.filter { !$0.isHidden }) { m in
                        Text(m.text.isEmpty ? L("（圖片）") : m.text)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            })
        }
        return AnyView(ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.messages.filter { !$0.isHidden }) { m in
                        MessageBubble(
                            message: m,
                            onShare: { items in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { presentShare(items) }
                            },
                            onDelete: { model.deleteMessage(m) },
                            onDeleteAttachment: { model.deleteAttachment(of: m) },
                            onZoom: { zoomImage = $0 }
                        )
                        .id(m.id)
                    }
                    if model.awaitingReply {
                        HStack { TypingBubble(since: model.workingSince); Spacer(minLength: 40) }
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
            .onChange(of: model.streaming) { _, _ in scrollToBottom(proxy, delay: 0.02) }
            .onChange(of: pending.isEmpty) { _, _ in scrollToBottom(proxy, delay: 0.02) }
            .onChange(of: model.awaitingReply) { _, typing in
                if typing { scrollToBottom(proxy, delay: 0.05, anchor: "typing-indicator") }
            }
        })
    }

    // MARK: - Attachment chips

    @ViewBuilder
    private var attachmentChips: some View {
        if !pending.isEmpty {
            VStack(alignment: .trailing, spacing: 6) {
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
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    /// 附件選單浮層:半寬小卡 + 點空白處關閉
    private var attachOverlay: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.opacity(0.15)
                .ignoresSafeArea()
                .onTapGesture { showAttachMenu = false }

            AttachMenuCard(
                onPhoto: { attachChoice = .photo; showAttachMenu = false },
                onFile: { attachChoice = .file; showAttachMenu = false }
            )
            .frame(width: max(160, UIScreen.main.bounds.width / 2 - 12))
            .padding(.trailing, 12)
            .padding(.bottom, 88)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
        }
        .transition(.opacity)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { showAttachMenu = true }
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
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 6, matching: .images)
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): urls.forEach(loadFile)
            case .failure: break
            }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var added: [PendingAttachment] = []
                let multi = items.count > 1
                let maxB = multi ? 500_000 : 700_000
                let maxD: CGFloat = multi ? 1000 : 1200
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let att = await Task.detached { () -> PendingAttachment? in
                            autoreleasepool { Self.makeImageAttachment(data, maxBytes: maxB, maxDim: maxD) }
                        }.value
                        if let att { added.append(att) } else { await MainActor.run { sizeWarning = L("無法讀取這個檔案") } }
                    }
                }
                await MainActor.run {
                    pending.append(contentsOf: added)
                    photoItems = []
                    let total = pending.reduce(0) { $0 + $1.data.count }
                    if total > 24 * 1024 * 1024 {
                        sizeWarning = L("附件總量超過 24 MB，請減少張數")
                        while pending.reduce(0, { $0 + $1.data.count }) > 24 * 1024 * 1024, !pending.isEmpty {
                            pending.removeLast()
                        }
                    }
                }
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
    static func makeImageAttachment(_ data: Data, maxBytes: Int = 6 * 1024 * 1024, maxDim: CGFloat = 2048) -> PendingAttachment? {
        // 用 ImageIO 直接產生縮圖,不要先解整張原圖(48MP 原圖會瞬間吃掉 200MB)
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDim
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = UIImage(cgImage: cg)
        let limit = maxBytes
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
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 34, height: 22)
            }
            .accessibilityLabel(L("連線"))
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
    /// 選單關掉之後才開相簿/檔案,避免兩個 presentation 撞在一起
    private func openPendingPicker() {
        guard let choice = attachChoice else { return }
        attachChoice = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            switch choice {
            case .photo: showPhotoPicker = true
            case .file: showFileImporter = true
            }
        }
    }
}

enum AttachChoice { case photo, file }

/// 附加檔案選單:浮在輸入框上方的小卡,寬度 = 螢幕一半
struct AttachMenuCard: View {
    var onPhoto: () -> Void
    var onFile: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            row(title: L("照片"), action: onPhoto)
            row(title: L("檔案"), action: onFile)
        }
        .padding(8)
        .background(Theme.bgSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
    }

    private func row(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.ui(15, .medium))
                .lineLimit(1)
            .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 思考中的循環動畫(三個點)
struct TypingBubble: View {
    /// When the current run started, so a long task shows elapsed time instead of
    /// a silent animation that looks idle after a few seconds.
    var since: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let elapsed = since.map { ctx.date.timeIntervalSince($0) } ?? 0
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        let wave = 0.35 + 0.65 * max(0, sin(t * 3.2 - Double(i) * 0.7))
                        Circle().fill(Theme.ink.opacity(wave)).frame(width: 7, height: 7)
                    }
                }
                if let since, elapsed >= 2 {
                    Text(L("工作中") + " " + Self.mmss(elapsed))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink.opacity(0.55))
                        .monospacedDigit()
                        .id(Int(elapsed))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private static func mmss(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        if m >= 60 { return String(format: "%d:%02d:%02d", m / 60, m % 60, s) }
        return String(format: "%d:%02d", m, s)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var onShare: ([Any]) -> Void = { _ in }
    var onDelete: () -> Void = {}
    var onDeleteAttachment: () -> Void = {}
    var onZoom: (UIImage) -> Void = { _ in }
    @State private var previewURL: URL?

    private var mediaOnly: Bool {
        let has = message.imageData != nil || (message.imageDatas?.isEmpty == false) || (message.imagePaths?.isEmpty == false)
        let t = visibleText
        let placeholderOnly = t.isEmpty || (t.hasPrefix("[附件]") && !t.contains("\n"))
        return has && placeholderOnly && message.attachmentPath == nil
    }

    private static let imgCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 20
        c.totalCostLimit = 48 * 1024 * 1024
        return c
    }()

    static func images(for m: ChatMessage) -> [UIImage] {
        var out: [UIImage] = []
        if let ds = m.imageDatas, !ds.isEmpty {
            for (i, d) in ds.enumerated() {
                let key = "\(m.id)-d\(i)" as NSString
                if let c = imgCache.object(forKey: key) { out.append(c); continue }
                if let ui = UIImage(data: d) { imgCache.setObject(ui, forKey: key, cost: d.count); out.append(ui) }
            }
            return out
        }
        if let d = m.imageData {
            let key = "\(m.id)-single" as NSString
            if let c = imgCache.object(forKey: key) { return [c] }
            if let ui = UIImage(data: d) { imgCache.setObject(ui, forKey: key, cost: d.count); return [ui] }
        }
        if let ps = m.imagePaths {
            for (i, path) in ps.enumerated() {
                let key = "\(m.id)-p\(i)" as NSString
                if let c = imgCache.object(forKey: key) { out.append(c); continue }
                if let ui = UIImage(contentsOfFile: path) { imgCache.setObject(ui, forKey: key, cost: 2 * 1024 * 1024); out.append(ui) }
            }
        }
        return out
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                let imgs: [UIImage] = Self.images(for: message)
                if imgs.count > 0 { bubbleImage(imgs[0]) }
                if imgs.count > 1 { bubbleImage(imgs[1]) }
                if imgs.count > 2 { bubbleImage(imgs[2]) }
                if imgs.count > 3 { bubbleImage(imgs[3]) }
                if imgs.count > 4 { bubbleImage(imgs[4]) }
                if imgs.count > 5 { bubbleImage(imgs[5]) }
                if let path = message.attachmentPath, FileManager.default.fileExists(atPath: path) {
                    fileCard(path: path, name: message.attachmentName ?? URL(fileURLWithPath: path).lastPathComponent)
                }
                if !displayText.isEmpty {
                    Text(Linkified.attributed(displayText))
                        .font(Theme.ui(15))
                        .tint(textColor)
                        .textSelection(.enabled)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = displayText
                            } label: {
                                Label(L("複製"), systemImage: "doc.on.doc")
                            }
                            Button {
                                onShare([displayText])
                            } label: {
                                Label(L("分享文字"), systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) { onDelete() } label: {
                                Label(L("刪除訊息"), systemImage: "trash")
                            }
                        }
                }
                if message.hasTimestamp != false, message.role != .system {
                    HStack {
                        Spacer(minLength: 0)
                        Text(Self.timeText(message.createdAt))
                            .font(.system(size: 10))
                            .foregroundStyle(textColor.opacity(0.55))
                    }
                }
            }
            .padding(.horizontal, mediaOnly ? 0 : 12)
            .padding(.vertical, mediaOnly ? 0 : 9)
            .background(mediaOnly ? Color.clear : bubbleColor)
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
    private func bubbleImage(_ ui: UIImage) -> some View {
        Image(uiImage: ui)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: mediaOnly ? 300 : 220, maxHeight: mediaOnly ? 400 : 260)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture { onZoom(ui) }
            .contextMenu {
                Button { UIPasteboard.general.image = ui } label: { Label(L("複製圖片"), systemImage: "doc.on.doc") }
                Button { onShare([ui]) } label: { Label(L("分享"), systemImage: "square.and.arrow.up") }
                Button(role: .destructive) { onDelete() } label: { Label(L("刪除照片"), systemImage: "trash") }
            }
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

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "j:mm", options: 0, locale: .current) ?? "HH:mm"
        return f
    }()

    private static func timeText(_ d: Date) -> String { timeFmt.string(from: d) }

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
        let cleaned = cappedText
        return cleaned
    }

    /// 英文模式把附件佔位符也翻掉(只影響顯示/複製,不動媒體判定)
    private var displayText: String {
        guard Language.isEnglish else { return visibleText }
        return visibleText
            .replacingOccurrences(of: "[附件] ", with: "[Attachment] ")
            .replacingOccurrences(of: " 個檔案", with: " files")
            .replacingOccurrences(of: "[附件]", with: "[Attachment]")
    }

    private var cappedText: String {
        let raw = message.text
            .replacingOccurrences(of: #"\[media attached: [^\]]*\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.count > 20000 ? String(raw.prefix(2000)) + L("\n…（內容過長，已省略）") : raw
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


/// 全螢幕看圖:雙指縮放 / 拖曳 / 雙擊放大
struct ZoomViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { v in scale = min(max(lastScale * v, 1), 5) }
                            .onEnded { _ in lastScale = scale; if scale <= 1 { offset = .zero; lastOffset = .zero } },
                        DragGesture()
                            .onChanged { v in
                                guard scale > 1 else { return }
                                offset = CGSize(width: lastOffset.width + v.translation.width,
                                                height: lastOffset.height + v.translation.height)
                            }
                            .onEnded { _ in lastOffset = offset }
                    )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if scale > 1 { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero }
                        else { scale = 2.5; lastScale = 2.5 }
                    }
                }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.55))
                    .clipShape(Circle())
            }
            .padding(.top, 18)
            .padding(.trailing, 18)
        }
    }
}
