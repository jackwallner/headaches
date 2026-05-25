import Foundation
import os
@preconcurrency import RevenueCat

enum HeadacheProProduct {
    static let lifetime = "com.jackwallner.headachelogger.pro.lifetime"
    static let yearly = "com.jackwallner.headachelogger.pro.yearly"
    static let monthly = "com.jackwallner.headachelogger.pro.monthly"
    static let all: [String] = [lifetime, yearly, monthly]
}

enum RevenueCatConfig {
    static let apiKey = "appl_JEymooxJJAUzljQhVzWPIQKFMBb"
    static let proEntitlement = "HeadachePro"
    static let fallbackEntitlement = "pro"
}

enum PurchaseState {
    case purchased
    case cancelled
    case pending
}

enum HeadacheProPackageKind: Int {
    case lifetime = 0
    case yearly = 1
    case monthly = 2
    case other = 3
}

extension HeadacheProPackageKind {
    init(package: Package) {
        switch package.packageType {
        case .lifetime:
            self = .lifetime
        case .annual:
            self = .yearly
        case .monthly:
            self = .monthly
        default:
            let identifiers = [package.identifier, package.storeProduct.productIdentifier].map { $0.lowercased() }
            if identifiers.contains(where: { $0.contains("lifetime") }) {
                self = .lifetime
            } else if identifiers.contains(where: { $0.contains("yearly") || $0.contains("annual") }) {
                self = .yearly
            } else if identifiers.contains(where: { $0.contains("monthly") }) {
                self = .monthly
            } else {
                self = .other
            }
        }
    }
}

extension Package {
    var headacheProPackageKind: HeadacheProPackageKind {
        HeadacheProPackageKind(package: self)
    }

    var headacheProDisplayName: String {
        switch headacheProPackageKind {
        case .lifetime:
            return "Lifetime"
        case .yearly:
            return "Yearly"
        case .monthly:
            return "Monthly"
        case .other:
            return storeProduct.localizedTitle
        }
    }

    /// Display order for the paywall: yearly first (default + trial), then monthly,
    /// then lifetime. Conversion-optimized — the trial path is what most users buy,
    /// monthly is the "I want to think about it" option, lifetime is the alternative
    /// for people who refuse subscriptions outright.
    var headacheProPaywallSortIndex: Int {
        switch headacheProPackageKind {
        case .yearly:   return 0
        case .monthly:  return 1
        case .lifetime: return 2
        case .other:    return 3
        }
    }

    /// Per-month price for the yearly plan, formatted in the product's locale/currency.
    /// Returns nil for non-yearly packages.
    var headacheProMonthlyEquivalentLabel: String? {
        guard headacheProPackageKind == .yearly else { return nil }
        let monthly = (storeProduct.price as NSDecimalNumber)
            .dividing(by: NSDecimalNumber(value: 12))
        if let formatter = storeProduct.priceFormatter,
           let formatted = formatter.string(from: monthly) {
            return formatted
        }
        let fallback = NumberFormatter()
        fallback.numberStyle = .currency
        fallback.currencyCode = storeProduct.currencyCode
        return fallback.string(from: monthly)
    }

    var headacheProPriceLabel: String {
        guard let period = storeProduct.subscriptionPeriod else { return storeProduct.localizedPriceString }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        if period.value == 1 {
            return "\(storeProduct.localizedPriceString) / \(unit)"
        } else {
            return "\(storeProduct.localizedPriceString) / \(period.value) \(unit)"
        }
    }

    var headacheProIntroOfferLabel: String? {
        guard let intro = storeProduct.introductoryDiscount, intro.paymentMode == .freeTrial else {
            return nil
        }
        let period = intro.subscriptionPeriod
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        if period.unit == .week {
            return "\(period.value * 7)-day free trial"
        } else {
            return "\(period.value)-\(unit.dropLast(period.value == 1 ? 0 : 1)) free trial"
        }
    }
}

extension CustomerInfo {
    var hasHeadacheProEntitlement: Bool {
        !entitlements.active.isEmpty
    }
}

extension StoreService {
    /// Percent savings of the yearly plan compared to 12× the monthly plan. Returns
    /// nil unless both packages are available and yearly is actually cheaper.
    var yearlySavingsPercent: Int? {
        guard let yearly = yearlyPackage, let monthly = monthlyPackage else { return nil }
        let yearlyPrice = yearly.storeProduct.price as NSDecimalNumber
        let monthlyAnnualized = (monthly.storeProduct.price as NSDecimalNumber)
            .multiplying(by: NSDecimalNumber(value: 12))
        guard monthlyAnnualized.doubleValue > 0 else { return nil }
        let savings = monthlyAnnualized.subtracting(yearlyPrice).doubleValue
            / monthlyAnnualized.doubleValue
        let percent = Int((savings * 100).rounded())
        return percent > 0 ? percent : nil
    }
}

extension Offering {
    var headacheProSortedPackages: [Package] {
        availablePackages.sorted {
            if $0.headacheProPaywallSortIndex != $1.headacheProPaywallSortIndex {
                return $0.headacheProPaywallSortIndex < $1.headacheProPaywallSortIndex
            }
            return $0.storeProduct.productIdentifier < $1.storeProduct.productIdentifier
        }
    }
}

