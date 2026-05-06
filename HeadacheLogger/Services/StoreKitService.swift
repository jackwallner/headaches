import Foundation
import StoreKit

enum StoreError: Error {
    case failedVerification
}

/// On-device entitlement state for Pro. No accounts, no servers — StoreKit 2 handles everything.
///
/// Two products unlock the same Pro entitlement:
/// - `com.jackwallner.headachelogger.pro.yearly` — auto-renewable annual subscription with 7-day free trial.
/// - `com.jackwallner.headachelogger.pro.lifetime` — one-time non-consumable.
@MainActor
final class StoreKitService: ObservableObject {
    static let yearlyProductId = "com.jackwallner.headachelogger.pro.yearly"
    static let lifetimeProductId = "com.jackwallner.headachelogger.pro.lifetime"
    static let allProProductIds: Set<String> = [yearlyProductId, lifetimeProductId]

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

    var yearlyProduct: Product? {
        products.first { $0.id == Self.yearlyProductId }
    }

    var lifetimeProduct: Product? {
        products.first { $0.id == Self.lifetimeProductId }
    }

    /// True when the active entitlement comes from the auto-renewable subscription.
    var hasSubscription: Bool {
        activeProductId == Self.yearlyProductId
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

    func purchase(_ product: Product) async throws -> Bool {
        lastError = nil
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateEntitlement()
            await transaction.finish()
            return true
        case .userCancelled:
            return false
        case .pending:
            return false
        @unknown default:
            return false
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
                // Prefer subscription as the "active" surface when both somehow coexist;
                // lifetime overrides only if subscription is gone.
                if active == nil || transaction.productID == Self.yearlyProductId {
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
                    print("Transaction unverified: \(error)")
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
