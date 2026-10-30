import Charts
import SwiftData
import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var store: StoreService
    @Query(sort: \HeadacheEvent.timestamp, order: .reverse) private var events: [HeadacheEvent]
    @State private var showPaywall = false
    @State private var dailyRecords: [DailyRecord] = []
    @State private var riskForecast: ProactiveAlertsEngine.RiskForecast?
    @State private var riskLoading = false
    @State private var riskLocationMissing = false
    /// Guards the insights value-moment so it counts at most once per view appearance.
    @State private var notedInsightsMoment = false
    #if DEBUG
    /// `-HeadacheDuoScreen pattern` pushes the top pattern's detail at launch.
    @State private var debugShowsFirstPattern = false
    @State private var debugDidPushFirstPattern = false
    #endif

    private var summary: InsightsEngine.Summary {
        InsightsEngine.summarize(events, dailyRecords: dailyRecords)
            .prioritized(by: QuizInsightPriority.categories)
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
                .task { store.trackPaywallImpression(id: "headache_insights_sheet") }
        }
        .task {
            await loadAndBackfillDailyRecords()
            await refreshRiskForecast()
            noteInsightsPositiveMomentIfEarned()
        }
        .onChange(of: events.count) { _, _ in
            Task { await loadAndBackfillDailyRecords() }
        }
        .onAppear {
            // Second-touch trial offer hook. Root content evaluates the gates.
            NotificationCenter.default.post(name: .headachePatternsDidAppear, object: nil)
        }
        #if DEBUG
        .navigationDestination(isPresented: $debugShowsFirstPattern) {
            if let insight = summary.insights.first {
                InsightDetailView(insight: insight, totalEvents: summary.totalEvents)
            }
        }
        .task {
            guard DuoScreen.requested == .pattern, !debugDidPushFirstPattern else { return }
            debugDidPushFirstPattern = true
            try? await Task.sleep(for: .milliseconds(600))
            debugShowsFirstPattern = store.isProUnlocked && !summary.insights.isEmpty
        }
        #endif
    }

    @ViewBuilder
    private var proContent: some View {
        List {
            Section {
                InsightsHeader(summary: summary)
                    .keepsWholeAboveTabBar()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
            }

            patternsSection

            if !HeadacheBrand.isScreenshotMode {
                Section {
                    DailyRiskForecastCard(
                        forecast: riskForecast,
                        isLoading: riskLoading,
                        locationMissing: riskLocationMissing,
                        onRetry: { Task { await refreshRiskForecast(forceRefresh: true) } }
                    )
                    .keepsWholeAboveTabBar()
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Today's risk")
                        .keepsWholeAboveTabBar()
                } footer: {
                    Text("Risk combines the next 24 hours of forecast pressure and air quality with last night's sleep. It's a heads-up, not a prediction.")
                        .font(.footnote)
                        .keepsWholeAboveTabBar()
                }
            }

            if !HeadacheBrand.isScreenshotMode {
                Section {
                    ProactiveAlertsCard()
                        .keepsWholeAboveTabBar()
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Get ahead of triggers")
                        .keepsWholeAboveTabBar()
                } footer: {
                    Text("Proactive Alerts use the same forecast signals shown here to give you a 12–24 hour heads-up before risky weather.")
                        .font(.footnote)
                        .keepsWholeAboveTabBar()
                }
            }
        }
        .compactChromeInPane()
        .clearsFloatingTabBar()
    }

    @ViewBuilder
    private var patternsSection: some View {
        if events.count < InsightsEngine.minimumSampleSize {
            Section {
                LearningStateRow(
                    title: "Personalized patterns warming up",
                    detail: "Personalized patterns unlock after \(InsightsEngine.minimumSampleSize) logs. You have \(events.count).",
                    progress: Double(events.count) / Double(InsightsEngine.minimumSampleSize)
                )
            } header: {
                Text("Your patterns")
            }
        } else if summary.insights.isEmpty {
            Section {
                LearningStateRow(
                    title: "Still watching for a clear pattern",
                    detail: "\(events.count) headaches logged so far. Keep using the one-tap button and Pro will surface a pattern when a signal stands out.",
                    progress: nil
                )
            } header: {
                Text("Your patterns")
            }
        } else {
            Section {
                ForEach(summary.insights) { insight in
                    NavigationLink {
                        InsightDetailView(insight: insight, totalEvents: summary.totalEvents)
                    } label: {
                        InsightRow(insight: insight)
                    }
                    .keepsWholeAboveTabBar()
                }
            } header: {
                Text("Your patterns")
                    .keepsWholeAboveTabBar()
            } footer: {
                Text("Patterns are computed locally from your logged events. They describe your data, not a clinical diagnosis. Share with a doctor if you're trying to identify triggers.")
                    .font(.footnote)
                    .keepsWholeAboveTabBar()
            }
        }
    }

    /// Seeing real, unlocked patterns is a strong "the app delivered value" signal, so count it toward
    /// review eligibility. Count only; the prompt itself still presents on the Home tab after a log.
    private func noteInsightsPositiveMomentIfEarned() {
        guard !notedInsightsMoment,
              store.isProUnlocked,
              events.count >= InsightsEngine.minimumSampleSize,
              !summary.insights.isEmpty else { return }
        notedInsightsMoment = true
        ReviewPromptTracker.recordPositiveMoment()
    }

    private func refreshRiskForecast(forceRefresh: Bool = false) async {
        guard store.isProUnlocked else { return }
        if !forceRefresh, let forecast = riskForecast, Date().timeIntervalSince(forecast.evaluatedAt) < 30 * 60 {
            return
        }
        riskLocationMissing = false
        riskLoading = true
        defer { riskLoading = false }
        guard let coord = CachedLocation.current() else {
            riskLocationMissing = true
            riskForecast = nil
            return
        }
        let forecast = await ForecastClient.fetch24Hour(latitude: coord.latitude, longitude: coord.longitude)
        let sleep = await HealthKitService.shared.fetchSleepHoursForNightBefore(Date())
        riskForecast = ProactiveAlertsEngine.dailyRiskForecast(
            forecast: forecast,
            sleepLastNightHours: sleep
        )
    }

    private func loadAndBackfillDailyRecords() async {
        var records = DailyRecordStore.load()
        let versionKey = HeadacheStorageKey.sleepBackfillVersion.rawValue
        let storedVersion = HeadacheAppGroup.userDefaults.integer(forKey: versionKey)
        if storedVersion < DailyRecordStore.sleepBackfillVersion {
            records = DailyRecordStore.resettingStaleSleep(records, storedVersion: storedVersion)
            DailyRecordStore.save(records)
            HeadacheAppGroup.userDefaults.set(DailyRecordStore.sleepBackfillVersion, forKey: versionKey)
        }
        let needsSleepBackfill = records.contains { !$0.sleepFetched && $0.weatherFetched }
        if needsSleepBackfill {
            records = await DailyRecordStore.backfillSleep(records: records, healthKit: HealthKitService.shared)
            DailyRecordStore.save(records)
        }
        dailyRecords = records
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
                    Text("Pro analyzes your logged events and surfaces the patterns hiding in the data (sleep, pressure, time of day, weather) with a chart and explanation for each one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                .padding(.horizontal, 20)

                if events.count >= InsightsEngine.minimumSampleSize, !summary.insights.isEmpty {
                    realInsightPreview
                } else {
                    sampleInsightPreview
                }
            }
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Text("Logged so far: \(events.count) headache\(events.count == 1 ? "" : "s")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    showPaywall = true
                } label: {
                    Text("See Pro plans")
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

    private var realInsightPreview: some View {
        VStack(spacing: 10) {
            Text("Your patterns so far")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)

            ForEach(summary.insights) { insight in
                LockedInsightPreviewRow(insight: insight, showPaywall: $showPaywall)
            }
        }
        .padding(.horizontal, 16)
    }

    private var sampleInsightPreview: some View {
        VStack(spacing: 10) {
            Text("Example patterns you'll see")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
            SampleInsightRow(icon: "sunset.fill", title: "Most common time: Evening", detail: "40% of your headaches, 1.6× the even baseline.")
            SampleInsightRow(icon: "bed.double.fill", title: "Sleep before a headache", detail: "Median 5h 40m, 47% under 6 hours.")
            SampleInsightRow(icon: "barometer", title: "Falling pressure pattern", detail: "62% of headaches followed a pressure drop.")
            SampleInsightRow(icon: "bell.badge.fill", title: "Proactive Alerts", detail: "Get notified 12–24h before risky weather.")
        }
        .padding(.horizontal, 16)
    }

    private var brandColor: Color { Color(red: 0.95, green: 0.25, blue: 0.36) }
}

