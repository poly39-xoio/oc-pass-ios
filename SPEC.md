# OC Pass — 產品規格 v0.1

> 手機上的 OpenClaw 遙控器：掃 QR 連上你自己的 agent，隨時聊天、收推播、用語音下指令。
> 全原生 SwiftUI（路線 B）。目標：App Store 上架、可買斷或訂閱。

## 1. 目標與非目標

**目標**
- 3 分鐘內完成「掃 QR → 連線 → 第一句對話」
- 不是純 WebView 包裝：必須有 QR 配對、推播、語音、離線快取、Demo 模式
- 支援多 gateway（家裡 Mac / 雲端 VPS）
- 可上架 App Store（Guideline 4.2 / 2.5.2 / 5.1.1 合規）

**非目標（v1 不做）**
- 不在手機上跑 gateway
- 不做多用戶/團隊權限
- 不做雲端代管（v2 再談）
- 不做完整設定編輯器（先做唯讀摘要 + 開關常用項）

## 2. 使用流程（6 個畫面）

1. **Welcome**：一句話價值 +「掃描 QR」「手動輸入」「Demo 模式」
2. **Scan**：相機掃 QR（`openclaw://pair?...` 或 dashboard 的配對連結）
3. **Connect**：顯示進度（網路 → 認證 → 配對 → 載入 sessions），失敗給可操作原因
4. **Chat**：session 清單（側拉）+ 對話 + 輸入列（文字/語音/附件）
5. **Settings**：gateway 管理（多台）、通知、外觀、隱私政策、登出/移除
6. **Demo**：內建假資料，可完整操作（審查員用）

## 3. Gateway 連線

- 傳輸：WebSocket（wss）
- 認證：token（`gateway.auth.token`）或 password
- 裝置：首次連線需要 device identity + 一次性配對核准
- 端點：`wss://<host>/oc`（或使用者自填）

**風險（必須先做 spike）**
- 原生 client 需要重現 Control UI 的 connect 流程：`connect.challenge` nonce → 建 device key → 簽章 → pairing
- 若協議太複雜，替代方案：app 內嵌 WebView 只做「配對/授權」，其餘原生；但這會拉高 4.2 風險
- Spike 目標：3 天內證明「原生 Swift 能用 token + 裝置金鑰連上並收發訊息」

## 4. 原生功能（審查必要）

| 功能 | 說明 | 優先 |
|---|---|---|
| QR 配對 | 掃描即綁定，免手打 token | P0 |
| 推播 | agent 完成/需核准時通知（APNs） | P0 |
| 語音輸入 | 按住說話 → 轉文字 | P0 |
| 離線快取 | 最近 50 則可讀、待送訊息排隊 | P1 |
| Demo 模式 | 假資料可操作，審查員免 gateway | P0 |
| 多 gateway | 清單 + 切換 | P1 |
| Watch 快速指令 | 手錶語音記一句 | P2 |

## 5. 資料模型

```swift
struct Gateway: Identifiable, Codable { id, name, url, tokenRef, lastSeen }
struct ChatSession: Identifiable { id, title, updatedAt, agentId }
struct ChatMessage: Identifiable { id, role, text, createdAt, attachments, status }
```

- Token 存 **Keychain**（絕不進 UserDefaults）
- 對話快取存 SQLite（GRDB）或 SwiftData

## 6. 里程碑（4–6 週）

| 週 | 內容 | 交付 |
|---|---|---|
| W1 | 協議 spike、專案骨架、CI 建置 | 能在 TestFlight 開啟 |
| W2 | QR 配對、連線、session 清單 | 可連自己的 gateway |
| W3 | 聊天 UI、語音輸入、附件 | 可用來日常對話 |
| W4 | 推播（APNs + gateway 端掛鉤）、離線快取 | 背景通知可用 |
| W5 | Demo 模式、設定、隱私政策、內購（若做） | 可送審 |
| W6 | 送審、修正、上架 | App Store |

## 7. 上架檢核

- [ ] 非 WebView 包裝（原生 UI 佔絕大多數）
- [ ] Demo 模式可完整操作
- [ ] 隱私政策 URL、資料收集揭露
- [ ] 若建帳號 → Sign in with Apple + 帳號刪除
- [ ] 若收費 → IAP（買斷用非消耗型）
- [ ] 加密合規（usesNonExemptEncryption=false）
- [ ] 審查備註：如何連線、Demo 帳號、QR 範例

## 8. 待你決定

- App 名稱（暫用 `OpenClaw Remote`）
- Bundle ID 前綴（暫用 `io.xoio.openclawremote`）
- 收費：US$4.99 買斷 / 免費 + 訂閱
- 品牌：獨立品牌（建議）或掛 XOIO
