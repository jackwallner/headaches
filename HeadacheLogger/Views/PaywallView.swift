import SwiftUI
@preconcurrency import RevenueCat

/// Legal URLs shared by the paywall and trial-offer sheet (Apple 3.1.2).
enum PaywallLinks {
    static let privacyPolicy = URL(string: "https://jackwallner.github.io/headaches/privacy-policy.html")!
    static let standardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

/// Native Headache Pro paywall. Purchases flow through `StoreService.purchase` →
/// `Purchases.shared.purchase` so RevenueCat records transactions and entitlements.
struct PaywallView: View {
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss

    var displayCloseButton: Bool = true

    @State private var selectedPackage: Package?
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var restoreMessage: String?
    @State private var isRestoring = false

    private var brandColor: Color { Color(red: 0.95, green: 0.25, blue: 0.36) }

    private var features: [(icon: String, title: String)] {
        [
            ("bell.badge.fill", "Proactive headache-weather alerts before pressure drops or AQI spikes"),
            ("slider.horizontal.3", "Tune alert sensitivity and quiet hours"),
            ("chart.bar.xaxis", "Personalized patterns from your logged headaches"),
            ("lock.shield", "All processing stays on your device")
        ]
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if store.isLoadingProducts && store.products.isEmpty {
                loadingState
            } else if store.products.isEmpty {
                emptyState
            } else {
                content
            }

            if displayCloseButton {
                closeButton
            }
        }
        .onChange(of: store.isProUnlocked) { _, isPro in
            if isPro { dismiss() }
        }
        .task {
            if store.products.isEmpty { await store.fetchProducts() }
            selectDefaultPackageIfNeeded()
        }
        .onChange(of: store.products.count) { _, _ in selectDefaultPackageIfNeeded() }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Loading plans…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Couldn't Load Plans")
                .font(.headline)
            Text(store.lastError ?? "Check your connection and try again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task {
                    await store.fetchProducts()
                    selectDefaultPackageIfNeeded()
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(brandColor)
        }
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                header
                featureList
                planCards
                purchaseSection
            }
            .padding(.horizontal, 24)
            .padding(.top, displayCloseButton ? 56 : 32)
            .padding(.bottom, 32)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(brandColor)
            Text("Headache Pro")
                .font(.title.bold())
            Text("Get a heads-up before headache weather, plus patterns from the logs you already keep.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(features, id: \.title) { feature in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: feature.icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(brandColor)
                        .frame(width: 24)
                    Text(feature.title)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var planCards: some View {
        VStack(spacing: 10) {
            ForEach(store.products, id: \.identifier) { package in
                PaywallPlanCard(
                    package: package,
                    isSelected: selectedPackage?.identifier == package.identifier,
                    showsTrialBadge: store.isEligibleForIntroOffer(package),
                    isBestValue: package.headacheProPackageKind == .yearly,
                    accent: brandColor
                ) {
                    selectedPackage = package
                }
            }
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            Button(action: startPurchase) {
                ZStack {
                    Text(ctaTitle)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .opacity(isPurchasing ? 0 : 1)
                    if isPurchasing {
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(brandColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || selectedPackage == nil)

            if let disclosure = disclosureText {
                Text(disclosure)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            if let restoreMessage {
                Text(restoreMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: startRestore) {
                Text(isRestoring ? "Restoring…" : "Restore Purchases")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isRestoring || isPurchasing)

            HStack(spacing: 4) {
                Link("Terms", destination: PaywallLinks.standardEULA)
                Text("·")
                Link("Privacy Policy", destination: PaywallLinks.privacyPolicy)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                        .padding(16)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var ctaTitle: String {
        guard let package = selectedPackage else { return "Continue" }
        if package.headacheProPackageKind == .lifetime { return "Unlock Lifetime" }
        if store.isEligibleForIntroOffer(package) { return "Start Free Trial" }
        return "Subscribe"
    }

    private var disclosureText: String? {
        guard let package = selectedPackage else { return nil }
        let price = package.headacheProPriceLabel
        if package.headacheProPackageKind == .lifetime {
            return "\(price). One-time purchase. Lifetime access, no subscription."
        }
        let renew = "Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings → Apple ID → Subscriptions."
        if store.isEligibleForIntroOffer(package), let trial = package.headacheProIntroOfferLabel {
            return "\(trial.capitalized), then \(price). \(renew)"
        }
        return "\(price). \(renew)"
    }

    private func selectDefaultPackageIfNeeded() {
        guard selectedPackage == nil, !store.products.isEmpty else { return }
        selectedPackage = store.products.first { $0.headacheProPackageKind == .yearly }
            ?? store.products.first
    }

    private func startPurchase() {
        guard let package = selectedPackage else { return }
        errorMessage = nil
        restoreMessage = nil
        isPurchasing = true
        Task { @MainActor in
            defer { isPurchasing = false }
            do {
                switch try await store.purchase(package) {
                case .purchased, .pending:
                    break
                case .cancelled:
                    errorMessage = "Purchase cancelled. Tap again to continue."
                }
            } catch {
                errorMessage = "Couldn't complete the purchase. Please try again."
            }
        }
    }

    private func startRestore() {
        errorMessage = nil
        restoreMessage = nil
        isRestoring = true
        Task { @MainActor in
            defer { isRestoring = false }
            await store.restorePurchases()
            if !store.isProUnlocked {
                restoreMessage = store.lastError ?? "No previous Headache Pro purchase was found on this Apple ID."
            }
        }
    }
}

private struct PaywallPlanCard: View {
    let package: Package
    let isSelected: Bool
    let showsTrialBadge: Bool
    let isBestValue: Bool
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? accent : Color.secondary.opacity(0.4), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(accent)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(package.headacheProDisplayName)
                            .font(.subheadline.bold())
                        if isBestValue {
                            Text("BEST VALUE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accent, in: Capsule())
                        }
                    }
                    if showsTrialBadge, let trial = package.headacheProIntroOfferLabel {
                        Text(trial.capitalized)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                }

                Spacer(minLength: 8)

                Text(package.headacheProPriceLabel)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? accent : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
