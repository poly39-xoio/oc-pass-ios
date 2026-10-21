import Foundation

/// 與 OpenClaw Gateway 的原生 WebSocket 連線。
/// 協議:JSON 文字幀;{type:"req",id,method,params} ↔ {type:"res",id,ok,payload}
/// 事件:{type:"event",event,payload}
actor GatewayClient {
    private var task: URLSessionWebSocketTask?
    private var pending: [String: CheckedContinuation<Any?, Error>] = [:]
    private var eventHandler: ((String, Any?) -> Void)?
    private(set) var isOpen = false

    func onEvent(_ handler: @escaping (String, Any?) -> Void) { eventHandler = handler }

    func connect(url: URL, token: String) async throws {
        let session = URLSession(configuration: .default)
        let t = session.webSocketTask(with: url)
        task = t
        t.resume()
        isOpen = true
        listen()
        // 1) 等 challenge
        // 2) 送 connect(含 auth token + device identity)
        // TODO(spike): device key 產生與簽章;目前先送 token 認證
        _ = try await request("connect", ["auth": ["token": token], "role": "operator"])
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isOpen = false
    }

    func request(_ method: String, _ params: [String: Any] = [:]) async throws -> Any? {
        guard let task else { throw URLError(.notConnectedToInternet) }
        let id = UUID().uuidString
        let frame: [String: Any] = ["type": "req", "id": id, "method": method, "params": params]
        let data = try JSONSerialization.data(withJSONObject: frame)
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            task.send(.data(data)) { err in
                if let err { Task { await self.fail(id, err) } }
            }
        }
    }

    private func fail(_ id: String, _ error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            Task {
                switch result {
                case .failure(let err):
                    await self.handleClose(err)
                case .success(let message):
                    await self.handle(message)
                    await self.listenAgain()
                }
            }
        }
    }

    private func listenAgain() { listen() }

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

        if type == "res", let id = obj["id"] as? String {
            let cont = pending.removeValue(forKey: id)
            if obj["ok"] as? Bool == true { cont?.resume(returning: obj["payload"]) }
            else { cont?.resume(throwing: NSError(domain: "gateway", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(obj["error"] ?? "request failed")"])) }
        } else if type == "event" {
            eventHandler?(obj["event"] as? String ?? "", obj["payload"])
        }
    }

    private func handleClose(_ error: Error) {
        isOpen = false
        pending.values.forEach { $0.resume(throwing: error) }
        pending.removeAll()
    }
}