/// Translates the user's quiz answers into an ordered list of insight categories
/// to float to the top of the Patterns list. Categories the user flagged as
/// triggers come first; everything else keeps its strength-based order.
enum QuizInsightPriority {
    static var categories: [InsightsEngine.InsightCategory] {
        var result: [InsightsEngine.InsightCategory] = []
        func add(_ category: InsightsEngine.InsightCategory) {
            if !result.contains(category) { result.append(category) }
        }

        switch HeadacheQuizStore.answer(for: "trigger_weather") {
        case "Pressure drops": add(.pressure)
        case "Heat", "Cold": add(.weather)
        default: break
        }
        if HeadacheQuizStore.answer(for: "trigger_sleep") == "Yes" {
            add(.sleep)
        }
        if let time = HeadacheQuizStore.answer(for: "time_of_day"), time != "No pattern" {
            add(.time)
        }
        if let severity = HeadacheQuizStore.answer(for: "severity"),
           severity.hasPrefix("Extreme") || severity.hasPrefix("Medium") {
            add(.severity)
        }
        return result
    }
}

extension InsightsEngine.Summary {
    /// Stable reorder that moves insights in `categories` to the front (in the
    /// given priority order) while preserving the original strength order within
    /// each tier.
    func prioritized(by categories: [InsightsEngine.InsightCategory]) -> InsightsEngine.Summary {
        guard !categories.isEmpty else { return self }
        let rank = Dictionary(uniqueKeysWithValues: categories.enumerated().map { ($1, $0) })
        let sorted = insights.enumerated().sorted { lhs, rhs in
            let lrank = rank[lhs.element.category] ?? Int.max
            let rrank = rank[rhs.element.category] ?? Int.max
            if lrank != rrank { return lrank < rrank }
            return lhs.offset < rhs.offset
        }.map(\.element)
        return InsightsEngine.Summary(totalEvents: totalEvents, dateRange: dateRange, insights: sorted)
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
        return "\(formatter.string(from: range.lowerBound)) to \(formatter.string(from: range.upperBound))"
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

private struct LockedInsightPreviewRow: View {
    let insight: InsightsEngine.Insight
    @Binding var showPaywall: Bool

    private var brandColor: Color { Color(red: 0.95, green: 0.25, blue: 0.36) }

    var body: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: insight.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(brandColor)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(insight.title)
                            .font(.headline)
                        ProBadge()
                    }
                    Text(insight.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .blur(radius: 7)
            .overlay(
                Image(systemName: "lock.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The blur only hides pixels: without this, VoiceOver reads the locked insight in full.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Locked Pro pattern")
        .accessibilityHint("Opens Pro plans")
        .accessibilityAddTraits(.isButton)
    }
}

private struct ProBadge: View {
    var body: some View {
        Text("Pro")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(red: 0.95, green: 0.25, blue: 0.36).opacity(0.15), in: Capsule())
            .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.36))
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
                         ? "You'll be notified when the forecast matches a supported personal trigger. Tap to tune thresholds and quiet hours."
                         : "Turn on background forecast checks that stay quiet until your logs support a pressure or AQI trigger.")
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
                    .keepsWholeAboveTabBar()
                chartBlock
                    .keepsWholeAboveTabBar()
                sectionBlock(
                    title: "Your pattern",
                    body: insight.yourPattern,
                    icon: "person.crop.circle.fill"
                )
                .keepsWholeAboveTabBar()
                sectionBlock(
                    title: "Why this matters",
                    body: insight.whyItMatters,
                    icon: "lightbulb.fill"
                )
                .keepsWholeAboveTabBar()
                if shouldShowAlertsCTA {
                    NavigationLink {
                        ProAlertsConfigView()
                    } label: {
                        alertsCTAContent
                    }
                    .buttonStyle(.plain)
                    .keepsWholeAboveTabBar()
                }
                disclaimer
                    .keepsWholeAboveTabBar()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .clearsFloatingTabBar(backdrop: Color(.systemBackground))
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    BaselineSwatch()
                    Text("Even baseline (\(percentString(baseline))): what you'd see if headaches were spread evenly across these buckets.")
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
        Text("Computed locally from your logged events. Descriptive only, not a clinical diagnosis.")
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
                // Explained by the legend under the chart, which draws the
                // same dashed line.
                RuleMark(y: .value("Even baseline", baseline))
                    .lineStyle(BaselineSwatch.stroke)
                    .foregroundStyle(BaselineSwatch.color)
            }
        }
        // Every bar carries its own value, so there are no gridlines for the
        // value labels to collide with.
        .chartYAxis(.hidden)
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

