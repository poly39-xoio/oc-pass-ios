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
    @Published var sessionError: String?
    /// 使用者自己設定的名字(存在 UserDefaults),用來顯示「你是誰」而不是 Telegram 帳號
    @Published var userName: String = UserDefaults.standard.string(forKey: "ocpass.userName") ?? ""

    var displayName: String {
        if isDemo { return userName.isEmpty ? "Demo" : userName }
        if !userName.isEmpty { return userName }
        return currentSession?.title ?? "OC Pass"
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

    /// 斷線 → 指數退避自動重連(1,2,4,8,15 秒上限)
    private func handleDrop() {
        guard !reconnecting else { return }
        guard let url = gatewayURL else { return }
        let tok = gatewayToken
        guard !tok.isEmpty else { return }
        reconnecting = true
        state = .connecting
        Task {
            let delay = min(15.0, pow(2.0, Double(reconnectAttempt)))
            reconnectAttempt += 1
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            reconnecting = false
            if case .ready = state { return }
            connect(url: url, token: tok)
        }
    }

    // MARK: - Connect

    func connect(pairingCode: String) {
        guard let comps = URLComponents(string: pairingCode) else {
            state = .failed("QR 內容無法解析"); return
        }
        let urlStr = comps.queryItems?.first(where: { $0.name == "url" })?.value
        let tokenValue = comps.queryItems?.first(where: { $0.name == "token" })?.value
        guard let urlStr, let url = URL(string: urlStr), let tokenValue else {
            state = .failed("QR 內容無法解析"); return
        }
        connect(url: url, token: tokenValue)
    }

    func connect(url: URL, token: TokenString) {
        state = .connecting
        gatewayURL = url
        gatewayToken = token
        Task {
            do {
                state = .authenticating
                try await client.connect(url: url, token: token)
                currentGateway = Gateway(name: url.host ?? "gateway", url: url, lastSeen: Date())
                reconnectAttempt = 0
                state = .ready
                startHeartbeat()
                await refreshSessions()
            } catch GatewayClient.ClientError.pairingRequired(let id) {
                state = .pairing(id)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
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

    func disconnect() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        client.disconnect()
        state = .idle
        messages = []
        sessions = []
        currentSession = nil
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
        messages = []
        Task {
            do {
                let history = try await client.history(sessionKey: session.id)
                messages = history
            } catch {
                messages = [ChatMessage(role: .system, text: "讀取歷史失敗:\(error.localizedDescription)")]
            }
        }
    }

    // MARK: - Chat

    func send(_ text: String, attachments: [PendingAttachment] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(trimmed.isEmpty && attachments.isEmpty), let session = currentSession else { return }
        let shown = trimmed.isEmpty ? (attachments.count == 1 ? "[附件] \(attachments[0].name)" : "[附件] \(attachments.count) 個檔案") : trimmed
        messages.append(ChatMessage(role: .user, text: shown))
        streaming = true
        var assistant = ChatMessage(role: .assistant, text: "", pending: true)
        streamingMessageId = assistant.id
        messages.append(assistant)

        Task {
            do {
                _ = try await client.send(sessionKey: session.id, message: trimmed, attachments: attachments)
                startHistoryPolling(sessionKey: session.id)
            } catch {
                streaming = false
                streamingMessageId = nil
                if let i = messages.firstIndex(where: { $0.id == assistant.id }) {
                    messages[i].pending = false
                    messages[i].text = "送出失敗:\(error.localizedDescription)"
                }
            }
        }
    }

    /// 送出後每 1.5 秒抓一次歷史,直到看到助理回覆(最長 90 秒)
    private func startHistoryPolling(sessionKey: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if Task.isCancelled { return }
                if let h = try? await self.client.history(sessionKey: sessionKey), !h.isEmpty {
                    let hasAssistant = h.last?.role == .assistant
                    await MainActor.run {
                        if h.count >= self.messages.count || hasAssistant {
                            self.messages = h
                        }
                        if hasAssistant { self.streaming = false }
                    }
                    if hasAssistant {
                        await MainActor.run { self.streaming = false }
                        return
                    }
                }
            }
            await MainActor.run { self.streaming = false }
        }
    }

    // MARK: - Event stream

    private func handle(event: String, payload: Any?) {
        guard let dict = payload as? [String: Any] else { return }
        let stream = dict["stream"] as? String ?? ""
        let data = dict["data"] as? [String: Any] ?? [:]

        // 助手文字(逐步)
        if event == "agent", stream == "assistant" || stream == "message" || stream == "completion" {
            let chunk = (data["delta"] as? String) ?? (data["text"] as? String) ?? ""
            guard !chunk.isEmpty else { return }
            appendAssistant(chunk)
            return
        }
        // 執行結束
        if event == "agent", stream == "lifecycle" {
            let phase = data["phase"] as? String ?? ""
            if phase == "completed" || phase == "failed" || phase == "cancelled" {
                streaming = false
                if let id = streamingMessageId, let i = messages.firstIndex(where: { $0.id == id }) {
                    messages[i].pending = false
                }
                streamingMessageId = nil
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
        latencyMs = await client.pingLatency()
        do {
            cronJobs = try await client.cronJobs()
        } catch {
            cronJobs = []
        }
        do {
            nodes = try await client.nodes()
        } catch {
            nodes = []
        }
        do {
            sessions = try await client.listSessions()
        } catch {
            dashboardError = error.localizedDescription
        }
        dashboardLoading = false
    }

    func runJob(_ job: GatewayCronJob) {
        Task {
            try? await client.cronRun(jobId: job.id)
            await loadDashboard()
        }
    }

    var totalTokens: Int { sessions.reduce(0) { $0 + $1.totalTokens } }

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
        sessions = [GatewaySession(id: "demo", sessionId: "demo", title: "Demo session", updatedAt: Date(), unread: 0, totalTokens: 0)]
        currentSession = sessions.first
        messages = DemoData.messages
    }
}
