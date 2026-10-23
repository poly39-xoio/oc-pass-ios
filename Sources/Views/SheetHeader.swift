import SwiftUI

/// 統一的 sheet 頂部列:左邊「返回箭頭」、中間標題、右邊可放配件(例如語言鍵)。
/// 自己畫,不用系統 toolbar,避免 iOS 26 自動加圓形玻璃底。
struct SheetHeader<Trailing: View>: View {
    let title: String
    let onDone: () -> Void
    let trailing: Trailing

    init(title: String, onDone: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.onDone = onDone
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onDone) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 30)
                    .background(Theme.panel2)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("完成"))

            Spacer()
            Text(title)
                .font(Theme.ui(16, .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()

            trailing.frame(minWidth: 32, minHeight: 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

extension SheetHeader where Trailing == EmptyView {
    init(title: String, onDone: @escaping () -> Void) {
        self.init(title: title, onDone: onDone) { EmptyView() }
    }
}

/// 方形語言切換鍵(單層)
struct LanguagePill: View {
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            Text(Language.isEnglish ? "中" : "EN")
                .font(Theme.ui(13, .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 30)
                .background(Theme.panel2)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
