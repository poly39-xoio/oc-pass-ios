import SwiftUI
import UIKit

/// 有高度上限的輸入框:文字清空後一定會縮回單行高度,不會一直佔半個螢幕
struct GrowingTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var minHeight: CGFloat = 38
    var maxHeight: CGFloat = 96

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text { tv.text = text }
        let width = tv.bounds.width > 0 ? tv.bounds.width : 240
        let fitting = tv.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let target = min(max(fitting, minHeight), maxHeight)
        tv.isScrollEnabled = fitting > maxHeight
        if abs(height - target) > 0.5 {
            DispatchQueue.main.async { self.height = target }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: GrowingTextField
        init(_ parent: GrowingTextField) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}
