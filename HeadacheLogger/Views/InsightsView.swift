import Charts
import Charts
import SwiftData
import SwiftUI
import RevenueCatUI

struct InsightsView: View {
    @EnvironmentObject private var store: StoreService
    @Query(sort: \HeadacheEvent.timestamp, order: .reverse) private var events: [HeadacheEvent]
    @State private var showPaywall = false

    private var summary: InsightsEngine.Summary {
        InsightsEngine.summarize(events)
    }

    var body: some View {
        Group {
            if store.isProUnlocked {
                proContent
            } else {
                lockedTeaser
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            showPaywall = true
                        }
                    }
            }
        }
        .navigationTitle("Patterns")
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    @ViewBuilder
    private var proContent: some View {
        if events.count < InsightsEngine.minimumSampleSize {
            proLearningState(
                title: "Headache Pro is active",
                detail: "Proactive Alerts are ready now. Personalized patterns unlock after \(InsightsEngine.minimumSampleSize) logs — you have \(events.count).",
                progress: Double(events.count) / Double(InsightsEngine.minimumSampleSize)
            )
        } else if summary.insights.isEmpty {
            proLearningState(
                title: "Still watching for a clear pattern",
                detail: "\(events.count) headaches logged so far. Keep using the one-tap button and Pro will surface a pattern when a signal stands out.",
                progress: nil
            )
        } else {
            List {
                Section {
                    InsightsHeader(summary: summary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                Section {
                    ProactiveAlertsCard()
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Get ahead of triggers")
                } footer: {
                    Text("Proactive Alerts use the same forecast signals shown here to give you a 12–24 hour heads-up before risky weather.")
                        .font(.footnote)
                }
                Section {
                    ForEach(summary.insights) { insight in
                        NavigationLink {
                            InsightDetailView(insight: insight, totalEvents: summary.totalEvents)
                        } label: {
                            InsightRow(insight: insight)
                        }
                    }
                } header: {
                    Text("Your patterns")
                } footer: {
                    Text("Patterns are computed locally from your logged events. They describe your data — not a clinical diagnosis. Share with a doctor if you're trying to identify triggers.")
                        .font(.footnote)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Not enough data yet", systemImage: "chart.bar.xaxis")
        } description: {
            Text("Log at least \(InsightsEngine.minimumSampleSize) headaches and we'll start surfacing patterns from the time, sleep, weather, and Health context already attached to each entry.")
        }
    }

    private func proLearningState(title: String, detail: String, progress: Double?) -> some View {
        List {
            Section {
                ProactiveAlertsCard()
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            } header: {
                Text("Headache Pro")
            } footer: {
                Text("Proactive Alerts are the main premium feature and do not require a minimum number of logged headaches.")
                    .font(.footnote)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label(title, systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(brandColor)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let progress {
                        ProgressView(value: min(progress, 1))
                        Text("\(events.count) of \(InsightsEngine.minimumSampleSize) logs for personalized patterns")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    SampleInsightRow(icon: "barometer", title: "Example: Falling pressure pattern", detail: "Once enough logs exist, Pro can show whether headaches cluster after pressure drops.")
                }
                .padding(.vertical, 4)
            } header: {
                Text("Personalized patterns")
            }
        }
    }

    private var notEnoughSignal: some View {
        ContentUnavailableView {
            Label("No clear patterns yet", systemImage: "chart.line.flattrend.xyaxis")
        } description: {
            Text("\(events.count) headaches logged so far — not enough variation in any one factor to call out yet. Keep logging and we'll surface patterns as they emerge.")
        }
    }

    private var lockedTeaser: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(brandColor)
                    Text("See what triggers your headaches")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("Pro analyzes your logged events and surfaces the patterns hiding in the data — sleep, pressure, time of day, weather — with a chart and explanation for each one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                .padding(.horizontal, 20)

                VStack(spacing: 10) {
                    Text("Example insights you'll see")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                    SampleInsightRow(icon: "sunset.fill", title: "Most common time: Evening", detail: "40% of your headaches — 1.6× the even baseline.")
                    SampleInsightRow(icon: "bed.double.fill", title: "Sleep before a headache", detail: "Median 5h 40m — 47% under 6 hours.")
                    SampleInsightRow(icon: "barometer", title: "Falling pressure pattern", detail: "62% of headaches followed a pressure drop.")
                    SampleInsightRow(icon: "bell.badge.fill", title: "Proactive Alerts", detail: "Get notified 12–24h before risky weather.")
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Text("Logged so far: \(events.count) headache\(events.count == 1 ? "" : "s")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(paywallPriceLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    showPaywall = true
                } label: {
                    Text("Unlock Headache Pro")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(brandColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }

    private var brandColor: Color { Color(red: 0.95, green: 0.25, blue: 0.36) }

    private var paywallPriceLine: String {
        if let yearly = store.yearlyPackage, let lifetime = store.lifetimePackage {
            return "\(yearly.storeProduct.localizedPriceString)/year or \(lifetime.storeProduct.localizedPriceString) lifetime"
        }
        if let yearly = store.yearlyPackage {
            return "\(yearly.storeProduct.localizedPriceString)/year"
        }
        if let monthly = store.monthlyPackage {
            return "Plans from \(monthly.storeProduct.localizedPriceString)/month"
        }
        if store.isLoadingProducts {
            return "Loading prices…"
        }
        return "Pricing shown before purchase"
    }
}

private struct InsightsHeader: View {
    let summary: InsightsEngine.Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(summary.totalEvents) headache\(summary.totalEvents == 1 ? "" : "s") logged")
                .font(.title2.bold())
            if let range = summary.dateRange {
                Text(rangeLabel(range))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rangeLabel(_ range: ClosedRange<Date>) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: range.lowerBound)) — \(formatter.string(from: range.upperBound))"
    }
}

private struct InsightRow: View {
    let insight: InsightsEngine.Insight

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: insight.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.36))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.headline)
                Text(insight.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SampleInsightRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.36))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Proactive Alerts Card

private struct ProactiveAlertsCard: View {
    @StateObject private var prefs = ProAlertPreferences.shared

    private var brandColor: Color { Color(red: 0.95, green: 0.25, blue: 0.36) }

    var body: some View {
        NavigationLink {
            ProAlertsConfigView()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: prefs.alertsEnabled ? "bell.badge.fill" : "bell.slash.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(prefs.alertsEnabled ? brandColor : .secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Proactive Alerts")
                            .font(.headline)
                        if prefs.alertsEnabled {
                            Text("On")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.18), in: Capsule())
                                .foregroundStyle(Color.green)
                        } else {
                            Text("Suggested setup")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(brandColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(brandColor)
                        }
                    }
                    Text(prefs.alertsEnabled
                         ? "You'll be notified when a pressure drop or AQI spike is forecast. Tap to tune thresholds and quiet hours."
                         : "Turn on a daily background forecast check — get a notification 12–24 hours before a barometric drop or AQI spike.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(brandColor.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(brandColor.opacity(prefs.alertsEnabled ? 0.0 : 0.25), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail screen

struct InsightDetailView: View {
    let insight: InsightsEngine.Insight
    let totalEvents: Int

    private var brandColor: Color { Color(red: 0.95, green: 0.25, blue: 0.36) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroBlock
                chartBlock
                sectionBlock(
                    title: "Your pattern",
                    body: insight.yourPattern,
                    icon: "person.crop.circle.fill"
                )
                sectionBlock(
                    title: "Why this matters",
                    body: insight.whyItMatters,
                    icon: "lightbulb.fill"
                )
                if shouldShowAlertsCTA {
                    NavigationLink {
                        ProAlertsConfigView()
                    } label: {
                        alertsCTAContent
                    }
                    .buttonStyle(.plain)
                }
                disclaimer
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .navigationTitle(insight.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: insight.icon)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(brandColor)
                    .frame(width: 36, height: 36)
                Text(insight.title)
                    .font(.title2.bold())
            }
            Text(insight.detail)
                .font(.body)
                .foregroundStyle(.secondary)
            Text("Based on \(totalEvents) logged headache\(totalEvents == 1 ? "" : "s").")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var chartBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(insight.breakdown.axisCaption)
                .font(.subheadline.weight(.semibold))
            BreakdownChart(breakdown: insight.breakdown, accent: brandColor)
                .frame(height: 220)
            if let baseline = insight.breakdown.evenBaseline {
                HStack(spacing: 6) {
                    Rectangle()
                        .frame(width: 18, height: 2)
                        .foregroundStyle(.secondary)
                    Text("Even baseline (\(percentString(baseline))) — what you'd see if headaches were spread evenly across these buckets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func sectionBlock(title: String, body: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(brandColor)
                Text(title)
                    .font(.headline)
            }
            Text(body)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shouldShowAlertsCTA: Bool {
        switch insight.category {
        case .pressure, .airQuality, .weather: return true
        default: return false
        }
    }

    private var alertsCTAContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(brandColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Set up Proactive Alerts")
                    .font(.headline)
                Text("Get a notification before this signal spikes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(brandColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(brandColor.opacity(0.25), lineWidth: 1)
        )
    }

    private var disclaimer: some View {
        Text("Computed locally from your logged events. Descriptive only — not a clinical diagnosis.")
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
    }

    private func percentString(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct BreakdownChart: View {
    let breakdown: InsightsEngine.Breakdown
    let accent: Color

    var body: some View {
        Chart {
            ForEach(breakdown.buckets) { bucket in
                BarMark(
                    x: .value("Bucket", bucket.label),
                    y: .value("Share", bucket.share)
                )
                .foregroundStyle(bucket.isPeak ? accent : Color.secondary.opacity(0.45))
                .annotation(position: .top, alignment: .center) {
                    Text(percentLabel(bucket.share))
                        .font(.caption2.weight(bucket.isPeak ? .bold : .regular))
                        .foregroundStyle(bucket.isPeak ? accent : .secondary)
                }
                .cornerRadius(4)
            }
            if let baseline = breakdown.evenBaseline {
                RuleMark(y: .value("Even baseline", baseline))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .topTrailing, alignment: .trailing) {
                        Text("Even baseline")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(percentLabel(d))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisValueLabel()
                    .font(.caption2)
            }
        }
        .chartYScale(domain: 0...max(0.4, (breakdown.buckets.map(\.share).max() ?? 0.4) * 1.25))
    }

    private func percentLabel(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
