import StoreKit
import SwiftUI

struct PaywallView: View {
    enum Plan: String, CaseIterable, Identifiable {
        case monthly
        case yearly
        case lifetime
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: StoreKitService
    @State private var selectedPlan: Plan = .yearly
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var purchaseError: String?
    @State private var purchaseMessage: String?
    @State private var restoreMessage: String?
    @State private var showSuccess = false
    @State private var showAlertSetup = false

    private let privacyURL = URL(string: "https://jackwallner.github.io/headaches/privacy-policy.html")
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    featureList
                    planPicker
                    purchaseSection
                    legalFooter
                }
                .padding(20)
            }
            .navigationTitle("Headache Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Purchase Issue", isPresented: errorBinding) {
                Button("OK", role: .cancel) { purchaseError = nil }
            } message: {
                Text(purchaseError ?? "")
            }
            .alert("Purchase Update", isPresented: messageBinding) {
                Button("OK", role: .cancel) { purchaseMessage = nil }
            } message: {
                Text(purchaseMessage ?? "")
            }
            .alert("Restore Purchases", isPresented: restoreBinding) {
                Button("OK", role: .cancel) { restoreMessage = nil }
            } message: {
                Text(restoreMessage ?? "")
            }
            .alert("Welcome to Headache Pro", isPresented: $showSuccess) {
                Button("Set Up Proactive Alerts") {
                    showAlertSetup = true
                }
                Button("Done", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("Your access is active. Turn on Proactive Alerts now so the app can warn you before pressure drops or AQI spikes.")
            }
            .sheet(isPresented: $showAlertSetup, onDismiss: { dismiss() }) {
                NavigationStack {
                    ProAlertsConfigView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    showAlertSetup = false
                                }
                            }
                        }
                }
            }
            .task {
                ensureValidSelection()
            }
            .onChange(of: store.products.count) { _, _ in
                ensureValidSelection()
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { purchaseError != nil },
            set: { if !$0 { purchaseError = nil } }
        )
    }

    private var messageBinding: Binding<Bool> {
        Binding(
            get: { purchaseMessage != nil },
            set: { if !$0 { purchaseMessage = nil } }
        )
    }

    private var restoreBinding: Binding<Bool> {
        Binding(
            get: { restoreMessage != nil },
            set: { if !$0 { restoreMessage = nil } }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(brandColor)
            Text("Get a heads-up before headache weather")
                .font(.title2.bold())
            Text("Headache Pro is built around Proactive Alerts: background forecast checks for pressure drops and AQI spikes, plus personalized patterns from the headaches you already log.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 16) {
            FeatureRow(
                icon: "bell.badge.fill",
                title: "Proactive headache-weather alerts",
                detail: "Get notified before sharp pressure drops or AQI spikes are forecast near you."
            )
            FeatureRow(
                icon: "slider.horizontal.3",
                title: "Sensitivity and quiet hours",
                detail: "Tune alert thresholds and keep overnight notifications muted."
            )
            FeatureRow(
                icon: "chart.bar.xaxis",
                title: "Personalized pattern insights",
                detail: "See which conditions your logged headaches cluster around — sleep, pressure, time of day, weather."
            )
            FeatureRow(
                icon: "lock.shield",
                title: "Stays on your device",
                detail: "No accounts, no servers. Apple handles billing; your settings and data stay local."
            )
        }
    }

    @ViewBuilder
    private var planPicker: some View {
        if store.isLoadingProducts && store.products.isEmpty {
            HStack {
                ProgressView()
                Text("Loading purchase options…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
        } else if store.monthlyProduct == nil && store.yearlyProduct == nil && store.lifetimeProduct == nil {
            VStack(spacing: 8) {
                Text("Unable to load purchase options right now.")
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await store.refresh() }
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 12) {
                if let monthly = store.monthlyProduct {
                    PlanCard(
                        title: "Monthly",
                        price: monthly.displayPrice + " / month",
                        badge: nil,
                        subtitle: "Auto-renews. Cancel anytime in Settings.",
                        isSelected: selectedPlan == .monthly,
                        accent: brandColor
                    ) {
                        selectedPlan = .monthly
                    }
                }
                if let yearly = store.yearlyProduct {
                    PlanCard(
                        title: "Yearly",
                        price: yearly.displayPrice + " / year",
                        badge: trialBadge(for: yearly),
                        subtitle: yearlySubtitle(for: yearly),
                        isSelected: selectedPlan == .yearly,
                        accent: brandColor
                    ) {
                        selectedPlan = .yearly
                    }
                }
                if let lifetime = store.lifetimeProduct {
                    PlanCard(
                        title: "Lifetime",
                        price: lifetime.displayPrice,
                        badge: "One-time",
                        subtitle: "Pay once, unlock forever. No subscription.",
                        isSelected: selectedPlan == .lifetime,
                        accent: brandColor
                    ) {
                        selectedPlan = .lifetime
                    }
                }
            }
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            Button {
                guard let product = resolvedProduct else { return }
                Task { await purchase(product) }
            } label: {
                HStack {
                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text(primaryButtonTitle)
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(brandColor, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .disabled(resolvedProduct == nil || isPurchasing || isRestoring)

            Button {
                Task { await restore() }
            } label: {
                HStack {
                    if isRestoring {
                        ProgressView()
                    } else {
                        Text("Restore Purchases")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .disabled(isPurchasing || isRestoring)

            subscriptionDisclosure
        }
    }

    @ViewBuilder
    private var subscriptionDisclosure: some View {
        switch selectedPlan {
        case .monthly:
            Text("Payment is charged to your Apple ID at confirmation. The subscription auto-renews monthly at the listed price unless cancelled at least 24 hours before the renewal date. Manage or cancel any time in iPhone Settings → Apple ID → Subscriptions.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        case .yearly:
            VStack(spacing: 4) {
                if let yearly = store.yearlyProduct, hasFreeTrial(yearly) {
                    Text("After the 7-day free trial, this subscription automatically renews as a paid subscription.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Text("Payment is charged to your Apple ID at confirmation. The subscription auto-renews yearly at the listed price unless cancelled at least 24 hours before the renewal date. Manage or cancel any time in iPhone Settings → Apple ID → Subscriptions.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)
        case .lifetime:
            Text("One-time purchase. No subscription, no auto-renewal.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    private var legalFooter: some View {
        HStack(spacing: 12) {
            if let privacyURL {
                Button("Privacy Policy") { openURL(privacyURL) }
            }
            if let termsURL {
                Button("Terms of Use") { openURL(termsURL) }
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var activeProduct: Product? {
        switch selectedPlan {
        case .monthly: return store.monthlyProduct
        case .yearly: return store.yearlyProduct
        case .lifetime: return store.lifetimeProduct
        }
    }

    private var activePlan: Plan? {
        if activeProduct != nil { return selectedPlan }
        return firstAvailablePlan
    }

    private var resolvedProduct: Product? {
        guard let activePlan else { return nil }
        switch activePlan {
        case .monthly: return store.monthlyProduct
        case .yearly: return store.yearlyProduct
        case .lifetime: return store.lifetimeProduct
        }
    }

    private var firstAvailablePlan: Plan? {
        if store.yearlyProduct != nil { return .yearly }
        if store.monthlyProduct != nil { return .monthly }
        if store.lifetimeProduct != nil { return .lifetime }
        return nil
    }

    private var primaryButtonTitle: String {
        guard let product = resolvedProduct, let activePlan else { return "Unavailable" }
        switch activePlan {
        case .monthly:
            return "Subscribe — \(product.displayPrice)/month"
        case .yearly:
            return "Continue — \(product.displayPrice)/year"
        case .lifetime:
            return "Buy Lifetime — \(product.displayPrice)"
        }
    }

    private func trialBadge(for product: Product) -> String? {
        hasFreeTrial(product) ? "Trial if eligible" : nil
    }

    private func hasFreeTrial(_ product: Product) -> Bool {
        guard let intro = product.subscription?.introductoryOffer else { return false }
        return intro.paymentMode == .freeTrial
    }

    private func yearlySubtitle(for product: Product) -> String {
        if hasFreeTrial(product) {
            return "Apple confirms trial eligibility before purchase. Auto-renews; cancel anytime in Settings."
        }
        return "Auto-renews. Cancel anytime in Settings."
    }

    private func ensureValidSelection() {
        if activeProduct == nil, let fallback = firstAvailablePlan {
            selectedPlan = fallback
        }
    }

    private var brandColor: Color { Color(red: 0.95, green: 0.25, blue: 0.36) }

    private func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let outcome = try await store.purchase(product)
            switch outcome {
            case .purchased:
                showSuccess = true
            case .cancelled:
                purchaseMessage = "Purchase cancelled. Nothing was charged."
            case .pending:
                purchaseMessage = "Purchase pending. We'll unlock Headache Pro automatically if Apple approves it."
            }
        } catch StoreError.failedVerification {
            purchaseError = "Apple couldn't verify the purchase. Please try Restore Purchases or contact support."
        } catch {
            purchaseError = "Purchase could not be completed. Please check your connection and try again."
        }
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        await store.restorePurchases()
        if store.isProUnlocked {
            showSuccess = true
        } else if store.lastError == nil {
            restoreMessage = "No previous Headache Pro purchase was found on this Apple ID."
        } else {
            restoreMessage = store.lastError
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.36))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PlanCard: View {
    let title: String
    let price: String
    let badge: String?
    let subtitle: String
    let isSelected: Bool
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? accent : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(accent)
                        }
                        Spacer()
                        Text(price).font(.subheadline.weight(.semibold))
                    }
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? accent : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
