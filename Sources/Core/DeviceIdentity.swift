import Foundation
import CryptoKit

/// ed25519 裝置身份(與 gateway 協議一致)
/// deviceId = sha256(raw public key) hex
/// 簽章內容 v3 = "v3|deviceId|clientId|clientMode|role|scopes|signedAt|token|nonce|platform|deviceFamily"
struct DeviceIdentity {
    let deviceId: String
    let publicKeyRaw: Data
    let privateKey: Curve25519.Signing.PrivateKey

    static func loadOrCreate() -> DeviceIdentity {
        if let saved = DeviceStore.load() { return saved }
        let key = Curve25519.Signing.PrivateKey()
        let id = DeviceIdentity(deviceId: sha256Hex(key.publicKey.rawRepresentation),
                                publicKeyRaw: key.publicKey.rawRepresentation,
                                privateKey: key)
        DeviceStore.save(id)
        return id
    }

    func sign(_ payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let sig = try? privateKey.signature(for: data) else { return nil }
        return sig.base64URLEncodedString()
    }

    var publicKeyBase64URL: String { publicKeyRaw.base64URLEncodedString() }

    static func payloadV3(deviceId: String, clientId: String, clientMode: String, role: String,
                          scopes: [String], signedAt: Int64, token: ***, nonce: String,
                          platform: String, deviceFamily: String) -> String {
        [ "v3", deviceId, clientId, clientMode, role, scopes.joined(separator: ","),
          String(signedAt), token, nonce,
          platform.trimmingCharacters(in: .whitespaces).lowercased(),
          deviceFamily.trimmingCharacters(in: .whitespaces).lowercased()
        ].joined(separator: "|")
    }
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// 先把金鑰存 Keychain(骨架用最簡實作)
enum DeviceStore {
    private static let key = "io.xoio.ocpass.device"
    static func save(_ id: DeviceIdentity) {
        let payload = ["priv": id.privateKey.rawRepresentation.base64EncodedString()]
        UserDefaults.standard.set(payload, forKey: key)   // TODO: 移到 Keychain
    }
    static func load() -> DeviceIdentity? {
        guard let d = UserDefaults.standard.dictionary(forKey: key),
              let b64 = d["priv"] as? String, let raw = Data(base64Encoded: b64),
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { return nil }
        return DeviceIdentity(deviceId: sha256Hex(key.publicKey.rawRepresentation),
                              publicKeyRaw: key.publicKey.rawRepresentation,
                              privateKey: key)
    }
}
