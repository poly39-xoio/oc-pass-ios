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

    var isConnected: Bool { if case .ready = state { return true }; return false }

    private let client = GatewayClient()
    private var currentGateway: Gateway?
    private var streamingMessageId: UUID?
    private var pollTask: Task<Void, Never>?

    init() {
        client.onEvent { [weak self] name, payload in
            Task { @MainActor in self?.handle(event: name, payload: payload) }
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
        Task {
            do {
                state = .authenticating
                try await client.connect(url: url, token: token)
                currentGateway = Gateway(name: url.host ?? "gateway", url: url, lastSeen: Date())
                state = .ready
                await refreshSessions()
            } catch GatewayClient.ClientError.pairingRequired(let id) {
                state = .pairing(id)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func disconnect() {
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
            if currentSession == nil, let first = list.first { select(first) }
        } catch {
            state = .failed(error.localizedDescription)
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

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let session = currentSession else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))
        streaming = true
        var assistant = ChatMessage(role: .assistant, text: "", pending: true)
        streamingMessageId = assistant.id
        messages.append(assistant)

        Task {
            do {
                _ = try await client.send(sessionKey: session.id, message: trimmed)
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
        _ = assistant
        assistant.text = ""
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
        sessions = [GatewaySession(id: "demo", sessionId: "demo", title: "Demo session", updatedAt: Date(), unread: 0)]
        currentSession = sessions.first
        messages = DemoData.messages
    }
}
