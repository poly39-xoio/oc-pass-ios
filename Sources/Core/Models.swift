import Foundation

struct Gateway: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var url: URL
    var lastSeen: Date?
}

struct ChatSession: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var updatedAt: Date
}

enum MessageRole: String, Codable { case user, assistant, system }

struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var role: MessageRole
    var text: String
    var createdAt = Date()
    var pending = false
    /// 工具/中間產物列:不顯示,但用來切斷「同一輪」的助理訊息
    var hidden: Bool? = nil

    var isHidden: Bool { hidden == true }
}

/// 準備送出的附件(照片 / 檔案)
struct PendingAttachment: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var mimeType: String
    var data: Data

    var isImage: Bool { mimeType.hasPrefix("image/") }
}

/// 自動化任務(來自 gateway cron.list)
struct GatewayCronJob: Identifiable, Equatable {
    let id: String
    let name: String
    let enabled: Bool
    let scheduleText: String
    let nextRunAt: Date?
    let lastStatus: String?

    static func parse(_ d: [String: Any]) -> GatewayCronJob? {
        guard let id = (d["id"] as? String) ?? (d["jobId"] as? String) else { return nil }
        let name = (d["name"] as? String) ?? (d["displayName"] as? String) ?? id
        let enabled = (d["enabled"] as? Bool) ?? true
        let sched = d["schedule"] as? [String: Any] ?? [:]
        var text = "—"
        if let expr = sched["expr"] as? String {
            text = expr + ((sched["tz"] as? String).map { " · \($0)" } ?? "")
        } else if let every = sched["everyMs"] as? Double {
            text = "每 \(max(1, Int(every / 60000))) 分鐘"
        } else if let at = sched["at"] as? String {
            text = at
        }
        let next = (d["nextRunAtMs"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return GatewayCronJob(id: id, name: name, enabled: enabled, scheduleText: text,
                              nextRunAt: next, lastStatus: d["lastRunStatus"] as? String)
    }
}

/// 節點(來自 gateway node.list)
struct GatewayNode: Identifiable, Equatable {
    let id: String
    let name: String
    let platform: String
    let online: Bool

    static func parse(_ d: [String: Any]) -> GatewayNode? {
        guard let id = (d["id"] as? String) ?? (d["nodeId"] as? String) else { return nil }
        let name = (d["name"] as? String) ?? (d["displayName"] as? String) ?? id
        let status = (d["status"] as? String) ?? ""
        let online = (d["online"] as? Bool) ?? ["online", "connected"].contains(status.lowercased())
        return GatewayNode(id: id, name: name, platform: d["platform"] as? String ?? "—", online: online)
    }
}


/// 待核准的配對請求
struct PendingApproval: Identifiable, Equatable {
    let id: String          // requestId
    let deviceName: String
    let platform: String
    let ip: String

    static func parse(_ d: [String: Any]) -> PendingApproval? {
        let rid = (d["requestId"] as? String) ?? (d["id"] as? String) ?? ""
        guard !rid.isEmpty else { return nil }
        let name = (d["deviceName"] as? String) ?? (d["name"] as? String) ?? (d["displayName"] as? String) ?? "未知裝置"
        let platform = (d["platform"] as? String) ?? (d["role"] as? String) ?? "—"
        let ip = (d["ip"] as? String) ?? (d["remoteAddr"] as? String) ?? ""
        return PendingApproval(id: rid, deviceName: name, platform: platform, ip: ip)
    }
}

/// 已配對裝置
struct PairedDevice: Identifiable, Equatable {
    let id: String          // deviceId
    let name: String
    let roles: String
    let ip: String
    let online: Bool

    static func parse(_ d: [String: Any]) -> PairedDevice? {
        let did = (d["deviceId"] as? String) ?? (d["id"] as? String) ?? ""
        guard !did.isEmpty else { return nil }
        let name = (d["displayName"] as? String) ?? (d["name"] as? String) ?? "裝置"
        let roles = (d["roles"] as? [String])?.joined(separator: ",") ?? (d["role"] as? String) ?? "—"
        let ip = (d["ip"] as? String) ?? (d["remoteAddr"] as? String) ?? ""
        return PairedDevice(id: did, name: name, roles: roles, ip: ip, online: (d["online"] as? Bool) ?? false)
    }
}

enum ConnectionState: Equatable {
    case idle
    case connecting
    case authenticating
    case pairing(String)   // requestId 待核准
    case ready
    case failed(String)
}
