import SwiftUI
import StoreKit

/// 訂閱頁:3 天免費試用 → $2.99/月 或 $24.99/年
struct PaywallView: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SheetHeader(title: L("訂閱 Relay"), onDone: { dismiss() })

                        Text(L("前 3 天免費，之後自動續訂。可隨時在 Apple ID 設定取消。"))
                            .font(Theme.ui(13))
                            .foregroundStyle(.white.opacity(0.8))

                        if store.subscribed {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                                Text(L("已訂閱，Relay 已解鎖")).foregroundStyle(.white)
                            }
                            .font(Theme.ui(15, .semibold))
                        } else if store.loading && store.products.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text(L("讀取商品中…")).foregroundStyle(.white)
                            }
                        } else if let err = store.error, store.products.isEmpty {
                            Text(err).font(Theme.ui(13)).foregroundStyle(Theme.warn)
                            bigButton(L("重新整理")) { Task { await store.load() } }
                        } else {
                            ForEach(store.products, id: \.id) { p in
                                productRow(p)
                            }
                            Text(L("訂閱可解鎖 Relay 連線（每月 1GB 流量）。"))
                                .font(Theme.ui(12))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        Button {
                            Task { await store.restore() }
                        } label: {
                            Text(L("還原購買"))
                                .font(Theme.ui(13, .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(.top, 4)

                        Text(L("訂閱會自動續訂，除非在到期前 24 小時取消。管理或取消：設定 › Apple ID › 訂閱。"))
                            .font(Theme.ui(11))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await store.load() }
    }

    private func productRow(_ p: Product) -> some View {
        let isYearly = p.id == Store.yearly
        return Button {
            Task { await store.buy(p) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isYearly ? L("年繳") : L("月繳"))
                        .font(Theme.ui(15, .bold))
                        .foregroundStyle(.white)
                    Text(isYearly ? L("平均 $2.08/月，省 30%") : L("每月自動續訂"))
                        .font(Theme.ui(12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Text(p.displayPrice)
                    .font(Theme.ui(16, .bold))
                    .foregroundStyle(.white)
                if let sub = p.subscription, let offer = sub.introductoryOffer {
                    Text(String(format: L("前 %d 天免費"), offer.period.value))
                        .font(Theme.ui(10, .bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Theme.panel)
                        .clipShape(Capsule())
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(isYearly ? Theme.accent : Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func bigButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.ui(15, .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