/// The even-baseline rule as it appears in the chart, for its legend.
private struct BaselineSwatch: View {
    static var color: Color { Color.primary.opacity(0.5) }
    static var stroke: StrokeStyle { StrokeStyle(lineWidth: 1.5, dash: [4, 3]) }

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 1))
            path.addLine(to: CGPoint(x: 18, y: 1))
        }
        .stroke(Self.color, style: Self.stroke)
        .frame(width: 18, height: 2)
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
    }
}

// MARK: - Calendar heatmap

struct CalendarHeatmapCard: View {
    let days: [HeatmapDay]
    var title = "Last 90 days"

    private var window: [HeatmapDay] { HeatmapData.padded(days) }
    private var headacheDayCount: Int { days.filter { $0.count > 0 }.count }
    private var freeDayCount: Int { days.count - headacheDayCount }

    private var caption: String {
        let base = "Coloured days have a logged headache. Darker means more severe."
        return days.count < window.count ? base + " Outlined days come before your first log." : base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer(minLength: 8)
                HeatmapLegend()
            }

            HeatmapGrid(days: window)

            HStack(spacing: 14) {
                summaryChip(value: headacheDayCount, label: "headache days")
                summaryChip(value: freeDayCount, label: "headache-free")
                Spacer(minLength: 0)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func summaryChip(value: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(value)").fontWeight(.semibold).foregroundStyle(.primary)
            Text(label)
        }
    }
}

