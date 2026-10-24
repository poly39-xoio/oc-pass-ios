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
    "手動連線": "Manual connection", "自己的網址": "My URL", "貼上 Relay 配對碼": "Paste relay code",
    "Relay 配對碼無法解析": "Cannot parse the relay code", "請貼上 Relay 配對碼": "Paste a relay code", "Gateway token": "Gateway token",
    "網址格式不對（例：ws://192.168.1.20:18789）": "Invalid URL (e.g. ws://192.168.1.20:18789)",
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
    "系統任務": "System job", "複製圖片": "Copy image", "快速查看": "Quick Look", "分享": "Share",
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
        "You can always unpair from Settings → Remove this device.",
    // Relay / 訂閱(2026-10-23)
    "一鍵連線": "One-tap connect",
    "免費方案：100MB/月 · 需要更多可訂閱 $2.99/月 或 $24.99/年（前 3 天免費）":
        "Free plan: 100 MB/month. Need more? $2.99/month or $24.99/year (3-day free trial).",
    "正在建立連線通道…": "Creating your relay channel…",
    "重新試一次": "Try again",
    "在跑 OpenClaw 的電腦上，貼上這行並按 Enter":
        "Paste this line on the computer running OpenClaw, then press Enter.",
    "已複製 ✓": "Copied ✓",
    "複製指令": "Copy command",
    "不用做其他事 — 電腦裝好後，這支 App 會自動接上":
        "Nothing else to do — this app connects automatically once your computer is set up.",
    "等待電腦端連上…": "Waiting for your computer…",
    "免費到": "Free until",
    "按下面按鈕，30 秒內就能連上你的 OpenClaw":
        "Tap below to connect to your OpenClaw in about 30 seconds.",
    "免費連線": "Connect for free",
    "不需要註冊帳號，也不必自己有網域或公網 IP。":
        "No account, no domain, no public IP required.",
    "不用網域、不用開 port，出門也能連。免費 100MB/月；訂閱 $2.99/月 或 $24.99/年（前 3 天免費，1GB/月）。":
        "No domain or port forwarding needed. Free 100 MB/month; subscription $2.99/month or $24.99/year (3-day free trial, 1 GB/month).",
    "免費連線（100MB/月）": "Connect free (100 MB/mo)",
    "訂閱 / 還原購買": "Subscribe / Restore",
    "訂閱 Relay": "Relay subscription",
    "前 3 天免費，之後自動續訂（1GB/月）。可隨時在 Apple ID 設定取消。":
        "3 days free, then auto-renews (1 GB/month). Cancel anytime in Apple ID settings.",
    "已訂閱，Relay 已解鎖": "Subscribed — relay unlocked",
    "讀取商品中…": "Loading products…",
    "重新整理": "Refresh",
    "免費層 100MB/月；訂閱後 1GB/月。":
        "Free tier 100 MB/month; 1 GB/month with a subscription.",
    "還原購買": "Restore purchases",
    "訂閱會自動續訂，除非在到期前 24 小時取消。管理或取消：設定 › Apple ID › 訂閱。":
        "Subscriptions renew automatically unless cancelled 24 hours before renewal. Manage: Settings › Apple ID › Subscriptions.",
    "年繳": "Yearly",
    "月繳": "Monthly",
    "平均 $2.08/月，省 30%": "≈$2.08/month — save 30%",
    "每月自動續訂": "Auto-renews monthly",
    "前 %d 天免費": "Free for %d days",
    "找不到訂閱商品(可能還在 App Store Connect 審核設定中)":
        "Products unavailable (they may still be in App Store Connect review setup).",
    // 對話選單
    "複製": "Copy",
    "分享文字": "Share text",
    "刪除訊息": "Delete message",
    "刪除照片": "Delete photo",
    "刪除檔案": "Delete file",
    "清除本機紀錄": "Clear local history",
    // 支援信箱 / 連線取回
    "有問題或需要協助，歡迎寫信給我們。": "Questions or need help? Email us anytime.",
    "進階：手動貼上配對碼": "Advanced: paste pairing code manually",
    "用手動配對碼連線": "Connect with pairing code",
    "只有自動連線失敗時才需要：在電腦執行 cat ~/.oc-tunnel/pair-code.txt，把整串貼進來。":
        "Only needed when auto-connect fails: on your computer run cat ~/.oc-tunnel/pair-code.txt and paste the whole string here.",
    "填你自己 gateway 的位址；沒有網域或公網 IP，請用下面的 XOIO Relay。":
        "Enter your own gateway address. If you have no domain or public IP, use XOIO Relay below.",
    "用電腦執行 openclaw qr，掃它產生的 QR": "Run openclaw qr on your computer and scan its QR",
    "自己填 URL 與 token（進階）": "Enter URL and token yourself (advanced)",
    "不用連線，先看看介面": "No connection needed — take a look",
    "退出": "Exit",
    "診斷": "Diagnostics",
    "最近的執行紀錄（閃退前的最後步驟）": "Recent trace (last steps before a crash)",
    "複製診斷紀錄": "Copy diagnostics",
    "已複製診斷紀錄": "Diagnostics copied",
    "讀取會話失敗": "Couldn't load chats",
    "切換模型失敗:": "Failed to switch model: ",
    // Demo(模式內文字也要跟著語系)
    "這是 Demo 模式：不需要連接 gateway 也能操作。\n\n連上你自己的 OpenClaw 後，這裡會顯示真實對話。":
        "Demo mode: explore without connecting a gateway.\n\nOnce you connect your own OpenClaw, real conversations appear here.",
    "你可以幫我做什麼?": "What can you do for me?",
    "我可以幫你整理檔案、跑指令、查資料、設定排程，也可以操作你的電腦。實際能力取決於你在 gateway 開放的權限。":
        "I can organise files, run commands, look things up, schedule tasks and operate your computer — within the permissions you grant in your gateway.",
    "（Demo 模式）這是示範回覆：連上你自己的 OpenClaw 後，這裡會是你真正的答案。實際能力取決於你在 gateway 開放的權限。":
        "(Demo) This is a sample reply. After you connect your own OpenClaw this is where the real answer appears; capabilities depend on the permissions you grant.",
    "（Demo 模式）嗨！這是不連線的示範。按右上「退出」或回首頁，就能換成連你自己的 gateway。":
        "(Demo) Hi! This is an offline demo. Tap “Exit” at the top right, or go back to the entry screen, to connect your own gateway.",
    "（Demo 模式）收到：「%@」。真正的回覆要連上你的 gateway 才會出現。":
        "(Demo) Received: “%@”. Real replies require your gateway.",
    "取不回原本的連線，請稍後再試": "Couldn't restore your previous connection — please try again.",
    "裝置簽章失敗": "Device signing failed.",
    "Relay 回應格式錯誤": "Unexpected response from relay.",
    "Relay 沒有回傳通道資訊": "Relay did not return channel info."
]

func L(_ key: String) -> String {
    guard Language.isEnglish else { return key }
    return EN[key] ?? key
}
