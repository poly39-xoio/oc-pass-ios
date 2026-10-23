import Foundation

/// 極簡雙語(中/英)。以「中文原文」當 key,查不到就原樣回傳。
enum Language {
    static var current: String {
        get {
            if let v = UserDefaults.standard.string(forKey: "ocpass.lang"), !v.isEmpty { return v }
            let sys = Locale.preferredLanguages.first ?? "zh"
            return sys.lowercased().hasPrefix("en") ? "en" : "zh"
        }
        set { UserDefaults.standard.set(newValue, forKey: "ocpass.lang") }
    }
    static var isEnglish: Bool { current == "en" }
}

private let EN: [String: String] = [
    // 通用
    "完成": "Done", "取消": "Cancel", "執行": "Run", "批准": "Approve", "拒絕": "Reject",
    "撤銷": "Revoke", "連線": "Connect", "設定": "Settings", "會話": "Chats", "控制台": "Console",
    "沒有任務": "No tasks", "載入中…": "Loading…", "沒有會話": "No chats",
    "沒有已配對裝置": "No paired devices", "沒有待核准的請求": "No pending requests",
    "沒有已配對節點": "No paired nodes", "沒有可用模型": "No models", "切換": "Change",
    "最近會話": "Recent chats", "用量": "Usage", "會話數": "Chats", "總 tokens": "Total tokens",
    "最重會話": "Heaviest chat", "本會話模型": "Model for this chat", "節點": "Nodes",
    "自動化任務": "Automations", "已配對裝置": "Paired devices", "待核准": "Pending approval",
    "連線中斷,正在重連…": "Disconnected, reconnecting…",
    "還沒有任何工作階段 — 按上面的「開新對話」開始": "No sessions yet — tap “New chat” above",
    "開新對話": "New chat", "工作階段": "Sessions", "沒有工作階段": "No sessions",
    // 入口頁
    "掃描 QR 連線": "Scan QR to connect", "手動輸入 gateway": "Enter gateway manually",
    "openclaw dashboard": "openclaw dashboard",
    // 設定
    "使用者名稱": "Your name", "你的名字": "Your name",
    "只顯示在這支 App(App 裡的名字),不會改到 gateway 帳號": "Shown only in this app; does not change your gateway account",
    "手動連線": "Manual connection", "Gateway token": "Gateway token",
    "網址格式不對（例:wss://xoio.io/oc）": "Invalid URL (e.g. wss://xoio.io/oc)",
    "請貼上 Gateway token": "Please paste a gateway token",
    "隱私政策": "Privacy Policy", "版本": "Version",
    "中斷連線（保留配對）": "Disconnect (keep pairing)",
    "移除這台裝置（清除配對）": "Remove this device (clear pairing)",
    "語言": "Language", "切換後請重新開啟 App 生效": "Restart the app to apply the new language.", "繁體中文": "Traditional Chinese", "English": "English",
    "使用說明": "How it works", "關於": "About",
    // 控制台
    "Gateway": "Gateway", "延遲": "Latency", "狀態": "Status",
    "已連線": "Connected", "未連線": "Disconnected", "下次": "next",
    "撤銷這台裝置？": "Revoke this device?", "撤銷（需重新配對）": "Revoke (re-pair required)",
    "收鍵盤": "Hide keyboard",
    // 附加檔案
    "附加檔案": "Attach file", "照片": "Photo", "檔案": "File",
    "複製圖片": "Copy image", "快速查看": "Quick Look", "分享": "Share",
    "太大": "Too large", "這個檔案超過 18 MB,請壓縮後再傳": "This file exceeds 18 MB — please compress it first.",
    "無法讀取這個檔案": "Could not read this file",
    // 說明
    "我們不會收集你的對話與資料,內容只會送到你自己的 gateway。":
        "We do not collect your chats or data — everything goes only to your own gateway.",
    "OC Pass 是針對 OpenClaw Gateway 所設計的優化器。":
        "OC Pass is an optimizer designed for OpenClaw Gateway.",
    "1. 在你的電腦或伺服器安裝 OpenClaw,並啟動 gateway。":
        "1. Install OpenClaw on your computer or server and start the gateway.",
    "2. 在 gateway 上執行 openclaw qr,用手機掃描產生的 QR。":
        "2. Run `openclaw qr` on the gateway and scan the QR with this app.",
    "3. 沒有網域或公網 IP?可在設定改用 XOIO Relay(訂閱制)。":
        "3. No domain or public IP? Switch to XOIO Relay in Settings (subscription).",
    "檔案上限:圖片 6 MB、其他檔案 18 MB。":
        "Attachment limits: images 6 MB, other files 18 MB.",
    "隨時可在設定頁「移除這台裝置」斷開配對。":
        "You can always unpair from Settings → Remove this device."
]

func L(_ key: String) -> String {
    guard Language.isEnglish else { return key }
    return EN[key] ?? key
}