/// Arranges heatmap days into week columns, Sunday on top. Kept off the view
/// so tests can call it without the main actor.
enum HeatmapLayout {
    /// One column per week, each exactly seven cells: the first column is
    /// padded to its weekday and the last to Saturday with placeholders.
    static func weekColumns(for days: [HeatmapDay], calendar: Calendar = .current) -> [[HeatmapDay]] {
        guard let first = days.first else { return [] }
        let placeholder = HeatmapDay(date: .distantPast, count: 0, peakSeverity: nil)
        let leadingPad = calendar.component(.weekday, from: first.date) - 1
        var cells = Array(repeating: placeholder, count: leadingPad) + days
        cells += Array(repeating: placeholder, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }
}

/// The heatmap's cells. Square cells share the width it is given, so the grid
/// spans its card at any width without measuring it.
struct HeatmapGrid: View {
    let days: [HeatmapDay]
    var cellSpacing: CGFloat = 4

    var body: some View {
        let columns = HeatmapLayout.weekColumns(for: days)
        Grid(horizontalSpacing: cellSpacing, verticalSpacing: cellSpacing) {
            ForEach(0..<7, id: \.self) { weekday in
                GridRow {
                    ForEach(columns.indices, id: \.self) { week in
                        cell(for: columns[week][weekday])
                    }
                }
            }
        }
    }

