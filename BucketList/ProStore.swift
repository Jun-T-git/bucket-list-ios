import SwiftUI
import StoreKit

// Owns the single in-app purchase: バケットリスト Pro, a one-time non-consumable
// that unlocks unlimited URL auto-import. StoreKit 2 only (iOS 17+).
//
// This type is the host app's source of truth for the entitlement. The Share
// Extension can't run StoreKit, so every time the entitlement is resolved we
// mirror it into the shared App Group suite (Storage.proEntitled) for the
// extension to read.
//
// Note on naming: `StoreKit.AppStore` (the StoreKit type) collides with this
// project's own `AppStore` model. References to the StoreKit one are fully
// qualified below so they don't resolve to the model by mistake.
@MainActor
final class ProStore: ObservableObject {
    static let productID = "teratech.BucketList.pro"

    /// Whether Pro is unlocked. Seeded from the App Group mirror so the UI is
    /// correct on launch before the StoreKit round-trip completes.
    @Published private(set) var isPro: Bool
    /// The loaded product (nil until loaded, or if it can't be fetched).
    @Published private(set) var product: Product?
    /// A purchase / restore is in flight — drives button spinners + disabled state.
    @Published private(set) var working = false
    /// User-facing message for a failed purchase/restore. Cleared on retry.
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        isPro = Storage.proEntitled
    }

    /// Start observing transactions and resolve the current entitlement. Call
    /// once at app launch.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = listenForTransactions()
        Task {
            await loadProduct()
            await refreshEntitlement()
        }
    }

    deinit { updatesTask?.cancel() }

    /// Locale-aware price string (e.g. "¥600"), or nil if the product hasn't loaded.
    var displayPrice: String? { product?.displayPrice }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            // Non-fatal: the paywall shows a friendly fallback if the product
            // didn't load (offline, or not yet configured in App Store Connect).
            product = nil
        }
    }

    /// Attempt the purchase. Returns true when Pro becomes unlocked.
    @discardableResult
    func purchase() async -> Bool {
        guard let product else {
            errorMessage = "製品情報を読み込めませんでした。通信環境をご確認のうえ、もう一度お試しください。"
            return false
        }
        errorMessage = nil
        working = true
        defer { working = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = "購入の確認ができませんでした。"
                    return false
                }
                await transaction.finish()
                setPro(true)
                return true
            case .userCancelled:
                return false
            case .pending:
                errorMessage = "購入は保留中です。承認されると自動的に反映されます。"
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = "購入を完了できませんでした。時間をおいて、もう一度お試しください。"
            return false
        }
    }

    /// Restore a previous purchase (e.g. on a new device or reinstall).
    func restore() async {
        errorMessage = nil
        working = true
        defer { working = false }
        // `sync()` triggers a StoreKit refresh; it can throw on cancel — ignore
        // and just re-resolve the entitlement below either way.
        try? await StoreKit.AppStore.sync()
        await refreshEntitlement()
        if !isPro {
            errorMessage = "復元できる購入が見つかりませんでした。"
        }
    }

    /// Recompute `isPro` from the current entitlements and mirror the result.
    func refreshEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        setPro(entitled)
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshEntitlement()
            }
        }
    }

    private func setPro(_ value: Bool) {
        if isPro != value { isPro = value }
        Storage.proEntitled = value   // mirror for the Share Extension
    }
}
