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

        // 手寫/注音每輸入一筆都會走到這裡。舊版每次 update 量兩次 sizeThatFits,
        // 整個文字排版量測在主執行緒上 → 手寫輸入明顯延遲。改成:只量一次,而且
        // 只有「文字或寬度真的變了」才量,回寫 binding 也去重。
        let width = tv.bounds.width > 0 ? tv.bounds.width : context.coordinator.lastMeasuredWidth
        let textChanged = context.coordinator.lastMeasuredText != tv.text
        let widthChanged = abs(width - context.coordinator.lastMeasuredWidth) > 0.5
        if width > 0, textChanged || widthChanged {
            context.coordinator.lastMeasuredWidth = width
            context.coordinator.lastMeasuredText = tv.text
            let fitting = tv.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            let target = clampedHeight(fitting)
            tv.isScrollEnabled = fitting > maxHeight
            if abs(height - target) > 0.5, abs(context.coordinator.lastAppliedHeight - target) > 0.5 {
                context.coordinator.lastAppliedHeight = target
                DispatchQueue.main.async { self.height = target }
            }
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
