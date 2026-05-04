import Foundation
import StoreKit

enum StoreError: Error {
    case failedVerification
}

/// On-device entitlement state for Pro. No accounts, no servers — StoreKit 2 handles everything.
@MainActor
final class StoreKitService: ObservableObject {
    static let proProductId = "com.jackwallner.headachelogger.pro.lifetime"

    @Published private(set) var isProUnlocked: Bool = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts: Bool = false
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

    var proProduct: Product? {
        products.first { $0.id == Self.proProductId }
    }

    /// Public helper for previews and tests only.
    func setProUnlockedForPreview(_ unlocked: Bool) {
        isProUnlocked = unlocked
    }

    func refresh() async {
        await fetchProducts()
        await updateEntitlement()
    }

    func fetchProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: [Self.proProductId])
        } catch {
            lastError = "Could not load purchase: \(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async throws -> Bool {
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
        do {
            try await AppStore.sync()
            await updateEntitlement()
        } catch {
            lastError = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func updateEntitlement() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductId,
               transaction.revocationDate == nil {
                unlocked = true
            }
        }
        isProUnlocked = unlocked
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
