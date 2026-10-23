import Foundation

enum DemoData {
    static func reply(to text: String) -> String {
        let t = text.lowercased()
        if t.contains("?") || t.contains("什麼") || t.contains("what") || t.contains("how") {
            return "（Demo 模式）這是示範回覆：連上你自己的 OpenClaw 後，這裡會是你真正的答案。實際能力取決於你在 gateway 開放的權限。"
        }
        if t.contains("hi") || t.contains("hello") || t.contains("你好") {
            return "（Demo 模式）嗨！這是不連線的示範。按左上「中斷」或回首頁，就能換成連你自己的 gateway。"
        }
        return "（Demo 模式）收到：「\(text)」。真正的回覆要連上你的 gateway 才會出現。"
    }

    static let messages: [ChatMessage] = [
        ChatMessage(role: .assistant, text: "這是 Demo 模式:不需要連接 gateway 也能操作。\n\n連上你自己的 OpenClaw 後,這裡會顯示真實對話。"),
        ChatMessage(role: .user, text: "你可以幫我做什麼?"),
        ChatMessage(role: .assistant, text: "我可以幫你整理檔案、跑指令、查資料、設定排程,也可以操作你的電腦。實際能力取決於你在 gateway 開放的權限。")
    ]
}
