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

    private let paywallFeatures: [(icon: String, title: String)] = [
        ("bell.badge.fill", "12-24h warnings: heads-up before pressure and AQI shift"),
        ("chart.bar.xaxis", "Personal triggers: patterns from your sleep and weather"),
        ("waveform.path.ecg", "Daily risk forecast: tomorrow's score from your own data")
    ]

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if store.isLoadingProducts && store.products.isEmpty {
                loadingState
            } else if store.products.isEmpty {
                emptyState
            } else {
                paywallContent
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
            Spacer()
            ProgressView()
            Text("Loading plans…")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            legalFooter
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
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
            Spacer()
            legalFooter
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity)
    }

    /// Single viewport — warning hero, compact benefits, plans, and CTA together.
    private var paywallContent: some View {
        VStack(spacing: 12) {
            header
            compactFeatureList
            planCards
            Spacer(minLength: 0)
            purchaseSection
        }
        .padding(.horizontal, 22)
        .padding(.top, displayCloseButton ? 44 : 20)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity)
    }

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(brandColor.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(brandColor)
            }
            Text("Know before the headache hits")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
            Text("Unlock every Headache Pro feature. Private, on-device, no accounts.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
        }
    }

    private var compactFeatureList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(paywallFeatures, id: \.title) { feature in
                HStack(spacing: 12) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(brandColor)
                        .frame(width: 24)
                    Text(feature.title)
                        .font(.subheadline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var planCards: some View {
        VStack(spacing: 8) {
            ForEach(store.products, id: \.identifier) { package in
                PaywallPlanCard(
                    package: package,
                    isSelected: selectedPackage?.identifier == package.identifier,
                    showsTrialBadge: store.isEligibleForIntroOffer(package),
                    isRecommended: package.headacheProPackageKind == .yearly,
                    monthlyEquivalent: package.headacheProMonthlyEquivalentLabel,
                    savingsPercent: package.headacheProPackageKind == .yearly ? store.yearlySavingsPercent : nil,
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .opacity(isPurchasing ? 0 : 1)
                    if isPurchasing {
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(brandColor, in: Capsule())
                .shadow(color: brandColor.opacity(0.25), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || selectedPackage == nil)

            Text(trustLine ?? " ")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(minHeight: 20)
                .opacity(trustLine == nil ? 0 : 1)
                .accessibilityHidden(trustLine == nil)

            Text(disclosureText ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.9)
                .frame(minHeight: 64, alignment: .top)
                .opacity(disclosureText == nil ? 0 : 1)
                .accessibilityHidden(disclosureText == nil)

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

            legalFooter
        }
    }

    /// Restore + legal links — required on every paywall state (Apple 3.1.2).
    private var legalFooter: some View {
        VStack(spacing: 8) {
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
        return "Subscribe Now"
    }

    /// Short, high-trust microcopy directly under the CTA. Distinct from the
    /// Apple-required disclosure (which still appears below).
    private var trustLine: String? {
        guard let package = selectedPackage else { return nil }
        switch package.headacheProPackageKind {
        case .lifetime:
            return "One-time payment. No subscription."
        case .yearly, .monthly, .other:
            if store.isEligibleForIntroOffer(package) {
                return "No charge today."
            }
            return nil
        }
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
        #if DEBUG
        if let mode = PaywallScreenshotMode.current, !store.products.isEmpty {
            switch mode {
            case .monthly:
                selectedPackage = store.products.first { $0.headacheProPackageKind == .monthly }
            case .lifetime:
                selectedPackage = store.products.first { $0.headacheProPackageKind == .lifetime }
            case .yearly, .trial:
                selectedPackage = store.products.first { $0.headacheProPackageKind == .yearly }
            }
            return
        }
        #endif
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
    let isRecommended: Bool
    let monthlyEquivalent: String?
    let savingsPercent: Int?
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? accent : Color.secondary.opacity(0.35), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(accent)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(package.headacheProDisplayName)
                            .font(.subheadline.bold())
                            .layoutPriority(1)
                        // One badge only: dual pills truncate on compact widths.
                        if isRecommended {
                            Text("BEST VALUE")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accent, in: Capsule())
                                .fixedSize()
                        } else if let savingsPercent {
                            Text("SAVE \(savingsPercent)%")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accent.opacity(0.14), in: Capsule())
                                .fixedSize()
                        }
                    }
                    HStack(spacing: 6) {
                        if showsTrialBadge, let trial = package.headacheProIntroOfferLabel {
                            Text(trial.capitalized)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(accent)
                                .lineLimit(1)
                        } else if package.headacheProPackageKind == .lifetime {
                            Text("One-time purchase")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if isRecommended, let savingsPercent {
                            if showsTrialBadge || package.headacheProPackageKind == .lifetime {
                                Text("·")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            Text("Save \(savingsPercent)%")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(package.headacheProPriceLabel)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if let monthlyEquivalent {
                        Text("\(monthlyEquivalent)/mo")
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
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
