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
                              activeRunIds: (dict["activeRunIds"] as? [String]) ?? [])
    }
}

struct SendResult {
    let runId: String
}
