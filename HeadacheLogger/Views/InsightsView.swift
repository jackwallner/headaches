import SwiftData
import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var store: StoreKitService
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
            }
        }
        .navigationTitle("Patterns")
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private var proContent: some View {
        if events.count < InsightsEngine.minimumSampleSize {
            emptyState
        } else if summary.insights.isEmpty {
            notEnoughSignal
        } else {
            List {
                Section {
                    InsightsHeader(summary: summary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                }
                Section {
                    ForEach(summary.insights) { insight in
                        InsightRow(insight: insight)
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
                    Text("Pro analyzes your logged events and surfaces the patterns hiding in the data — sleep, pressure, time of day, weather.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                VStack(spacing: 10) {
                    SampleInsightRow(icon: "bed.double.fill", title: "Sleep before a headache", detail: "Median sleep the night before: 5h 40m.")
                    SampleInsightRow(icon: "barometer", title: "Falling pressure pattern", detail: "62% of your headaches followed a pressure drop.")
                    SampleInsightRow(icon: "sun.max.fill", title: "Most common time: Afternoon", detail: "48% of your headaches happened in the afternoon.")
                }
                .padding(.horizontal, 16)
                .opacity(0.85)
                .overlay(
                    LinearGradient(
                        colors: [.clear, Color(.systemBackground)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                )

                VStack(spacing: 6) {
                    Text("Logged so far: \(events.count) headache\(events.count == 1 ? "" : "s")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        showPaywall = true
                    } label: {
                        Text("Unlock Pro")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(brandColor, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 32)
            }
        }
    }

    private var brandColor: Color { Color(red: 0.95, green: 0.25, blue: 0.36) }
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
