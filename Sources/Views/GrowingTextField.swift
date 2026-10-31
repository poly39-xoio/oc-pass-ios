import SwiftUI
import UIKit

/// 多行輸入框:
/// - 依內容自動長高,上限 maxHeight(超過就內部捲動)
/// - 送出/清空後一定縮回 minHeight(不會殘留半個螢幕)
/// - focus 由外部 Binding 控制(點空白處收鍵盤、點輸入框再出現)
struct GrowingTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var focused: Bool
    var minHeight: CGFloat = 38
    var maxHeight: CGFloat = 120

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.font = UIFont(name: "AvenirNext-Regular", size: 16) ?? UIFont.preferredFont(forTextStyle: .body)
        tv.textColor = UIColor(Theme.ink)
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        tv.textContainer.lineFragmentPadding = 0
        tv.keyboardDismissMode = .interactive
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
        }

        // 每次都量一次(只量一次,成本可接受),但只在高度真的變了才回寫 binding。
        // 2026-10-31 修正:先前加了「文字/寬度沒變就跳過量測」的判斷,某些時機
        // (寬度還沒量到)整個跳過 → 輸入框卡在單行高度,第二行之後被裁掉看不到。
        let width = tv.bounds.width > 0 ? tv.bounds.width : 240
        let fitting = tv.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let target = clampedHeight(fitting)
        tv.isScrollEnabled = fitting > maxHeight
        if abs(height - target) > 0.5 {
            DispatchQueue.main.async { self.height = target }
        }

        if focused != tv.isFirstResponder {
            DispatchQueue.main.async {
                if self.focused, !tv.isFirstResponder {
                    tv.becomeFirstResponder()
                } else if !self.focused, tv.isFirstResponder {
                    tv.resignFirstResponder()
                }
            }
        }
    }

    private func clampedHeight(_ fitting: CGFloat) -> CGFloat {
        min(max(fitting, minHeight), maxHeight)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: GrowingTextField
        var lastMeasuredWidth: CGFloat = 0
        var lastMeasuredText: String = ""
        var lastAppliedHeight: CGFloat = 0
        init(_ parent: GrowingTextField) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.focused {
                DispatchQueue.main.async { self.parent.focused = true }
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.focused {
                DispatchQueue.main.async { self.parent.focused = false }
            }
        }
    }
}
