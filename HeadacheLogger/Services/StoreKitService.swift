import Foundation
import StoreKit

enum StoreError: Error {
    case failedVerification
}

enum PurchaseOutcome {
    case purchased
    case cancelled
    case pending
}

/// On-device entitlement state for Pro. No accounts, no servers — StoreKit 2 handles everything.
///
/// Two products unlock the same Pro entitlement:
/// - `com.jackwallner.headachelogger.pro.yearly` — auto-renewable annual subscription with 7-day free trial.
/// - `com.jackwallner.headachelogger.pro.lifetime` — one-time non-consumable.
@MainActor
final class StoreKitService: ObservableObject {
    nonisolated static let monthlyProductId = "com.jackwallner.headachelogger.pro.monthly"
    nonisolated static let yearlyProductId = "com.jackwallner.headachelogger.pro.yearly"
    nonisolated static let lifetimeProductId = "com.jackwallner.headachelogger.pro.lifetime"
    nonisolated static let allProProductIds: Set<String> = [monthlyProductId, yearlyProductId, lifetimeProductId]

    @Published private(set) var isProUnlocked: Bool = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var activeProductId: String?
    @Published var lastError: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = listenForTransactionUpdates()
        Task {
            await refresh()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductId }
    }

    var yearlyProduct: Product? {
        products.first { $0.id == Self.yearlyProductId }
    }

    var lifetimeProduct: Product? {
        products.first { $0.id == Self.lifetimeProductId }
    }

    /// True when the active entitlement comes from an auto-renewable subscription.
    var hasSubscription: Bool {
        guard let active = activeProductId else { return false }
        return active == Self.monthlyProductId || active == Self.yearlyProductId
    }

    /// Public helper for previews and tests only.
    func setProUnlockedForPreview(_ unlocked: Bool, productId: String? = nil) {
        isProUnlocked = unlocked
        activeProductId = unlocked ? (productId ?? Self.yearlyProductId) : nil
    }

    func refresh() async {
        await fetchProducts()
        await updateEntitlement()
    }

    func fetchProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        lastError = nil
        do {
            products = try await Product.products(for: Array(Self.allProProductIds))
        } catch {
            lastError = "Could not load purchase: \(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        lastError = nil
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateEntitlement()
            await transaction.finish()
            return .purchased
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }

    func restorePurchases() async {
        lastError = nil
        do {
            try await AppStore.sync()
            await updateEntitlement()
        } catch {
            lastError = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func updateEntitlement() async {
        var unlocked = false
        var active: String?
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.allProProductIds.contains(transaction.productID),
               transaction.revocationDate == nil {
                unlocked = true
                // Prefer yearly > monthly > lifetime when multiple entitlements coexist.
                if active == nil
                    || transaction.productID == Self.yearlyProductId
                    || (active == Self.lifetimeProductId && transaction.productID != Self.lifetimeProductId) {
                    active = transaction.productID
                }
            }
        }
        isProUnlocked = unlocked
        activeProductId = active
    }

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                switch result {
                case .verified(let transaction):
                    await self.updateEntitlement()
                    await transaction.finish()
                case .unverified(let transaction, let error):
                    // Finish even if verification failed so StoreKit stops redelivering it.
                    #if DEBUG
                    print("Transaction unverified: \(error)")
                    #endif
                    await transaction.finish()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}
