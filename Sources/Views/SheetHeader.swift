import SwiftUI

/// 統一的 sheet 頂部列:標題置中、左右各一顆「方形單層」按鈕(不用系統 toolbar,避免變成圓形玻璃底)
struct SheetHeader<Leading: View>: View {
    let title: String
    let leading: Leading
    let onDone: () -> Void

    init(title: String, onDone: @escaping () -> Void, @ViewBuilder leading: () -> Leading) {
        self.title = title
        self.onDone = onDone
        self.leading = leading()
    }

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer()
            Text(title)
                .font(Theme.ui(16, .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Button(action: onDone) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 30)
                    .background(Theme.panel2)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

extension SheetHeader where Leading == EmptyView {
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
