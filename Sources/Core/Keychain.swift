import Foundation
import Security

/// 極簡 Keychain 包裝(裝置金鑰、device token、gateway 網址都存在這裡)
enum Keychain {
    private static let service = "io.xoio.ocpass"

    static func set(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// 配對後留下的長期憑證:gateway 網址 + 這台裝置的 token
enum CredentialStore {
    private static let kURL = "gateway.url"
    private static let kToken = "gateway.token"
    private static let kKind = "gateway.kind"     // shared | device
    private static let kRole = "gateway.role"

    static func save(url: URL, token: TokenString, kind: String, role: String = "operator") {
        Keychain.set(url.absoluteString, for: kURL)
        Keychain.set(token, for: kToken)
        Keychain.set(kind, for: kKind)
        Keychain.set(role, for: kRole)
    }

    static func load() -> (url: URL, token: String, kind: String, role: String)? {
        guard let urlStr = Keychain.get(kURL), let url = URL(string: urlStr),
              let token = Keychain.get(kToken), !token.isEmpty else { return nil }
        return (url, token, Keychain.get(kKind) ?? "shared", Keychain.get(kRole) ?? "operator")
    }

    static func clear() {
        [kURL, kToken, kKind, kRole].forEach(Keychain.delete)
    }
}

/// 會話逐字稿本機快取:斷線/重開 App 都還在
enum TranscriptCache {
    private static var dir: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let d = base.appendingPathComponent("Transcripts", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    private static func file(for key: String) -> URL? {
        guard let dir else { return nil }
        return dir.appendingPathComponent(sha256Hex(Data(key.utf8)) + ".json")
    }

    static func save(_ messages: [ChatMessage], for key: String) {
        guard let file = file(for: key) else { return }
        guard let data = try? JSONEncoder().encode(messages) else { return }
        try? data.write(to: file, options: .atomic)
    }

    static func load(for key: String) -> [ChatMessage] {
        guard let file = file(for: key), let data = try? Data(contentsOf: file),
              let list = try? JSONDecoder().decode([ChatMessage].self, from: data) else { return [] }
        return list
    }

    static func clear(for key: String) {
        guard let file = file(for: key) else { return }
        try? FileManager.default.removeItem(at: file)
    }
}

/// Relay 通道憑證(存 Keychain → 刪掉 App 重裝仍在,可自動取回原本的線)
enum RelayCredStore {
    private static let kChannel = "relay.channel"
    private static let kSecret = "relay.secret"

    static func save(channel: String, secret: String) {
        Keychain.set(channel, for: kChannel)
        Keychain.set(secret, for: kSecret)
    }

    static func load() -> (channel: String, secret: String)? {
        guard let c = Keychain.get(kChannel), let s = Keychain.get(kSecret),
              !c.isEmpty, !s.isEmpty else { return nil }
        return (c, s)
    }

    static func clear() {
        Keychain.delete(kChannel)
        Keychain.delete(kSecret)
    }
}
