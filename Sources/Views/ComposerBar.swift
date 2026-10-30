import SwiftUI
import UIKit

/// 輸入列(獨立子視圖)
///
/// 為什麼要拆出來:先前輸入框的狀態(draft/高度/焦點)放在 ChatView 裡,
/// 手寫或注音每輸入一筆 → ChatView.body 重算 → **整個訊息列表重新排版**,
/// 訊息越多越慢。把這些狀態搬進這個子視圖後,打字只重繪輸入列,
/// 訊息列表(VStack)完全不動 → 又快又不會像 LazyVStack 那樣「送出後跳掉」。
struct ComposerBar: View {
    var onAttach: () -> Void
    var onSend: (String) -> Void
    var draftKey: String

    @State private var text = ""
    @State private var height: CGFloat = Theme.inputMin
    @State private var focused = false
    @State private var saveTask: Task<Void, Never>?
    /// 語音聽寫搬進來:transcript 每秒更新多次,留在 ChatView 會讓整個列表重繪 → 語音很慢
    @StateObject private var speech = SpeechInput()

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button(action: onAttach) {
                Image(systemName: "paperclip")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
            }

            Button { speech.toggle() } label: {
                Image(systemName: speech.isRecording ? "mic.circle.fill" : "mic")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(speech.isRecording ? Theme.warn : .white)
                    .frame(width: 30, height: 30)
            }

            GrowingTextField(text: $text, height: $height, focused: $focused,
                             minHeight: Theme.inputMin, maxHeight: Theme.inputMax)
                .frame(height: height)
                .padding(.horizontal, 10)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                let value = text
                text = ""          // 先清空:輸入框立刻縮回單行
                height = Theme.inputMin
                saveNow("")
                onSend(value)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(canSend ? Theme.accent : Theme.muted.opacity(0.6))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .onAppear { text = Self.load(draftKey) }
        .onChange(of: text) { _, v in scheduleSave(v) }
        .onChange(of: speech.transcript) { _, v in
            guard speech.isRecording, !v.isEmpty else { return }
            text = v
        }
        .onDisappear { saveNow(text) }
    }

    // 草稿保存:停止輸入 0.7 秒,且寫在背景佇列(不要卡主執行緒)
    private func scheduleSave(_ value: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            saveNow(value)
        }
    }

    private func saveNow(_ value: String) {
        let key = draftKey
        DispatchQueue.global(qos: .utility).async {
            let d = UserDefaults.standard
            if value.isEmpty {
                d.removeObject(forKey: key)
                d.removeObject(forKey: "ocpass.draft.last")
            } else {
                d.set(value, forKey: key)
                d.set(value, forKey: "ocpass.draft.last")
            }
        }
    }

    static func load(_ key: String) -> String {
        let perSession = UserDefaults.standard.string(forKey: key) ?? ""
        let last = UserDefaults.standard.string(forKey: "ocpass.draft.last") ?? ""
        return perSession.isEmpty ? last : perSession
    }
}
