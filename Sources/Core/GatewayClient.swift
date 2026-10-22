import Foundation

/// OpenClaw Gateway WebSocket client（協議 v4 + ed25519 裝置身份）
final class GatewayClient {
    enum ClientError: LocalizedError {
        case notConnected, challengeTimeout, pairingRequired(String), server(String)
        var errorDescription: String? {
            switch self {
            case .notConnected: return "尚未連線"
            case .challengeTimeout: return "Gateway 沒有回應 challenge"
            case .pairingRequired(let id): return "需要配對核准:\(id)"
            case .server(let m): return m
            }
        }
    }

    private let identity = DeviceIdentity.loadOrCreate()
    private var task: URLSessionWebSocketTask?
    private var pending: [String: CheckedContinuation<Any?, Error>] = [:]
    private var challengeWaiter: CheckedContinuation<String, Error>?
    private var eventHandler: ((String, Any?) -> Void)?
    private(set) var isOpen = false
    var onDisconnect: (() -> Void)?

    func onEvent(_ h: @escaping (String, Any?) -> Void) { eventHandler = h }

    func connect(url: URL, token: String) async throws {
        let t = URLSession(configuration: .default).webSocketTask(with: url)
        task = t; t.resume(); isOpen = true
        receiveLoop()

        let nonce = try await waitForChallenge()
        let signedAt = Int64(Date().timeIntervalSince1970 * 1000)
        let clientId = "openclaw-ios", mode = "ui", role = "operator"
        let scopes = ["operator.admin"], platform = "ios", family = "phone"
        let payload = DeviceIdentity.payloadV3(deviceId: identity.deviceId, clientId: clientId,
                                              clientMode: mode, role: role, scopes: scopes,
                                              signedAt: signedAt, token: token, nonce: nonce,
                                              platform: platform, deviceFamily: family)
        guard let signature = identity.sign(payload) else { throw ClientError.server("簽章失敗") }

        let params: [String: Any] = [
            "minProtocol": 4, "maxProtocol": 4,
            "client": ["id": clientId, "displayName": "OC Pass", "version": "0.1.0",
                       "platform": platform, "deviceFamily": family, "mode": mode,
                       "instanceId": UUID().uuidString],
            "caps": [], "auth": ["token": token], "role": role, "scopes": scopes,
            "device": ["id": identity.deviceId, "publicKey": identity.publicKeyBase64URL,
                       "signature": signature, "signedAt": signedAt, "nonce": nonce]
        ]
        _ = try await request("connect", params)
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil; isOpen = false
        pending.values.forEach { $0.resume(throwing: ClientError.notConnected) }
        pending.removeAll()
    }

    func request(_ method: String, _ params: [String: Any] = [:]) async throws -> Any? {
        guard let task, isOpen else { throw ClientError.notConnected }
        let id = UUID().uuidString
        let data = try JSONSerialization.data(withJSONObject: ["type": "req", "id": id, "method": method, "params": params])
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            task.send(.data(data)) { err in
                if let err { self.finish(id, .failure(err)) }
            }
        }
    }


    // MARK: - High level API

    func listSessions(limit: Int = 50) async throws -> [GatewaySession] {
        let payload = try await request("sessions.list", ["limit": limit])
        let dict = payload as? [String: Any] ?? [:]
        let raw = (dict["sessions"] as? [[String: Any]]) ?? (dict["items"] as? [[String: Any]]) ?? []
        return raw.compactMap(GatewaySession.parse)
    }

    func history(sessionKey: String, limit: Int = 50) async throws -> [ChatMessage] {
        let payload = try await request("chat.history", ["sessionKey": sessionKey, "limit": limit])
        let dict = payload as? [String: Any] ?? [:]
        let raw = (dict["messages"] as? [[String: Any]]) ?? []
        return raw.compactMap { m in
            let role = (m["role"] as? String) ?? (m["type"] as? String) ?? "assistant"
            let text = (m["text"] as? String) ?? (m["content"] as? String) ?? ""
            guard !text.isEmpty else { return nil }
            return ChatMessage(role: role == "user" ? .user : (role == "system" ? .system : .assistant), text: text)
        }
    }

    @discardableResult
    func send(sessionKey: String, message: String) async throws -> SendResult {
        let payload = try await request("chat.send", [
            "sessionKey": sessionKey,
            "message": message,
            "idempotencyKey": UUID().uuidString
        ])
        let dict = payload as? [String: Any] ?? [:]
        return SendResult(runId: dict["runId"] as? String ?? "")
    }

    // MARK: - internals

    private func finish(_ id: String, _ result: Result<Any?, Error>) {
        guard let c = pending.removeValue(forKey: id) else { return }
        switch result {
        case .success(let v): c.resume(returning: v)
        case .failure(let e): c.resume(throwing: e)
        }
    }

    private func waitForChallenge() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            challengeWaiter = cont
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self, let c = self.challengeWaiter else { return }
                self.challengeWaiter = nil
                c.resume(throwing: ClientError.challengeTimeout)
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                let wasOpen = self.isOpen
                self.isOpen = false
                self.pending.values.forEach { $0.resume(throwing: err) }
                self.pending.removeAll()
                if wasOpen { self.onDisconnect?() }
            case .success(let message):
                self.handle(message)
                self.receiveLoop()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .data(let d): data = d
        case .string(let s): data = s.data(using: .utf8)
        @unknown default: data = nil
        }
        guard let data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        if type == "event" {
            let name = obj["event"] as? String ?? ""
            if name == "connect.challenge",
               let payload = obj["payload"] as? [String: Any],
               let nonce = payload["nonce"] as? String,
               let waiter = challengeWaiter {
                challengeWaiter = nil
                waiter.resume(returning: nonce)
            } else {
                eventHandler?(name, obj["payload"])
            }
            return
        }

        if type == "res", let id = obj["id"] as? String {
            if obj["ok"] as? Bool == true {
                finish(id, .success(obj["payload"]))
            } else {
                let err = obj["error"] as? [String: Any] ?? [:]
                let details = err["details"] as? [String: Any] ?? [:]
                if let requestId = details["requestId"] as? String {
                    finish(id, .failure(ClientError.pairingRequired(requestId)))
                } else {
                    finish(id, .failure(ClientError.server(err["message"] as? String ?? "request failed")))
                }
            }
        }
    }
}
