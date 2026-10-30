import Foundation
import StoreKit

/// StoreKit 2:訂閱管理(月/年),3 天免費試用由 App Store 的 introductory offer 處理
@MainActor
final class Store: ObservableObject {
    static let shared = Store()
    static let monthly = "io.xoio.ocpass.relay.monthly"
    static let yearly = "io.xoio.ocpass.relay.yearly"

    @Published var products: [Product] = []
    @Published var subscribed = false
    @Published var loading = false
    @Published var error: String?
    /// 正在進行的購買(商品 id),用來在 UI 顯示 spinner 並避免重複點擊
    @Published var purchasingProductID: String?

    private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await _ in Transaction.updates {
                await self?.refreshEntitlement()
            }
        }
    }

    deinit { updates?.cancel() }

    func load() async {
        loading = true
        error = nil
        do {
            let list = try await Product.products(for: [Self.monthly, Self.yearly])
            // 月在前、年在後
            products = list.sorted {
                ($0.id == Self.monthly ? 0 : 1) < ($1.id == Self.monthly ? 0 : 1)
            }
            if products.isEmpty { error = L("找不到訂閱商品(可能還在 App Store Connect 審核設定中)") }
            await refreshEntitlement()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    func buy(_ product: Product) async {
        guard purchasingProductID == nil else { return }
        purchasingProductID = product.id
        error = nil
        defer { purchasingProductID = nil }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let tx):
                    await tx.finish()
                    await refreshEntitlement()
                case .unverified(_, let failure):
                    self.error = L("購買驗證失敗") + ": " + failure.localizedDescription
                }
            case .pending:
                // 家長同意 / SCA 之類需要外部授權:一定要讓使用者知道
                self.error = L("購買待處理:請依 Apple 提示完成授權後再回來")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            self.error = L("購買失敗") + ": " + error.localizedDescription
        }
    }

    func restore() async {
        loading = true
        try? await AppStore.sync()
        await refreshEntitlement()
        loading = false
    }

    func refreshEntitlement() async {
        var active = false
        var latestJWS: String?
        for await item in Transaction.currentEntitlements {
            guard case .verified(let tx) = item else { continue }
            guard tx.productID == Self.monthly || tx.productID == Self.yearly else { continue }
            if tx.revocationDate == nil, tx.expirationDate.map({ $0 > Date() }) ?? true {
                active = true
                latestJWS = item.jwsRepresentation
            }
        }
        subscribed = active
        if let jws = latestJWS { await pushEntitlement(jws) }
    }

    /// 把已驗證的交易交給 relay → 換成 1GB/月(伺服器會再向 Apple 驗一次)
    private func pushEntitlement(_ jws: String) async {
        guard let cred = RelayCredStore.load() else { return }
        guard let url = URL(string: "https://xoio.io/relay/entitle") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "channel": cred.channel, "secret": cred.secret, "jws": jws
        ])
        _ = try? await URLSession.shared.data(for: req)
    }

    /// 顯示用:每月價格字串
    func price(_ product: Product) -> String {
        product.displayPrice
    }
}
