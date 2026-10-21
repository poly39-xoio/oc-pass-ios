# OC Pass (iOS, native SwiftUI)

手機上的 OpenClaw 遙控器：掃 QR 連上自己的 gateway，聊天、語音、推播。

## 現況
- 骨架完成：SwiftUI 入口、連線層、聊天畫面、QR 掃描、設定、Demo 模式
- 尚未驗證：**gateway 連線協議**(device identity / challenge / pairing) → 這是第一個 spike

## 本機開發
```bash
brew install xcodegen
xcodegen generate
open OpenClawRemote.xcodeproj
```

## CI
`.github/workflows/ios.yml`：push 時建置模擬器版；手動觸發可 archive + 上傳 TestFlight（需 secrets：`ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8`、`TEAM_ID`）

## 待決策
- App 名稱:OC Pass｜Bundle ID:io.xoio.ocpass
- 收費模式（US$4.99 買斷 或 免費+訂閱）
- 品牌（獨立 或 XOIO）
