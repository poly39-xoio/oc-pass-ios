import Foundation

struct GatewaySession: Identifiable, Equatable {
    let id: String        // sessionKey
    let sessionId: String
    let title: String
    let updatedAt: Date?
    let unread: Int
    let totalTokens: Int
    let hasActiveRun: Bool
    let activeRunIds: [String]
    let model: String?

    static func parseModel(_ d: [String: Any]) -> String? {
        if let s = d["model"] as? String, !s.isEmpty { return s }
        if let m = d["model"] as? [String: Any] {
            if let p = m["provider"] as? String, let id = m["model"] as? String { return p + "/" + id }
            if let id = m["modelId"] as? String { return id }
            if let id = m["id"] as? String { return id }
        }
        if let s = d["modelId"] as? String, !s.isEmpty { return s }
        return nil
    }

    static func parse(_ dict: [String: Any]) -> GatewaySession? {
        guard let key = dict["key"] as? String else { return nil }
        let sid = dict["sessionId"] as? String ?? key
        let name = dict["displayName"] as? String
            ?? dict["title"] as? String
            ?? key.split(separator: ":").suffix(1).joined()
        let ts = (dict["updatedAt"] as? Double) ?? (dict["lastActivityAt"] as? Double)
        return GatewaySession(id: key, sessionId: sid, title: name,
                              updatedAt: ts.map { Date(timeIntervalSince1970: $0 / 1000) },
                              unread: dict["unread"] as? Int ?? 0,
                              totalTokens: (dict["totalTokens"] as? Int) ?? Int(dict["totalTokens"] as? Double ?? 0),
                              hasActiveRun: dict["hasActiveRun"] as? Bool ?? false,
                              activeRunIds: (dict["activeRunIds"] as? [String]) ?? [],
                              model: GatewaySession.parseModel(dict))
    }
}

struct SendResult {
    let runId: String
}
