import Foundation

/// 免費額度 / 試用期狀態
///
/// 為什麼要有這個:額度用完時 relay 只是「降速」、試用到期只是「斷線」,
/// 使用者完全不知道發生什麼事。這裡把用量取回來,讓 UI 能明確講原因。
struct RelayUsage: Equatable {
    var usedBytes: Int
    var quotaBytes: Int
    var trialExpiresAt: String?

    var ratio: Double { quotaBytes > 0 ? min(1.0, Double(usedBytes) / Double(quotaBytes)) : 0 }
    var remainingMB: Int { max(0, (quotaBytes - usedBytes) / 1_048_576) }
    var isOverQuota: Bool { usedBytes >= quotaBytes }
    var isNearLimit: Bool { ratio >= 0.8 }
    var isTrialExpired: Bool {
        guard let t = trialExpiresAt, let d = ISO8601DateFormatter().date(from: t) else { return false }
        return d < Date()
    }
}

extension AppModel {
    /// 連上後每 60 秒更新一次用量(使用者要被告知,而不是無聲降速)
    func startUsageWatch() {
        usageTask?.cancel()
        guard let ch = trialChannel, let sec = trialSecret else { return }
        usageTask = Task { [weak self] in
            while !Task.isCancelled {
                if let u = await Self.fetchRelayUsage(channel: ch, secret: sec) {
                    await MainActor.run { self?.relayUsage = u }
                }
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    static func fetchRelayUsage(channel: String, secret: String) async -> RelayUsage? {
        guard let url = URL(string: "https://xoio.io/relay/status/\(channel)?k=\(secret)") else { return nil }
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let used = obj["usedBytes"] as? Int,
              let quota = obj["quotaBytes"] as? Int else { return nil }
        return RelayUsage(usedBytes: used,
                          quotaBytes: quota,
                          trialExpiresAt: obj["trialExpiresAt"] as? String)
    }
}