extension Offerings {
    var headacheProPaywallOffering: Offering? {
        offering(identifier: "default") ?? current
    }
}

@MainActor
final class StoreService: NSObject, ObservableObject {
    static let shared = StoreService()

    @Published private(set) var products: [Package] = []
    @Published private(set) var currentOffering: Offering?
    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var isProUnlocked: Bool = false
    @Published private(set) var purchaseInFlight: Bool = false
    @Published private(set) var isLoadingProducts: Bool = false
    @Published var lastError: String?

    /// Per-product intro-offer eligibility. Populated with `fetchProducts` so the
    /// native paywall only advertises trials users will actually receive (Apple 3.1.2).
    @Published private(set) var introEligibility: [String: Bool] = [:]

    var activeProductId: String? {
        customerInfo?.entitlements.active.first?.key
    }

    var monthlyPackage: Package? {
        products.first { $0.headacheProPackageKind == .monthly }
    }

    var yearlyPackage: Package? {
        products.first { $0.headacheProPackageKind == .yearly }
    }

    var lifetimePackage: Package? {
        products.first { $0.headacheProPackageKind == .lifetime }
    }

    /// True when Pro is unlocked via an auto-renewable subscription (not lifetime).
    var hasSubscription: Bool {
        guard let info = customerInfo else { return false }
        return info.entitlements.active.values.contains { entitlement in
            let id = entitlement.productIdentifier
            return id == HeadacheProProduct.yearly || id == HeadacheProProduct.monthly
        }
    }

    private let logger = Logger(subsystem: "com.jackwallner.headachelogger", category: "Store")
    private var isConfigured = false
    private var paywallImpressionsThisSession: Set<String> = []

    private override init() {}

    func start() {
        configureIfNeeded()
        Task { await updateCustomerProductStatus(fetchPolicy: .fetchCurrent) }
        Task { await fetchProducts() }
    }

    func fetchProducts() async {
        configureIfNeeded()
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let offerings = try await Purchases.shared.offerings()
            let offering = offerings.headacheProPaywallOffering
            currentOffering = offering
            products = offering?.headacheProSortedPackages ?? []
            lastError = nil
            await refreshIntroEligibility()
        } catch {
            logger.error("Product fetch failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't load purchase options. Check your connection and try again."
        }
    }

    @discardableResult
    func purchase(_ package: Package) async throws -> PurchaseState {
        configureIfNeeded()
        purchaseInFlight = true
        defer { purchaseInFlight = false }

        let result = try await Purchases.shared.purchase(package: package)
        apply(customerInfo: result.customerInfo)
        if result.userCancelled {
            return .cancelled
        } else if result.customerInfo.hasHeadacheProEntitlement {
            return .purchased
        } else {
            return .pending
        }
    }

    func updateCustomerProductStatus(fetchPolicy: CacheFetchPolicy = .default) async {
        configureIfNeeded()
        do {
            let info = try await Purchases.shared.customerInfo(fetchPolicy: fetchPolicy)
            apply(customerInfo: info)
            lastError = nil
        } catch {
            logger.error("Customer info refresh failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't refresh your subscription status. Check your connection and try again."
        }
    }

    private func refreshIntroEligibility() async {
        let identifiers = products
            .filter { $0.storeProduct.introductoryDiscount != nil }
            .map(\.storeProduct.productIdentifier)
        guard !identifiers.isEmpty else {
            introEligibility = [:]
            return
        }
        let result = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: identifiers)
        introEligibility = result.mapValues { $0.status == .eligible }
    }

    /// True when this package has a free-trial intro offer and the user is eligible.
    func isEligibleForIntroOffer(_ package: Package) -> Bool {
        guard package.headacheProIntroOfferLabel != nil else { return false }
        return introEligibility[package.storeProduct.productIdentifier] ?? false
    }

    /// Reports a custom paywall impression to RevenueCat (required for native paywalls).
    func trackPaywallImpression(id: String, oncePerSession: Bool = false) {
        configureIfNeeded()
        if AppEnvironment.isUITesting { return }
        if oncePerSession {
            guard !paywallImpressionsThisSession.contains(id) else { return }
            paywallImpressionsThisSession.insert(id)
        }
        Purchases.shared.trackCustomPaywallImpression(
            CustomPaywallImpressionParams(paywallId: id)
        )
    }

    func restorePurchases() async {
        configureIfNeeded()
        lastError = nil
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(customerInfo: info)
            lastError = isProUnlocked ? nil : "No previous Headache Pro purchase was found on this Apple ID."
        } catch {
            logger.error("Restore failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't restore purchases. Try again."
        }
    }

    func apply(customerInfo: CustomerInfo) {
        self.customerInfo = customerInfo
        let hasPro = customerInfo.hasHeadacheProEntitlement
        if isProUnlocked != hasPro {
            isProUnlocked = hasPro
            logger.info("isProUnlocked updated to \(hasPro, privacy: .public)")
        }
    }

    // MARK: - Private

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
        Purchases.shared.delegate = self
        isConfigured = true
    }
}

extension StoreService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            StoreService.shared.apply(customerInfo: customerInfo)
        }
    }
}
