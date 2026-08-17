import Foundation
import os
import StoreKit
@preconcurrency import RevenueCat

enum HeadacheProProduct {
    static let lifetime = "com.jackwallner.headachelogger"
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

enum StoreServiceError: Error {
    case productUnavailable
    case verificationFailed
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

    /// Display order for the paywall: yearly first (default), then monthly, then
    /// lifetime. The direct trial path uses monthly, while the full picker still
    /// leads with yearly.
    /// Monthly is the "I want to think about it" option, lifetime is the alternative
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
    /// One-tap conversion target for the onboarding trial step: the monthly package.
    ///
    /// Monthly, not yearly, and this is deliberate. Onboarding and the paywall serve
    /// two different people: whoever taps through onboarding has not used the app yet
    /// and is reacting to the recurring number on Apple's sheet, while whoever opens
    /// the paywall later has already decided the app is worth paying for. So the
    /// smaller recurring figure is what starts the trial here, and the paywall still
    /// leads with yearly. Both plans carry the same 7-day free trial, so nothing is
    /// lost by starting on monthly.
    ///
    /// Bought directly (trial when eligible); the full `PaywallView` is only the
    /// fallback when this is nil (products not loaded).
    var onboardingTrialPackage: Package? { monthlyPackage }

    /// CTA label for the onboarding one-tap conversion. Leads with the free-trial offer
    /// when the user is eligible, price-forward otherwise so the price is never
    /// hidden (Apple 3.1.2 — nothing implies Pro is free forever).
    var onboardingCTALabel: String {
        guard let package = onboardingTrialPackage else { return "Unlock Headache Pro" }
        if isEligibleForIntroOffer(package), let trial = package.headacheProIntroOfferLabel {
            return "Start \(trial)"
        }
        return "Unlock Headache Pro for \(package.storeProduct.localizedPriceString)"
    }

    /// Full Apple-3.1.2 auto-renew disclosure for the onboarding CTA. States trial
    /// length (when eligible), then the real price from the loaded package, then
    /// auto-renew and how to cancel.
    ///
    /// Reads from `onboardingTrialPackage` for the same reason the button buys it:
    /// the disclosure must name the plan the tap actually charges. Quoting a yearly
    /// amount over a monthly purchase would misstate the charge (3.1.2) and invite
    /// refunds. Returns nil until the package loads so no placeholder price is ever
    /// rendered.
    var onboardingCTADisclosureText: String? {
        guard let package = onboardingTrialPackage else { return nil }
        let renew = "Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions."
        if isEligibleForIntroOffer(package), let trial = package.headacheProIntroOfferLabel {
            return "\(trial.capitalized), then \(package.headacheProPriceLabel). \(renew)"
        }
        return "\(package.headacheProPriceLabel). \(renew)"
    }

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
    /// False until an *explicit* `customerInfo()` fetch completes (the forced-network
    /// `.fetchCurrent` call in `start()`). Promotional sheets must wait on this so a Pro user
    /// is never pitched during the launch window. Deliberately NOT set by the delegate's
    /// initial push: that push can carry a stale/cached non-Pro `CustomerInfo`, and flipping
    /// this true on it let the Pro-intro sheet present (then get yanked when the authoritative
    /// result arrived) — a blank sheet flashing on every cold launch for returning Pro users.
    @Published private(set) var hasResolvedEntitlements: Bool = false
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

    /// True when the account shows any sign of current or recent Pro access: an active
    /// entitlement, a lifetime (non-subscription) purchase, or an entitlement that expired
    /// within the last 48 hours. Renewals (especially sandbox/TestFlight) and billing retry
    /// can read "not Pro" authoritatively for a beat right before the renewed entitlement
    /// lands — presenting a promo inside that window gets the sheet yanked before layout,
    /// which is the blank-sheet flash. Promo surfaces treat these accounts as Pro and stay quiet.
    var hasRecentOrActiveProSignal: Bool {
        guard let info = customerInfo else { return false }
        if info.hasHeadacheProEntitlement { return true }
        if !info.nonSubscriptions.isEmpty { return true }
        let cutoff = Date(timeIntervalSinceNow: -48 * 3600)
        return info.entitlements.all.values.contains { entitlement in
            entitlement.isActive || (entitlement.expirationDate.map { $0 > cutoff } ?? false)
        }
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
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        #if targetEnvironment(simulator)
        await fetchSimulatorProducts()
        #else
        configureIfNeeded()
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
        #endif
    }