    private func cell(for day: HeatmapDay) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return shape
            .fill(heatmapColor(for: day))
            .overlay {
                if !day.isTracked {
                    shape.strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                }
            }
            .aspectRatio(1, contentMode: .fit)
    }
}

struct HeatmapLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Less").font(.caption2).foregroundStyle(.secondary)
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(legendSwatch(at: i))
                    .frame(width: 12, height: 12)
            }
            Text("More").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func legendSwatch(at index: Int) -> Color {
        switch index {
        case 0: Color.secondary.opacity(0.15)
        case 1: heatmapColor(for: HeatmapDay(date: .now, count: 1, peakSeverity: .slight))
        case 2: heatmapColor(for: HeatmapDay(date: .now, count: 1, peakSeverity: .medium))
        case 3: heatmapColor(for: HeatmapDay(date: .now, count: 1, peakSeverity: .extreme))
        default: heatmapColor(for: HeatmapDay(date: .now, count: 3, peakSeverity: .extreme))
        }
    }
}

func heatmapColor(for day: HeatmapDay) -> Color {
    let placeholder = day.date == .distantPast
    if placeholder || !day.isTracked { return Color.clear }
    if day.count == 0 { return Color.secondary.opacity(0.15) }
    let brand = Color(red: 0.95, green: 0.25, blue: 0.36)
    if let severity = day.peakSeverity {
        switch severity {
        case .slight: return brand.opacity(0.35)
        case .medium: return brand.opacity(0.65)
        case .extreme: return brand.opacity(0.95)
        }
    }
    return brand.opacity(day.count >= 2 ? 0.75 : 0.50)
}

// MARK: - Daily risk forecast

struct DailyRiskForecastCard: View {
    let forecast: ProactiveAlertsEngine.RiskForecast?
    let isLoading: Bool
    let locationMissing: Bool
    let onRetry: () -> Void

    private var brandColor: Color { Color(red: 0.95, green: 0.25, blue: 0.36) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let forecast {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(forecast.level.displayName)
                        .font(.title2.bold())
                        .foregroundStyle(forecast.level.tint)
                    Text("risk today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh risk forecast")
                }
                if forecast.factors.isEmpty {
                    Text("No elevated signals in the next 24 hours.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(forecast.factors) { factor in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: factor.icon)
                                    .font(.subheadline)
                                    .foregroundStyle(brandColor)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(factor.title).font(.subheadline.weight(.semibold))
                                    Text(factor.detail).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(forecast.level.tint)
                    Text(forecast.recommendation)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            } else if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking forecast…").font(.subheadline).foregroundStyle(.secondary)
                }
            } else if locationMissing {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Location unavailable", systemImage: "location.slash")
                        .font(.subheadline.weight(.semibold))
                    Text("Log a headache once to capture your location, then come back here for forecast-based risk.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(.secondary)
                    Text("Forecast unavailable. Tap to retry.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Retry", action: onRetry)
                        .font(.footnote.bold())
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private extension ProactiveAlertsEngine.RiskLevel {
    var displayName: String {
        switch self {
        case .low: "Low"
        case .moderate: "Moderate"
        case .high: "High"
        }
    }

    var tint: Color {
        switch self {
        case .low: .green
        case .moderate: .orange
        case .high: .red
        }
    }
}

// MARK: - Learning state row (used when patterns aren't ready yet)

private struct LearningStateRow: View {
    let title: String
    let detail: String
    let progress: Double?

    private var brandColor: Color { Color(red: 0.95, green: 0.25, blue: 0.36) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(brandColor)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let progress {
                ProgressView(value: min(progress, 1))
            }
        }
        .padding(.vertical, 4)
    }
}
