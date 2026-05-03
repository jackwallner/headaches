import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: StoreKitService
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var purchaseError: String?

    private let privacyURL = URL(string: "https://jackwallner.github.io/headaches/privacy-policy.html")
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    featureList
                    purchaseSection
                    legalFooter
                }
                .padding(20)
            }
            .navigationTitle("Pro")
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
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { purchaseError != nil },
            set: { if !$0 { purchaseError = nil } }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.36))
            Text("Get a heads-up before headache weather")
                .font(.title2.bold())
            Text("Pro turns on Proactive Alerts — a daily background check of your local forecast that taps you on the shoulder when conditions look risky.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 18) {
            FeatureRow(
                icon: "barometer",
                title: "Barometric pressure alerts",
                detail: "Get notified when a sharp pressure drop is forecast within the next 24 hours."
            )
            FeatureRow(
                icon: "aqi.medium",
                title: "Air quality alerts",
                detail: "Heads-up when the local US AQI is forecast to spike past your threshold."
            )
            FeatureRow(
                icon: "slider.horizontal.3",
                title: "Custom sensitivity & quiet hours",
                detail: "Set how big a pressure swing is worth a ping. Mute alerts at night."
            )
            FeatureRow(
                icon: "lock.shield",
                title: "Stays on your device",
                detail: "No accounts, no servers. Your purchase unlocks via Apple, your settings stay on your iPhone."
            )
        }
    }

    @ViewBuilder
    private var purchaseSection: some View {
        if let product = store.proProduct {
            VStack(spacing: 12) {
                Button {
                    Task { await purchase(product) }
                } label: {
                    HStack {
                        if isPurchasing {
                            ProgressView().tint(.white)
                        } else {
                            Text("Unlock Pro — \(product.displayPrice)")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color(red: 0.95, green: 0.25, blue: 0.36), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .disabled(isPurchasing || isRestoring)

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
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(isPurchasing || isRestoring)

                Text("One-time purchase. No subscription. Family Sharing not supported.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else if store.isLoadingProducts {
            HStack {
                ProgressView()
                Text("Loading purchase…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        } else {
            VStack(spacing: 8) {
                Text("Unable to load the purchase right now.")
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await store.refresh() }
                }
                Button("Restore Purchases") {
                    Task { await restore() }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var legalFooter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if let privacyURL {
                    Button("Privacy Policy") { openURL(privacyURL) }
                }
                if let termsURL {
                    Button("Terms of Use") { openURL(termsURL) }
                }
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let success = try await store.purchase(product)
            if success {
                dismiss()
            }
        } catch StoreError.failedVerification {
            purchaseError = "Apple couldn't verify the purchase. Please try Restore Purchases or contact support."
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        await store.restorePurchases()
        if store.isProUnlocked {
            dismiss()
        } else if store.lastError == nil {
            purchaseError = "No previous purchase was found on this Apple ID."
        } else {
            purchaseError = store.lastError
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