    @discardableResult
    func purchase(_ package: Package) async throws -> PurchaseState {
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        #if targetEnvironment(simulator)
        guard let product = package.storeProduct.sk2Product else {
            throw StoreServiceError.productUnavailable
        }
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw StoreServiceError.verificationFailed
            }
            await transaction.finish()
            isProUnlocked = true
            return .purchased
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
        #else
        configureIfNeeded()
        let result = try await Purchases.shared.purchase(package: package)
        apply(customerInfo: result.customerInfo)
        if result.userCancelled {
            return .cancelled
        } else if result.customerInfo.hasHeadacheProEntitlement {
            return .purchased
        } else {
            return .pending
        }
        #endif
    }

    func updateCustomerProductStatus(fetchPolicy: CacheFetchPolicy = .default) async {
        #if targetEnvironment(simulator)
        hasResolvedEntitlements = true
        lastError = nil
        #else
        configureIfNeeded()
        do {
            let info = try await Purchases.shared.customerInfo(fetchPolicy: fetchPolicy)
            apply(customerInfo: info)
            // This is an explicit fetch (network-backed on `.fetchCurrent`), so the Pro
            // status is now authoritative — only here do we let promo sheets unblock.
            hasResolvedEntitlements = true
            lastError = nil
        } catch {
            logger.error("Customer info refresh failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't refresh your subscription status. Check your connection and try again."
        }
        #endif
    }

    #if targetEnvironment(simulator)
    private func fetchSimulatorProducts() async {
        do {
            let storeProducts = try await Product.products(for: HeadacheProProduct.all)
            products = storeProducts.map { product in
                let storeProduct = StoreProduct(sk2Product: product)
                return Package(
                    identifier: product.id,
                    packageType: packageType(for: product.id),
                    storeProduct: storeProduct,
                    offeringIdentifier: "storekit-testing",
                    webCheckoutUrl: nil
                )
            }
            .sorted {
                if $0.headacheProPaywallSortIndex != $1.headacheProPaywallSortIndex {
                    return $0.headacheProPaywallSortIndex < $1.headacheProPaywallSortIndex
                }
                return $0.storeProduct.productIdentifier < $1.storeProduct.productIdentifier
            }
            introEligibility = Dictionary(
                uniqueKeysWithValues: products.compactMap { package in
                    guard package.storeProduct.introductoryDiscount != nil else { return nil }
                    return (package.storeProduct.productIdentifier, true)
                }
            )
            currentOffering = nil
            lastError = products.isEmpty ? "StoreKit Testing products are unavailable." : nil
        } catch {
            logger.error("StoreKit Testing product fetch failed: \(String(describing: error), privacy: .public)")
            products = []
            introEligibility = [:]
            lastError = "Couldn't load StoreKit Testing products."
        }
    }

    private func packageType(for productID: String) -> PackageType {
        switch productID {
        case HeadacheProProduct.yearly:
            return .annual
        case HeadacheProProduct.monthly:
            return .monthly
        case HeadacheProProduct.lifetime:
            return .lifetime
        default:
            return .custom
        }
    }
    #endif

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
        #if targetEnvironment(simulator)
        return
        #else
        configureIfNeeded()
        if AppEnvironment.isUITesting { return }
        if oncePerSession {
            guard !paywallImpressionsThisSession.contains(id) else { return }
            paywallImpressionsThisSession.insert(id)
        }
        Purchases.shared.trackCustomPaywallImpression(
            CustomPaywallImpressionParams(paywallId: id)
        )
        #endif
    }

    func restorePurchases() async {
        lastError = nil
        #if targetEnvironment(simulator)
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               HeadacheProProduct.all.contains(transaction.productID) {
                isProUnlocked = true
                return
            }
        }
        lastError = "No previous Headache Pro purchase was found on this Apple ID."
        #else
        configureIfNeeded()
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(customerInfo: info)
            lastError = isProUnlocked ? nil : "No previous Headache Pro purchase was found on this Apple ID."
        } catch {
            logger.error("Restore failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't restore purchases. Try again."
        }
        #endif
    }

    func apply(customerInfo: CustomerInfo) {
        self.customerInfo = customerInfo
        let hasPro = customerInfo.hasHeadacheProEntitlement
        if isProUnlocked != hasPro {
            isProUnlocked = hasPro
            logger.info("isProUnlocked updated to \(hasPro, privacy: .public)")
        }
        // `hasResolvedEntitlements` is intentionally NOT set here. The delegate's initial
        // push can deliver stale/cached info; promo gating waits on the explicit fetch in
        // `updateCustomerProductStatus` so it only ever acts on an authoritative result.
    }

    // MARK: - Private

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        #if targetEnvironment(simulator)
        return
        #else
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
        Purchases.shared.delegate = self
        isConfigured = true
        #endif
    }
}

extension StoreService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            StoreService.shared.apply(customerInfo: customerInfo)
        }
    }
}
