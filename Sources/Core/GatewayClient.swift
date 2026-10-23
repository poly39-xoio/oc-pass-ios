import Foundation

/// 連線憑證的種類
enum AuthMode {
    case shared(TokenString)      // gateway 共用 token(手動輸入)
    case device(TokenString)      // 配對後拿到的裝置 token
    case bootstrap(TokenString)   // QR 的一次性 setup code

    var authParams: [String: Any] {
        switch self {
        case .shared(let t): return ["token": t]
        case .device(let t): return ["deviceToken": t]
        case .bootstrap(let t): return ["bootstrapToken": t]
        }
    }

    /// 簽章時放進 payload 的 token 欄位(與 gateway 的 resolveSignatureToken 一致)
    var signToken: TokenString {
        switch self {
        case .shared(let t), .device(let t), .bootstrap(let t): return t
        }
    }

    var role: String {
        switch self {
        case .bootstrap: return "node"
        default: return "operator"
        }
    }

    var scopes: [String] {
        switch self {
        case .bootstrap: return []
        case .shared: return ["operator.admin"]
        case .device: return ["operator.read", "operator.write"]
        }
    }
}

/// 配對握手回傳的憑證
struct HelloAuth {
    var deviceToken: TokenString?
    var operatorToken: TokenString?
    var role: String
    var scopes: [String]
    var serverVersion: String?
}

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
    /// 保護 pending / challengeWaiter / isOpen(多個 async 呼叫會同時進來)
    private let stateLock = NSLock()
    var onDisconnect: (() -> Void)?

    func onEvent(_ h: @escaping (String, Any?) -> Void) { eventHandler = h }

    func connect(url: URL, auth: AuthMode) async throws -> HelloAuth {
        let t = URLSession(configuration: .default).webSocketTask(with: url)
        task = t; t.resume()
        stateLock.lock(); isOpen = true; stateLock.unlock()
        receiveLoop()

        let nonce = try await waitForChallenge()
        let signedAt = Int64(Date().timeIntervalSince1970 * 1000)
        let clientId = "openclaw-ios", mode = "ui"
        let role = auth.role, scopes = auth.scopes
        let platform = "ios", family = "phone"
        let payload = DeviceIdentity.payloadV3(deviceId: identity.deviceId, clientId: clientId,
                                              clientMode: mode, role: role, scopes: scopes,
                                              signedAt: signedAt, token: auth.signToken, nonce: nonce,
                                              platform: platform, deviceFamily: family)
        guard let signature = identity.sign(payload) else { throw ClientError.server("簽章失敗") }

        let params: [String: Any] = [
            "minProtocol": 4, "maxProtocol": 4,
            "client": ["id": clientId, "displayName": "OC Pass", "version": "1.0",
                       "platform": platform, "deviceFamily": family, "mode": mode,
                       "instanceId": UUID().uuidString],
            "caps": [], "auth": auth.authParams, "role": role, "scopes": scopes,
            "device": ["id": identity.deviceId, "publicKey": identity.publicKeyBase64URL,
                       "signature": signature, "signedAt": signedAt, "nonce": nonce]
        ]
        let hello = try await request("connect", params)
        return Self.parseHello(hello)
    }

    /// 從 hello-ok 取出這台裝置的憑證
    static func parseHello(_ payload: Any?) -> HelloAuth {
        let dict = payload as? [String: Any] ?? [:]
        let auth = dict["auth"] as? [String: Any] ?? [:]
        let primary = auth["deviceToken"] as? String
        var operatorToken: TokenString?
        if let extra = auth["deviceTokens"] as? [[String: Any]] {
            for entry in extra {
                let role = entry["role"] as? String ?? ""
                if role == "operator", let tok = entry["deviceToken"] as? String, !tok.isEmpty {
                    operatorToken = tok
                    break
                }
            }
            if operatorToken == nil, let first = extra.first, let tok = first["deviceToken"] as? String {
                operatorToken = tok
            }
        }
        let server = dict["server"] as? [String: Any] ?? [:]
        return HelloAuth(deviceToken: primary,
                         operatorToken: operatorToken,
                         role: auth["role"] as? String ?? "operator",
                         scopes: auth["scopes"] as? [String] ?? [],
                         serverVersion: server["version"] as? String)
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        stateLock.lock()
        isOpen = false
        let waiting = pending.values
        pending.removeAll()
        stateLock.unlock()
        waiting.forEach { $0.resume(throwing: ClientError.notConnected) }
    }

    func request(_ method: String, _ params: [String: Any] = [:]) async throws -> Any? {
        guard let task, isOpen else { throw ClientError.notConnected }
        let id = UUID().uuidString
        let data = try JSONSerialization.data(withJSONObject: ["type": "req", "id": id, "method": method, "params": params])
        return try await withCheckedThrowingContinuation { cont in
            stateLock.lock()
            pending[id] = cont
            stateLock.unlock()
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

    func history(sessionKey: String, limit: Int = 80) async throws -> [ChatMessage] {
        let payload = try await request("chat.history", ["sessionKey": sessionKey, "limit": limit])
        let dict = payload as? [String: Any] ?? [:]
        let raw = (dict["messages"] as? [[String: Any]]) ?? []
        return raw.compactMap { Self.parseHistoryMessage($0) }
    }

    /// gateway 的 chat.history 每筆可能是 {role,text} 或 {role,content:[{type:"text",text:…}]},
    /// 也可能包一層 message。這裡全部容錯處理,避免助理回覆被漏掉。
    static func parseHistoryMessage(_ raw: [String: Any]) -> ChatMessage? {
        let m = (raw["message"] as? [String: Any]) ?? raw
        let roleRaw = (m["role"] as? String) ?? (m["type"] as? String) ?? "assistant"
        let lowered = roleRaw.lowercased()
        // 工具/執行結果不是給人看的內容 → 標成 hidden(只當分隔線用)
        if ["tool", "toolresult", "tool_result", "function", "function_result", "command", "exec", "developer"].contains(lowered) {
            return ChatMessage(role: .system, text: "tool", hidden: true)
        }
        let role: MessageRole = roleRaw == "user" ? .user : (roleRaw == "system" ? .system : .assistant)

        var text = ""
        if let s = m["text"] as? String { text = s }
        if text.isEmpty, let s = m["content"] as? String { text = s }
        if text.isEmpty, let blocks = m["content"] as? [[String: Any]] {
            let parts: [TokenString] = blocks.compactMap { b in
                let kind = b["type"] as? String ?? ""
                if kind == "text" || kind == "output_text" {
                    return (b["text"] as? String) ?? (b["content"] as? String)
                }
                return nil
            }
            text = parts.joined(separator: "\n")
        }
        if text.isEmpty, let b = m["content"] as? [String: Any], let s = b["text"] as? String {
            text = s
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 斷線重連偶爾會把 base64 區塊當訊息存進來:不要顯示
        guard !Self.looksLikeEncodedBlob(trimmed) else { return nil }
        return ChatMessage(role: role, text: trimmed)
    }

    /// 判斷是否為 base64/JSON 控制區塊(用於隱藏亂碼)
    static func looksLikeEncodedBlob(_ s: String) -> Bool {
        if s.hasPrefix("{\"sid\":") || s.hasPrefix("{\"relay\":") { return true }
        guard s.count >= 120, !s.contains(" "), !s.contains("\n") else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=_-")
        return s.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    @discardableResult
    func send(sessionKey: String, message: String, attachments: [PendingAttachment] = []) async throws -> SendResult {
        var params: [String: Any] = [
            "sessionKey": sessionKey,
            "message": message,
            "idempotencyKey": UUID().uuidString
        ]
        if !attachments.isEmpty {
            params["attachments"] = attachments.map { a -> [String: Any] in
                [
                    "type": a.isImage ? "image" : "file",
                    "mimeType": a.mimeType,
                    "fileName": a.name,
                    "content": a.data.base64EncodedString(),
                    "sizeBytes": a.data.count
                ]
            }
        }
        let payload = try await request("chat.send", params)
        let dict = payload as? [String: Any] ?? [:]
        return SendResult(runId: dict["runId"] as? String ?? "")
    }

    /// 建立新 session(使用者自己在 App 裡開新對話)
    func createSession(agentId: String = "main", displayName: String? = nil) async throws -> GatewaySession {
        var params: [String: Any] = ["agentId": agentId]
        if let displayName, !displayName.isEmpty { params["displayName"] = displayName }
        let payload = try await request("sessions.create", params)
        let dict = payload as? [String: Any] ?? [:]
        let inner = dict["session"] as? [String: Any] ?? dict
        if let s = GatewaySession.parse(inner) { return s }
        let key = (inner["key"] as? String) ?? (inner["sessionKey"] as? String) ?? ""
        guard !key.isEmpty else { throw ClientError.server("sessions.create 沒有回傳 session key") }
        return GatewaySession(id: key, sessionId: inner["sessionId"] as? String ?? key,
                              title: inner["displayName"] as? String ?? "新對話",
                              updatedAt: Date(), unread: 0, totalTokens: 0,
                              hasActiveRun: false, activeRunIds: [], model: nil)
    }

    /// WebSocket 層 ping,用來偵測「連線看起來還在、其實已經斷了」
    func ping() async throws {
        guard let task, isOpen else { throw ClientError.notConnected }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            task.sendPing { err in
                if let err { cont.resume(throwing: err) } else { cont.resume() }
            }
        }
    }

    // MARK: - Dashboard

    /// 量一次 ping 往返時間(毫秒)
    func pingLatency() async -> Double? {
        let start = Date()
        do {
            try await ping()
            return Date().timeIntervalSince(start) * 1000
        } catch {
            return nil
        }
    }

    /// 只問一個 session 的狀態(比 sessions.list 輕)
    func sessionRow(key: String) async throws -> GatewaySession? {
        let payload = try await request("sessions.describe", ["key": key])
        let dict = payload as? [String: Any] ?? [:]
        let inner = (dict["session"] as? [String: Any]) ?? dict
        return GatewaySession.parse(inner)
    }

    func cronJobs() async throws -> [GatewayCronJob] {
        let payload = try await request("cron.list", ["includeDisabled": true, "limit": 100])
        let dict = payload as? [String: Any] ?? [:]
        let raw = (dict["jobs"] as? [[String: Any]]) ?? (dict["items"] as? [[String: Any]]) ?? []
        return raw.compactMap(GatewayCronJob.parse)
    }

    func cronRun(jobId: String) async throws {
        _ = try await request("cron.run", ["id": jobId, "mode": "force"])
    }

    func nodes() async throws -> [GatewayNode] {
        let payload = try await request("node.list", [:])
        let dict = payload as? [String: Any] ?? [:]
        let raw = (dict["nodes"] as? [[String: Any]]) ?? (dict["items"] as? [[String: Any]]) ?? []
        return raw.compactMap(GatewayNode.parse)
    }


    // MARK: - Management (dashboard)

    func setJobEnabled(jobId: String, enabled: Bool) async throws {
        _ = try await request("cron.update", ["jobId": jobId, "patch": ["enabled": enabled]])
    }

    func jobRuns(jobId: String, limit: Int = 5) async throws -> [[String: Any]] {
        let payload = try await request("cron.runs", ["jobId": jobId, "limit": limit])
        let dict = payload as? [String: Any] ?? [:]
        return (dict["runs"] as? [[String: Any]]) ?? []
    }

    /// 待核准 + 已配對裝置
    func devicePairs() async throws -> (pending: [PendingApproval], approved: [PairedDevice]) {
        let payload = try await request("device.pair.list", [:])
        let dict = payload as? [String: Any] ?? [:]
        let reqRaw = (dict["pending"] as? [[String: Any]])
            ?? (dict["requests"] as? [[String: Any]])
            ?? (dict["pendingRequests"] as? [[String: Any]]) ?? []
        let devRaw = (dict["paired"] as? [[String: Any]])
            ?? (dict["devices"] as? [[String: Any]])
            ?? (dict["approved"] as? [[String: Any]]) ?? []
        return (reqRaw.compactMap(PendingApproval.parse), devRaw.compactMap(PairedDevice.parse))
    }

    func approveDevice(requestId: String) async throws {
        _ = try await request("device.pair.approve", ["requestId": requestId])
    }

    func rejectDevice(requestId: String) async throws {
        _ = try await request("device.pair.reject", ["requestId": requestId])
    }

    func removeDevice(deviceId: String) async throws {
        _ = try await request("device.pair.remove", ["deviceId": deviceId])
    }

    func availableModels() async throws -> [String] {
        // 先試 config 的允許清單(最準)
        if let cfgPayload = try? await request("config.get", [:]),
           let dict = cfgPayload as? [String: Any],
           let cfg = (dict["config"] as? [String: Any]) ?? (dict["value"] as? [String: Any]),
           let agents = cfg["agents"] as? [String: Any],
           let defaults = agents["defaults"] as? [String: Any],
           let models = defaults["models"] as? [String: Any], !models.isEmpty {
            return models.keys.sorted()
        }
        let payload = try await request("models.list", [:])
        let dict = payload as? [String: Any] ?? [:]
        if let list = dict["models"] as? [[String: Any]] {
            return list.compactMap { m -> String? in
                let id: String?
                if let direct = m["id"] as? String { id = direct }
                else if let p = m["provider"] as? String, let mid = m["model"] as? String { id = p + "/" + mid }
                else { id = nil }
                guard let id, !Self.bannedModel(id) else { return nil }
                return id
            }
        }
        if let list = dict["models"] as? [String] { return list.filter { !Self.bannedModel($0) } }
        return []
    }

    /// 已知被下架/不允許的模型,不要列出來
    static func bannedModel(_ id: String) -> Bool {
        let low = id.lowercased().replacingOccurrences(of: " ", with: "-")
        return low.contains("qwen3-vl") || low.contains("qwen3.7-vl") || low.contains("qwen3vl")
            || low.contains("q3-vl")
    }

    func patchSessionModel(sessionKey: String, model: String) async throws {
        _ = try await request("sessions.patch", ["key": sessionKey, "model": model])
    }

    // MARK: - internals

    private func finish(_ id: String, _ result: Result<Any?, Error>) {
        stateLock.lock()
        let c = pending.removeValue(forKey: id)
        stateLock.unlock()
        guard let c else { return }
        switch result {
        case .success(let v): c.resume(returning: v)
        case .failure(let e): c.resume(throwing: e)
        }
    }

    private func waitForChallenge() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            stateLock.lock(); challengeWaiter = cont; stateLock.unlock()
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self else { return }
                self.stateLock.lock()
                let c = self.challengeWaiter
                self.challengeWaiter = nil
                self.stateLock.unlock()
                guard let c else { return }
                c.resume(throwing: ClientError.challengeTimeout)
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                self.stateLock.lock()
                let wasOpen = self.isOpen
                self.isOpen = false
                let waiting = self.pending.values
                self.pending.removeAll()
                self.stateLock.unlock()
                waiting.forEach { $0.resume(throwing: err) }
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
               let nonce = payload["nonce"] as? String {
                stateLock.lock()
                let waiter = challengeWaiter
                challengeWaiter = nil
                stateLock.unlock()
                if let waiter { waiter.resume(returning: nonce) }
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
