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
}

enum ConnectionState: Equatable {
    case idle
    case connecting
    case authenticating
    case pairing(String)   // requestId 待核准
    case ready
    case failed(String)
}
