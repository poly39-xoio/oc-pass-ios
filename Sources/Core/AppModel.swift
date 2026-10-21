import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var state: ConnectionState = .idle
    @Published var messages: [ChatMessage] = []
    @Published var sessions: [ChatSession] = []
    @Published var showScanner = false
    @Published var showSettings = false
    @Published var isDemo = false

    var isConnected: Bool {
        if case .ready = state { return true }
        return false
    }

    private let client = GatewayClient()
    private var currentGateway: Gateway?

    // MARK: - Connect

    func connect(pairingCode: String) {
        // pairingCode 格式: openclaw://pair?url=wss%3A%2F%2F...&token=...
        guard let comps = URLComponents(string: pairingCode),
              let urlStr = comps.queryItems?.first(where: { $0.name == "url" })?.value,
              let token = comps.queryItems?.first(where: { $0.name == "token" })?.value,
              let url = URL(string: urlStr) else {
            state = .failed("QR 內容無法解析")
            return
        }
        connect(url: url, token: token)
    }

    func connect(url: URL, token: String) {
        state = .connecting
        Task {
            do {
                state = .authenticating
                try await client.connect(url: url, token: token)
                await client.onEvent { [weak self] event, payload in
                    Task { @MainActor in self?.handle(event: event, payload: payload) }
                }
                currentGateway = Gateway(name: url.host ?? "gateway", url: url, lastSeen: Date())
                state = .ready
                await loadSessions()
            } catch GatewayClient.ClientError.pairingRequired(let id) {
                state = .pairing(id)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        Task { await client.disconnect() }
        state = .idle
        messages = []
    }

    // MARK: - Chat

    func send(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var msg = ChatMessage(role: .user, text: text)
        msg.pending = true
        messages.append(msg)
        Task {
            do {
                _ = try await client.request("chat.send", ["text": text])
                if let i = messages.firstIndex(where: { $0.id == msg.id }) { messages[i].pending = false }
            } catch {
                if let i = messages.firstIndex(where: { $0.id == msg.id }) { messages[i].pending = false }
                messages.append(ChatMessage(role: .system, text: "送出失敗:\(error.localizedDescription)"))
            }
        }
    }

    // MARK: - Demo

    func startDemo() {
        isDemo = true
        state = .ready
        sessions = [ChatSession(id: "demo", title: "Demo session", updatedAt: Date())]
        messages = DemoData.messages
    }

    private func loadSessions() async {
        // TODO: 依 gateway 實際 method 名稱調整
        sessions = []
    }

    private func handle(event: String, payload: Any?) {
        // TODO: 依事件類型更新 messages(session.message / run.progress ...)
    }
}
