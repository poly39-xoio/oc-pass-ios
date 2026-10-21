import Foundation

enum DemoData {
    static let messages: [ChatMessage] = [
        ChatMessage(role: .assistant, text: "這是 Demo 模式:不需要連接 gateway 也能操作。\n\n連上你自己的 OpenClaw 後,這裡會顯示真實對話。"),
        ChatMessage(role: .user, text: "你可以幫我做什麼?"),
        ChatMessage(role: .assistant, text: "我可以幫你整理檔案、跑指令、查資料、設定排程,也可以操作你的電腦。實際能力取決於你在 gateway 開放的權限。")
    ]
}
