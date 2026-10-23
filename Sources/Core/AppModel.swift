import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var state: ConnectionState = .idle
    @Published var messages: [ChatMessage] = []
    @Published var sessions: [GatewaySession] = []
    @Published var currentSession: GatewaySession?
    @Published var showScanner = false
    @Published var showSettings = false
    @Published var showSessions = false
    @Published var isDemo = false
    @Published var streaming = false
    /// 送出後到「真正拿到最終回覆」前都保持 true(三點一直閃)
    @Published var awaitingReply = false
    @Published var showConsole = false
    @Published var gatewayURL: URL?
    @Published var gatewayToken: TokenString = ""
    @Published var creatingSession = false
    @Published var showDashboard = false
    @Published var cronJobs: [GatewayCronJob] = []
    @Published var nodes: [GatewayNode] = []
    @Published var latencyMs: Double?
    @Published var dashboardLoading = false
    @Published var dashboardError: String?
    @Published var pendingApprovals: [PendingApproval] = []
    @Published var pairedDevices: [PairedDevice] = []
    @Published var availableModels: [String] = []
    @Published var actionError: String?
    @Published var sessionError: String?
    @Published var gatewayVersion: String = ""
    /// 使用者自己設定的名字(存在 UserDefaults),用來顯示「你是誰」而不是 Telegram 帳號
    @Published var languageRevision = 0
    @Published var userName: String = UserDefaults.standard.string(forKey: "ocpass.userName") ?? ""

    var displayName: String {
        if isDemo { return userName.isEmpty ? "Demo" : userName }
        if !userName.isEmpty { return userName }
        return currentSession?.title ?? "OC Pass"
    }

    /// 只寫入設定,不在同一次更新中改動畫面狀態(避免 SwiftUI view graph 崩潰)
    func setLanguage(_ value: String) {
        Language.current = value
    }

    func bumpLanguageRevision() {
        languageRevision += 1
    }

    func setUserName(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        userName = trimmed
        UserDefaults.standard.set(trimmed, forKey: "ocpass.userName")
    }

    var isConnected: Bool { if case .ready = state { return true }; return false }

    private let client = GatewayClient()
    private var currentGateway: Gateway?
    private var streamingMessageId: UUID?
    private var pollTask: Task<Void, Never>?

    private var reconnectAttempt = 0
    private var reconnecting = false
    private var heartbeatTask: Task<Void, Never>?

    init() {
        client.onEvent { [weak self] name, payload in
            Task { @MainActor in self?.handle(event: name, payload: payload) }
        }
        client.onDisconnect = { [weak self] in
            Task { @MainActor in self?.handleDrop() }
        }
    }

    /// 斷線 → 指數退避自動重連(1,2,4,8,15 秒上限),沿用原本的憑證(device token)
    private func handleDrop() {
        guard !reconnecting, gatewayURL != nil, !gatewayToken.isEmpty else { return }
        reconnecting = true
        state = .connecting
        Task {
            let delay = min(15.0, pow(2.0, Double(reconnectAttempt)))
            reconnectAttempt += 1
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            reconnecting = false
            if case .ready = state { return }
            openConnection()
        }
    }

    // MARK: - Connect

    private var authMode: AuthMode = .shared("")

    /// QR 內容支援三種:
    ///  - `oc-pair://<base64url JSON{url,bootstrapToken}>`(官方 setup code,一次性)
    ///  - `?url=wss://…&bootstrapToken=…`
    ///  - `?url=wss://…&token=***`(舊式,相容保留)
    func connect(pairingCode: String) {
        let raw = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.lowercased().hasPrefix("oc-pair://") {
            let payload = String(raw.dropFirst("oc-pair://".count))
            if let (url, boot) = Self.decodeSetupCode(payload) {
                connectBootstrap(url: url, bootstrapToken: boot)
            } else {
                state = .failed("配對碼無法解析")
            }
            return
        }
        guard let comps = URLComponents(string: raw) else {
            state = .failed("QR 內容無法解析"); return
        }
        let items = comps.queryItems ?? []
        let urlStr = items.first(where: { $0.name == "url" })?.value
        let boot = items.first(where: { $0.name == "bootstrapToken" })?.value
        let tok = items.first(where: { $0.name == "token" })?.value
        guard let urlStr, let url = URL(string: urlStr) else {
            state = .failed("QR 內容無法解析"); return
        }
        if let boot, !boot.isEmpty { connectBootstrap(url: url, bootstrapToken: boot); return }
        guard let tok, !tok.isEmpty else { state = .failed("QR 內容無法解析"); return }
        connect(url: url, token: tok)
    }

    /// setup code = base64url(JSON{url,bootstrapToken,…})
    static func decodeSetupCode(_ raw: String) -> (URL, TokenString)? {
        var s = raw
        while s.hasPrefix("/") { s.removeFirst() }
        guard let data = base64URLDecode(s),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlStr = obj["url"] as? String, let url = URL(string: urlStr),
              let boot = obj["bootstrapToken"] as? String, !boot.isEmpty else { return nil }
        return (url, boot)
    }

    static func base64URLDecode(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    /// 手動輸入 / 舊式 QR:共用 gateway token
    func connect(url: URL, token: TokenString) {
        gatewayURL = url
        gatewayToken = token
        authMode = .shared(token)
        CredentialStore.save(url: url, token: token, kind: "shared")
        openConnection()
    }

    /// 官方 setup code:用一次性 bootstrap token 換裝置 token
    private func connectBootstrap(url: URL, bootstrapToken: TokenString) {
        state = .connecting
        Task {
            do {
                state = .authenticating
                let hello = try await client.connect(url: url, auth: .bootstrap(bootstrapToken))
                guard let op = hello.operatorToken ?? hello.deviceToken, !op.isEmpty else {
                    state = .failed("配對完成但沒拿到裝置憑證"); return
                }
                client.disconnect()
                gatewayURL = url
                gatewayToken = op
                authMode = .device(op)
                CredentialStore.save(url: url, token: op, kind: "device")
                openConnection()
            } catch GatewayClient.ClientError.pairingRequired(let id) {
                state = .pairing(id)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func openConnection() {
        guard let url = gatewayURL, !gatewayToken.isEmpty else { return }
        state = .connecting
        let mode = authMode
        Task {
            do {
                state = .authenticating
                let hello = try await client.connect(url: url, auth: mode)
                if case .device = mode, let dt = hello.deviceToken, !dt.isEmpty, dt != gatewayToken {
                    gatewayToken = dt
                    CredentialStore.save(url: url, token: dt, kind: "device")
                }
                currentGateway = Gateway(name: url.host ?? "gateway", url: url, lastSeen: Date())
                if let v = hello.serverVersion, !v.isEmpty { gatewayVersion = v }
                reconnectAttempt = 0
                state = .ready
                startHeartbeat()
                await refreshSessions()
                if let cur = currentSession { select(cur) }
            } catch GatewayClient.ClientError.pairingRequired(let id) {
                state = .pairing(id)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// App 啟動時自動連線(憑證存在 Keychain)
    func autoConnect() {
        guard case .idle = state, !isDemo else { return }
        guard let stored = CredentialStore.load() else { return }
        gatewayURL = stored.url
        gatewayToken = stored.token
        authMode = (stored.kind == "device") ? .device(stored.token) : .shared(stored.token)
        openConnection()
    }

    /// 每 25 秒 ping 一次;連線已經死掉但 socket 沒觸發 error 時,由這裡發現並重連
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if case .ready = self.state {
                    do {
                        try await self.client.ping()
                    } catch {
                        await MainActor.run { self.handleDrop() }
                        return
                    }
                }
            }
        }
    }

    func appDidBecomeActive() {
        guard gatewayURL != nil, !isDemo else { return }
        if case .ready = state { Task { try? await client.ping() } }
    }

    /// 只斷線,不清掉本機對話紀錄(下次連回來還在)
    func disconnect() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        client.disconnect()
        state = .idle
    }

    /// 移除這台裝置的憑證(設定頁的「登出」)
    func forgetDevice() {
        disconnect()
        CredentialStore.clear()
        gatewayURL = nil
        gatewayToken = ""
        currentSession = nil
        sessions = []
        messages = []
        isDemo = false
    }

    /// Telegram 風格:一段回覆裡只留最後一個助理訊息(中間的工具/旁白不顯示)
    private func collapsed(_ list: [ChatMessage]) -> [ChatMessage] {
        var out: [ChatMessage] = []
        var buffer: [ChatMessage] = []
        func flush() {
            if let last = buffer.last { out.append(last) }
            buffer = []
        }
        for m in list {
            if m.isHidden {
                // 工具產物:前面的助理訊息是「中間過程」→ 丟掉,不讓它變成最終答案
                buffer = []
                continue
            }
            if m.role == .assistant {
                if m.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                buffer.append(m)
            } else {
                flush()
                out.append(m)
            }
        }
        flush()
        return out
    }

    private func saveTranscript() {
        guard let key = currentSession?.id, !key.isEmpty else { return }
        TranscriptCache.save(messages, for: key)
    }

    // MARK: - Sessions

    func refreshSessions() async {
        do {
            let list = try await client.listSessions()
            sessions = list
            sessionError = nil
            if currentSession == nil, let first = list.first { select(first) }
        } catch {
            sessionError = error.localizedDescription
            if case .ready = state { state = .failed(error.localizedDescription) }
        }
    }

    func createSession() {
        guard !creatingSession else { return }
        creatingSession = true
        sessionError = nil
        Task {
            do {
                let s = try await client.createSession()
                await refreshSessions()
                select(sessions.first(where: { $0.id == s.id }) ?? s)
            } catch {
                sessionError = error.localizedDescription
            }
            creatingSession = false
        }
    }

    func select(_ session: GatewaySession) {
        currentSession = session
        let cached = TranscriptCache.load(for: session.id)
        messages = cached          // 先顯示本機快取(斷線也看得到)
        Task {
            do {
                let history = try await client.history(sessionKey: session.id)
                if !history.isEmpty, history.count >= cached.count {
                    messages = collapsed(history)
                    saveTranscript()
                }
            } catch {
                if cached.isEmpty {
                    messages = [ChatMessage(role: .system, text: "讀取歷史失敗:\(error.localizedDescription)")]
                }
            }
        }
    }

    // MARK: - Chat

    func send(_ text: String, attachments: [PendingAttachment] = []) {
        Task { try? await sendAsync(text, attachments: attachments) }
    }

    /// 送出;失敗時把使用者訊息收回、並把錯誤往上拋(讓 App 還原草稿)
    func sendAsync(_ text: String, attachments: [PendingAttachment]) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(trimmed.isEmpty && attachments.isEmpty), let session = currentSession else { return }
        let shown = trimmed.isEmpty ? (attachments.count == 1 ? "[附件] \(attachments[0].name)" : "[附件] \(attachments.count) 個檔案") : trimmed
        var userMessage = ChatMessage(role: .user, text: shown)
        if let img = attachments.first(where: { $0.isImage })?.data {
            userMessage.imageData = img
        }
        messages.append(userMessage)
        saveTranscript()
        streaming = true
        awaitingReply = true      // 三點持續閃到真正拿到最終回覆
        streamingMessageId = nil

        do {
            let res = try await client.send(sessionKey: session.id, message: trimmed, attachments: attachments)
            startRunWatch(sessionKey: session.id, runId: res.runId)
        } catch {
            streaming = false
            awaitingReply = false
            if let i = messages.firstIndex(where: { $0.id == userMessage.id }) { messages.remove(at: i) }
            saveTranscript()
            throw error
        }
    }

    /// 等這輪真的結束(不再有 active run)才收掉三點、換上最終回覆。
    /// 有 hasActiveRun 就用它;沒有就退回「回覆文字穩定」的判斷。
    private func startRunWatch(sessionKey: String, runId: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            var idleTicks = 0
            var lastLen = -1
            var stableTicks = 0
            var sawActive = false

            for _ in 0..<120 {                  // 最多約 3 分鐘
                try? await Task.sleep(nanoseconds: 600_000_000)
                if Task.isCancelled { return }

                if let row = try? await self.client.sessionRow(key: sessionKey) {
                    if row.hasActiveRun || row.activeRunIds.contains(runId) {
                        sawActive = true
                        idleTicks = 0
                    } else {
                        idleTicks += 1
                    }
                    if sawActive && idleTicks >= 1 { await self.finishRun(sessionKey); return }
                }

                // 後備:只有在「最後一則是助理訊息」且內容長度穩定時才算完成
                if let h = try? await self.client.history(sessionKey: sessionKey), !h.isEmpty {
                    let visible = self.collapsed(h)
                    let len = visible.reduce(0) { $0 + $1.text.count }
                    let endsWithAssistant = visible.last?.role == .assistant
                    if endsWithAssistant && len == lastLen && len > 0 { stableTicks += 1 } else { stableTicks = 0 }
                    lastLen = len
                    if stableTicks >= 2 { await self.finishRun(sessionKey); return }
                }
            }
            await self.finishRun(sessionKey)
        }
    }

    /// 收到 sessions.changed 時立刻檢查:若已無 active run,馬上收三點、換上結果
    private func finishRunIfIdle(_ sessionKey: String) async {
        guard awaitingReply else { return }
        guard let row = try? await client.sessionRow(key: sessionKey) else { return }
        if !row.hasActiveRun && row.activeRunIds.isEmpty {
            await finishRun(sessionKey)
        }
    }

    private func finishRun(_ sessionKey: String) async {
        // 執行結束 ≠ 回覆已寫進歷史:這裡要等到「最後一則是助理訊息」才收三點,
        // 否則會出現「下一題送出時,上一題答案才跳出來」。
        for _ in 0..<120 {                      // 最多約 60 秒(答案沒到就一直閃)
            if let h = try? await client.history(sessionKey: sessionKey), !h.isEmpty {
                let c = collapsed(h)
                if c.last?.role == .assistant {
                    messages = c
                    saveTranscript()
                    streaming = false
                    awaitingReply = false
                    return
                }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        if let h = try? await client.history(sessionKey: sessionKey), !h.isEmpty {
            messages = collapsed(h)
            saveTranscript()
        }
        streaming = false
        awaitingReply = false
    }

    // MARK: - Event stream

    private func handle(event: String, payload: Any?) {
        if event == "sessions.changed" {
            if let key = currentSession?.id {
                Task { await self.finishRunIfIdle(key) }
            }
            return
        }
        guard let dict = payload as? [String: Any] else { return }
        let stream = dict["stream"] as? String ?? ""
        let data = dict["data"] as? [String: Any] ?? [:]

        // 像 Telegram 一樣:過程中的文字不顯示,只留「思考中」動畫,答案在完成後一次顯示
        if event == "agent", stream == "assistant" || stream == "message" || stream == "completion" {
            return
        }
        // 執行結束
        if event == "agent", stream == "lifecycle" {
            let phase = data["phase"] as? String ?? ""
            if phase == "completed" || phase == "failed" || phase == "cancelled" {
                streaming = false
                awaitingReply = false
                streamingMessageId = nil
                if let key = currentSession?.id {
                    Task {
                        if let h = try? await client.history(sessionKey: key), !h.isEmpty {
                            messages = collapsed(h)
                            saveTranscript()
                        }
                    }
                }
            }
        }
    }

    private func appendAssistant(_ chunk: String) {
        if let id = streamingMessageId, let i = messages.firstIndex(where: { $0.id == id }) {
            messages[i].text += chunk
            messages[i].pending = false
        } else {
            var msg = ChatMessage(role: .assistant, text: chunk)
            msg.pending = false
            streamingMessageId = msg.id
            messages.append(msg)
        }
    }

    // MARK: - Dashboard

    func loadDashboard() async {
        guard isConnected else { return }
        dashboardLoading = true
        dashboardError = nil
        async let ping = client.pingLatency()
        async let jobs = client.cronJobs()
        async let nodeList = client.nodes()
        async let sessionList = client.listSessions()
        async let pairs = client.devicePairs()
        async let modelList = client.availableModels()

        latencyMs = await ping
        cronJobs = (try? await jobs) ?? []
        nodes = (try? await nodeList) ?? []

        if let s = try? await sessionList { sessions = s } else { dashboardError = "讀取會話失敗" }
        if let p = try? await pairs { pendingApprovals = p.pending; pairedDevices = p.approved }
        if let m = try? await modelList, !m.isEmpty, availableModels.isEmpty { availableModels = m }

        dashboardLoading = false
    }

    func runJob(_ job: GatewayCronJob) {
        Task {
            try? await client.cronRun(jobId: job.id)
            await loadDashboard()
        }
    }

    var totalTokens: Int { sessions.reduce(0) { $0 + $1.totalTokens } }

    // MARK: - Dashboard actions

    func toggleJob(_ job: GatewayCronJob) {
        Task {
            try? await client.setJobEnabled(jobId: job.id, enabled: !job.enabled)
            await loadDashboard()
        }
    }

    func approve(_ approval: PendingApproval) {
        Task {
            try? await client.approveDevice(requestId: approval.id)
            await loadDashboard()
        }
    }

    func reject(_ approval: PendingApproval) {
        Task {
            try? await client.rejectDevice(requestId: approval.id)
            await loadDashboard()
        }
    }

    func remove(_ device: PairedDevice) {
        Task {
            try? await client.removeDevice(deviceId: device.id)
            await loadDashboard()
        }
    }

    func setModel(_ model: String) {
        guard let key = currentSession?.id else {
            actionError = "沒有選取會話"; return
        }
        Task {
            do {
                try await client.patchSessionModel(sessionKey: key, model: model)
                actionError = nil
                await loadDashboard()
            } catch {
                let msg = error.localizedDescription
                actionError = "切換模型失敗:" + msg
                // 這個模型不被允許 → 從清單移除,避免再選到
                if msg.lowercased().contains("not allowed") {
                    availableModels.removeAll { $0 == model || model.hasSuffix($0) || $0.hasSuffix(model) }
                }
            }
        }
    }

    // MARK: - Demo

    func exitDemo() {
        isDemo = false
        state = .idle
        messages = []
        sessions = []
        currentSession = nil
        streaming = false
        streamingMessageId = nil
    }

    func startDemo() {
        isDemo = true
        state = .ready
        sessions = [GatewaySession(id: "demo", sessionId: "demo", title: "Demo session", updatedAt: Date(), unread: 0, totalTokens: 0, hasActiveRun: false, activeRunIds: [], model: nil)]
        currentSession = sessions.first
        messages = DemoData.messages
    }
}
