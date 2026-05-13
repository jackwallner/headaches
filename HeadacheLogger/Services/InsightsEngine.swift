import Foundation

/// Pure analysis over the user's logged `HeadacheEvent`s. Computes pattern distributions
/// the user can act on without requiring a non-headache baseline.
///
/// All output is descriptive — "what does the data show?" rather than "what causes a headache?".
/// Nothing here leaves the device.
enum InsightsEngine {
    /// Minimum sample size for any single insight to be surfaced. Below this the dataset is too
    /// noisy to be useful and we'd risk telling the user something untrue.
    static let minimumSampleSize: Int = 5

    enum InsightCategory: String, Sendable {
        case time
        case sleep
        case pressure
        case airQuality
        case heart
        case weather
        case severity
    }

    struct Bucket: Sendable, Identifiable {
        var id: String { label }
        let label: String
        let share: Double
        let count: Int
        let isPeak: Bool
    }

    struct Breakdown: Sendable {
        let buckets: [Bucket]
        /// Y-value (share, 0...1) of an "even baseline" rule. Nil when an even baseline is not
        /// meaningful (e.g. sleep hour bins are not equiprobable).
        let evenBaseline: Double?
        /// One short line for the chart caption — what the bars measure.
        let axisCaption: String
    }

    struct Insight: Sendable, Identifiable {
        let id: String
        let category: InsightCategory
        let icon: String
        let title: String
        let detail: String
        /// 0...1 strength used to rank insights — higher means a more concentrated pattern.
        let strength: Double
        /// Generalized explanation of why this signal correlates with headaches in the literature.
        let whyItMatters: String
        /// Narrative comparing the user's distribution against the baseline ("evenings 40% vs 25% baseline").
        let yourPattern: String
        /// Comparable bucket distribution for the detail-view chart.
        let breakdown: Breakdown
    }

    struct Summary: Sendable {
        let totalEvents: Int
        let dateRange: ClosedRange<Date>?
        let insights: [Insight]
    }

    static func summarize(_ events: [HeadacheEvent], dailyRecords: [DailyRecord] = [], calendar: Calendar = .current) -> Summary {
        let total = events.count
        let range: ClosedRange<Date>? = {
            let sorted = events.map(\.timestamp).sorted()
            guard let first = sorted.first, let last = sorted.last, first <= last else { return nil }
            return first...last
        }()
        guard total >= minimumSampleSize else {
            return Summary(totalEvents: total, dateRange: range, insights: [])
        }

        var insights: [Insight] = []

        if let item = partOfDayInsight(events) { insights.append(item) }
        if let item = weekdayInsight(events, calendar: calendar) { insights.append(item) }
        if let item = sleepInsight(events, dailyRecords: dailyRecords) { insights.append(item) }
        if let item = pressureTrendInsight(events) { insights.append(item) }
        if let item = pressureDeltaInsight(events) { insights.append(item) }
        if let item = airQualityInsight(events) { insights.append(item) }
        if let item = hrvInsight(events) { insights.append(item) }
        if let item = humidityInsight(events) { insights.append(item) }
        if let item = severityInsight(events) { insights.append(item) }

        // Strongest patterns first.
        insights.sort { $0.strength > $1.strength }
        return Summary(totalEvents: total, dateRange: range, insights: insights)
    }

    // MARK: - Individual insights

    private static func partOfDayInsight(_ events: [HeadacheEvent]) -> Insight? {
        let order: [PartOfDay] = [.morning, .afternoon, .evening, .overnight]
        var counts: [PartOfDay: Int] = [:]
        for event in events {
            counts[event.partOfDay, default: 0] += 1
        }
        guard let (top, topCount) = counts.max(by: { $0.value < $1.value }), topCount > 0 else { return nil }
        let total = events.count
        let topShare = Double(topCount) / Double(total)
        guard topShare >= 0.30 else { return nil }
        let buckets = order.map { part -> Bucket in
            let c = counts[part] ?? 0
            return Bucket(
                label: label(for: part),
                share: Double(c) / Double(total),
                count: c,
                isPeak: part == top
            )
        }
        let baseline = 1.0 / Double(order.count)
        let multiple = topShare / baseline
        let yourPattern = "\(percent(topShare)) of your headaches happen in the \(label(for: top).lowercased()) — about \(String(format: "%.1fx", multiple)) what you'd expect if they were evenly spread across the day (\(percent(baseline)) per period). " + othersSummary(buckets, excluding: top.rawValue, label: { $0.label })
        return Insight(
            id: "part-of-day",
            category: .time,
            icon: icon(for: top),
            title: "Most common time: \(label(for: top))",
            detail: "\(percent(topShare)) of your logged headaches happened in the \(label(for: top).lowercased()).",
            strength: topShare,
            whyItMatters: "Headaches that cluster at a specific time of day often point to circadian or behavioural triggers — caffeine timing, screen exposure, dehydration, posture, or letdown after stress. Knowing your peak window lets you preload water, breaks, or rescue meds before you'd normally feel it coming.",
            yourPattern: yourPattern,
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: baseline,
                axisCaption: "Share of your headaches by part of day"
            )
        )
    }

    private static func weekdayInsight(_ events: [HeadacheEvent], calendar: Calendar) -> Insight? {
        var counts: [Int: Int] = [:]
        for event in events {
            counts[event.weekdayIndex, default: 0] += 1
        }
        guard let (topIndex, topCount) = counts.max(by: { $0.value < $1.value }), topCount > 0 else { return nil }
        let total = events.count
        let topShare = Double(topCount) / Double(total)
        // Uniform across 7 days would be ~14%. Surface only when meaningfully concentrated —
        // raised to 25% so a near-flat weekday distribution doesn't generate noise.
        guard topShare >= 0.25 else { return nil }
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let fullSymbols = calendar.standaloneWeekdaySymbols
        let topName: String = {
            let i = topIndex - 1
            return (i >= 0 && i < fullSymbols.count) ? fullSymbols[i] : "a weekday"
        }()
        let buckets: [Bucket] = (1...7).map { idx -> Bucket in
            let c = counts[idx] ?? 0
            let short = (idx - 1 >= 0 && idx - 1 < symbols.count) ? symbols[idx - 1] : "?"
            return Bucket(
                label: short,
                share: Double(c) / Double(total),
                count: c,
                isPeak: idx == topIndex
            )
        }
        let baseline = 1.0 / 7.0
        let multiple = topShare / baseline
        let yourPattern = "\(percent(topShare)) of your headaches fall on \(topName) — about \(String(format: "%.1fx", multiple)) the even baseline of \(percent(baseline)) per day."
        return Insight(
            id: "weekday",
            category: .time,
            icon: "calendar",
            title: "Headache day: \(topName)",
            detail: "\(percent(topShare)) of your headaches fall on \(topName).",
            strength: topShare - baseline,
            whyItMatters: "Weekday clusters often signal a routine trigger — stress build-up, irregular sleep on transition days, alcohol after work, or letdown on a recurring rest day. Spotting the pattern points to behavioural changes (steady sleep windows, caffeine timing, scheduled breaks) rather than medication-only fixes.",
            yourPattern: yourPattern,
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: baseline,
                axisCaption: "Share of your headaches by weekday"
            )
        )
    }

    private static func sleepInsight(_ events: [HeadacheEvent], dailyRecords: [DailyRecord]) -> Insight? {
        let headacheSleepValues = events.compactMap(\.sleepHoursLastNight)
        guard headacheSleepValues.count >= minimumSampleSize else { return nil }
        let med = median(headacheSleepValues)

        let bins: [(label: String, range: Range<Double>)] = [
            ("<5h", 0..<5),
            ("5–6h", 5..<6),
            ("6–7h", 6..<7),
            ("7–8h", 7..<8),
            ("8h+", 8..<48)
        ]

        // --- Lift-based analysis when baseline sleep data is available ---
        let sleepRecords = dailyRecords.filter { $0.sleepFetched }
        let hasBaseline = sleepRecords.count >= minimumSampleSize

        let headlineBucket: (label: String, bucketIndex: Int, lift: Double)?
        let liftBuckets: [DailyRecordStore.SleepBucketCounts]
        let overallRate: Double

        if hasBaseline {
            let allBuckets = DailyRecordStore.sleepConditionCounts(from: dailyRecords)
            let totalSleepDays = sleepRecords.count
            let totalHeadacheDays = sleepRecords.filter(\.hadHeadache).count
            overallRate = totalSleepDays > 0 ? Double(totalHeadacheDays) / Double(totalSleepDays) : 0

            // Compute lift for each bucket with meaningful sample size
            var best: (label: String, bucketIndex: Int, lift: Double)? = nil
            for (idx, bucket) in allBuckets.enumerated() {
                guard bucket.totalDays >= 2 else { continue }
                let rate = bucket.headacheRate
                let lift = overallRate > 0 ? rate / overallRate : 0
                if lift > (best?.lift ?? 1.0) && lift >= 1.3 {
                    best = (bucket.label, idx, lift)
                }
            }

            headlineBucket = best
            liftBuckets = allBuckets
        } else {
            headlineBucket = nil
            liftBuckets = []
            overallRate = 0
        }

        // --- Build chart buckets (always from headache events for consistency) ---
        let total = headacheSleepValues.count
        let chartBuckets: [Bucket] = bins.enumerated().map { idx, bin in
            let c = headacheSleepValues.filter { bin.range.contains($0) }.count
            let share = Double(c) / Double(total)
            // Highlight the lift-based bucket if available, else fall back to max share
            let isPeak: Bool
            if let headline = headlineBucket {
                isPeak = idx == headline.bucketIndex
            } else {
                // Fallback: highlight the highest-share bucket
                let maxShare = bins.enumerated().map { i, b in
                    Double(headacheSleepValues.filter { b.range.contains($0) }.count) / Double(total)
                }.max() ?? 0
                isPeak = abs(share - maxShare) < 0.001
            }
            return Bucket(label: bin.label, share: share, count: c, isPeak: isPeak)
        }

        // --- Build detail text ---
        let detail: String
        let strength: Double
        let yourPattern: String
        let title: String

        if let headline = headlineBucket, headline.lift >= 1.3 {
            let pct = Int((headline.lift - 1.0) * 100)
            let bucket = liftBuckets[headline.bucketIndex]
            let ratePct = Int(bucket.headacheRate * 100)
            let overallPct = Int(overallRate * 100)
            let moreLikely = headline.lift >= 2.0
                ? "\(String(format: "%.1f", headline.lift))×"
                : "\(pct)%"
            detail = "Headaches are \(moreLikely) more likely after \(headline.label) of sleep (\(ratePct)% vs \(overallPct)% overall). Median: \(formatHours(med))."
            strength = 0.5 + min((headline.lift - 1.0) / 2.0, 0.5)
            title = "Low sleep: \(headline.label)"
            yourPattern = "On days following \(headline.label) of sleep, your headache rate was \(ratePct)% — compared to \(overallPct)% across all days with sleep data. Median sleep before a headache: \(formatHours(med))."
        } else {
            let lowSleepShare = Double(headacheSleepValues.filter { $0 < 6 }.count) / Double(total)
            if lowSleepShare >= 0.4 {
                detail = "\(percent(lowSleepShare)) of your headaches followed a night with under 6 hours of sleep. Median: \(formatHours(med))."
                strength = 0.5 + lowSleepShare * 0.4
            } else {
                detail = "Median sleep the night before a headache: \(formatHours(med))."
                strength = 0.35
            }
            title = "Sleep before a headache"
            yourPattern = "Median sleep the night before a headache: \(formatHours(med)). \(percent(lowSleepShare)) of your headaches followed a night under 6 hours."
        }

        return Insight(
            id: "sleep",
            category: .sleep,
            icon: "bed.double.fill",
            title: title,
            detail: detail,
            strength: strength,
            whyItMatters: "Sleep deprivation is one of the most consistently documented headache triggers in the migraine literature. Both too little (<6h) and too much (>9h) sleep, and especially irregular timing, can precipitate attacks. Wake-time consistency — including weekends — is the single highest-leverage behavioural change for many people.",
            yourPattern: yourPattern,
            breakdown: Breakdown(
                buckets: chartBuckets,
                evenBaseline: nil,
                axisCaption: "Sleep duration the night before each headache"
            )
        )
    }

    private static func pressureTrendInsight(_ events: [HeadacheEvent]) -> Insight? {
        let trends = events.map(\.pressureTrend).filter { $0 != .unavailable }
        guard trends.count >= minimumSampleSize else { return nil }
        let order: [PressureTrend] = [.falling, .steady, .rising]
        let total = trends.count
        let coveragePhrase = coverageQualifier(subset: total, of: events.count)
        var counts: [PressureTrend: Int] = [:]
        for t in trends { counts[t, default: 0] += 1 }
        guard let (top, topCount) = counts.max(by: { $0.value < $1.value }) else { return nil }
        let topShare = Double(topCount) / Double(total)
        guard topShare >= 0.45 else { return nil }
        let buckets: [Bucket] = order.map { trend in
            let c = counts[trend] ?? 0
            return Bucket(
                label: label(for: trend),
                share: Double(c) / Double(total),
                count: c,
                isPeak: trend == top
            )
        }
        let baseline = 1.0 / 3.0
        let topLabel = label(for: top)
        let title: String
        let icon: String
        switch top {
        case .falling: title = "Falling pressure pattern"; icon = "arrow.down.right.circle.fill"
        case .rising: title = "Rising pressure pattern"; icon = "arrow.up.right.circle.fill"
        default: title = "Steady pressure"; icon = "minus.circle.fill"
        }
        let why: String
        switch top {
        case .falling:
            why = "Falling barometric pressure is the most replicated weather trigger in the migraine literature — drops typically arrive 6–24 hours before a storm and correlate with attack onset. Because it's forecastable, this is a signal you can prepare for."
        case .rising:
            why = "Pressure rises (high-pressure systems building in) trigger fewer people than drops, but a clear cluster on rises still represents a forecastable signal — meaning hydration, caffeine, or rescue meds can be timed."
        default:
            why = "A 'steady' cluster suggests pressure isn't your dominant weather trigger. Other environmental signals (humidity, AQI) or non-weather factors are likelier drivers — worth checking those screens."
        }
        return Insight(
            id: "pressure-trend",
            category: .pressure,
            icon: icon,
            title: title,
            detail: "\(percent(topShare)) of your headaches\(coveragePhrase) happened during \(topLabel.lowercased()) barometric pressure.",
            strength: topShare,
            whyItMatters: why,
            yourPattern: "\(percent(topShare)) of your headaches\(coveragePhrase) occurred during \(topLabel.lowercased()) pressure — \(String(format: "%.1fx", topShare / baseline)) the even baseline of \(percent(baseline)).",
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: baseline,
                axisCaption: "Pressure trend at headache onset"
            )
        )
    }

    private static func pressureDeltaInsight(_ events: [HeadacheEvent]) -> Insight? {
        let deltas = events.compactMap(\.barometricPressureDeltaHpa6h)
        guard deltas.count >= minimumSampleSize else { return nil }
        let med = median(deltas)
        // Drops/rises under ~3 hPa over 6h are within typical daily noise — filter them out so
        // the insight only surfaces when the user's pre-headache pressure shift is actually notable.
        guard abs(med) >= 3.0 else { return nil }
        let direction = med < 0 ? "drop" : "rise"
        let bins: [(label: String, range: Range<Double>)] = [
            ("≤−6", -100..<(-6)),
            ("−6 to −3", -6..<(-3)),
            ("−3 to −1", -3..<(-1)),
            ("−1 to +1", -1..<1),
            ("+1 to +3", 1..<3),
            ("+3 to +6", 3..<6),
            ("≥+6", 6..<100)
        ]
        let total = deltas.count
        let medBinIndex = bins.firstIndex { $0.range.contains(med) } ?? 3
        let buckets: [Bucket] = bins.enumerated().map { idx, bin in
            let c = deltas.filter { bin.range.contains($0) }.count
            return Bucket(
                label: bin.label,
                share: Double(c) / Double(total),
                count: c,
                isPeak: idx == medBinIndex
            )
        }
        return Insight(
            id: "pressure-delta",
            category: .pressure,
            icon: "barometer",
            title: "Typical 6h pressure shift",
            detail: "Median pressure change in the 6 hours before your headaches: \(String(format: "%+.1f hPa", med)) — a typical \(direction).",
            strength: min(1.0, abs(med) / 6),
            whyItMatters: "The size of pressure swings tends to matter more than the absolute level. Drops of 5+ hPa within 24 hours are commonly cited thresholds for triggering migraine in sensitive people. The bigger your typical pre-headache shift, the more useful Proactive Alerts will be at giving you a heads-up.",
            yourPattern: "Median 6-hour pressure change before your headaches: \(String(format: "%+.1f hPa", med)). The histogram on the right shows the full distribution.",
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: "6-hour pressure change (hPa) before each headache"
            )
        )
    }

    private static func airQualityInsight(_ events: [HeadacheEvent]) -> Insight? {
        let aqi = events.compactMap(\.usAQI)
        guard aqi.count >= minimumSampleSize else { return nil }
        let elevated = Double(aqi.filter { $0 >= 75 }.count) / Double(aqi.count)
        guard elevated >= 0.30 else { return nil }
        let coveragePhrase = coverageQualifier(subset: aqi.count, of: events.count)
        let bins: [(label: String, range: Range<Double>)] = [
            ("Good\n0–50", 0..<51),
            ("Moderate\n51–100", 51..<101),
            ("USG\n101–150", 101..<151),
            ("Unhealthy\n151–200", 151..<201),
            ("Worse\n201+", 201..<10000)
        ]
        let total = aqi.count
        var topShare = 0.0
        var topLabel = ""
        let raw = bins.map { bin -> Bucket in
            let c = aqi.filter { bin.range.contains($0) }.count
            let share = Double(c) / Double(total)
            if share > topShare { topShare = share; topLabel = bin.label }
            return Bucket(label: bin.label, share: share, count: c, isPeak: false)
        }
        let buckets = raw.map { Bucket(label: $0.label, share: $0.share, count: $0.count, isPeak: $0.label == topLabel) }
        return Insight(
            id: "aqi",
            category: .airQuality,
            icon: "aqi.medium",
            title: "Elevated air quality",
            detail: "\(percent(elevated)) of your headaches\(coveragePhrase) happened with US AQI ≥ 75.",
            strength: elevated,
            whyItMatters: "Particulate matter and ozone can trigger or amplify headaches via inflammatory pathways. AQI of 75–100 is where sensitive groups typically start to feel effects; 150+ is unhealthy for everyone. On bad-air days, indoor mitigations (HEPA filters, closed windows, masks outdoors) can meaningfully reduce exposure.",
            yourPattern: "\(percent(elevated)) of your headaches\(coveragePhrase) occurred with US AQI at or above 75 — the threshold where sensitive groups commonly start to feel effects.",
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: "Air quality at headache onset (US AQI)"
            )
        )
    }

    private static func hrvInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.hrvSDNNMs)
        guard values.count >= minimumSampleSize else { return nil }
        let med = median(values)
        // Median HRV inside the typical adult range (35–80 ms SDNN) reads as a generic stat, not
        // a pattern. Surface only when the user's pre-headache median is meaningfully low or high.
        guard med < 35 || med > 80 else { return nil }
        let bins: [(label: String, range: Range<Double>)] = [
            ("<30", 0..<30),
            ("30–50", 30..<50),
            ("50–80", 50..<80),
            ("80+", 80..<10000)
        ]
        let total = values.count
        let medBin = bins.firstIndex { $0.range.contains(med) } ?? 1
        let buckets: [Bucket] = bins.enumerated().map { idx, bin in
            let c = values.filter { bin.range.contains($0) }.count
            return Bucket(
                label: bin.label,
                share: Double(c) / Double(total),
                count: c,
                isPeak: idx == medBin
            )
        }
        return Insight(
            id: "hrv",
            category: .heart,
            icon: "waveform.path.ecg",
            title: "HRV around your headaches",
            detail: "Median HRV (SDNN) when you've logged a headache: \(String(format: "%.0f ms", med)).",
            strength: 0.30,
            whyItMatters: "Heart-rate variability tracks autonomic nervous-system balance. Lower HRV is associated with stress, poor recovery, and — for many migraine sufferers — the prodrome window 12–24 hours before an attack. Watching multi-day HRV trends can give an early warning that your threshold is dropping.",
            yourPattern: "Your median pre-headache HRV (SDNN) is \(String(format: "%.0f ms", med)). The chart shows where your HRV typically sat at the moment you logged.",
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: "HRV (SDNN, ms) at headache onset"
            )
        )
    }

    private static func humidityInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.humidityPercent)
        guard values.count >= minimumSampleSize else { return nil }
        let high = Double(values.filter { $0 >= 70 }.count) / Double(values.count)
        guard high >= 0.40 else { return nil }
        let bins: [(label: String, range: Range<Double>)] = [
            ("<40%", 0..<40),
            ("40–60%", 40..<60),
            ("60–80%", 60..<80),
            ("80%+", 80..<101)
        ]
        let total = values.count
        var topShare = 0.0
        var topLabel = ""
        let raw = bins.map { bin -> Bucket in
            let c = values.filter { bin.range.contains($0) }.count
            let share = Double(c) / Double(total)
            if share > topShare { topShare = share; topLabel = bin.label }
            return Bucket(label: bin.label, share: share, count: c, isPeak: false)
        }
        let buckets = raw.map { Bucket(label: $0.label, share: $0.share, count: $0.count, isPeak: $0.label == topLabel) }
        return Insight(
            id: "humidity",
            category: .weather,
            icon: "humidity.fill",
            title: "High humidity pattern",
            detail: "\(percent(high)) of your headaches happened with humidity at or above 70%.",
            strength: high * 0.7,
            whyItMatters: "High humidity reduces evaporative cooling and often co-occurs with the pressure drops that precede storms — a one-two punch flagged in many migraine-trigger studies. Air conditioning, hydration, and electrolyte salts are commonly suggested mitigations on muggy days.",
            yourPattern: "\(percent(high)) of your headaches occurred with humidity ≥ 70%. The chart shows the full breakdown.",
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: "Relative humidity at headache onset"
            )
        )
    }

    private static func severityInsight(_ events: [HeadacheEvent]) -> Insight? {
        let order: [HeadacheSeverity] = [.slight, .medium, .extreme]
        var counts: [HeadacheSeverity: Int] = [:]
        var total = 0
        for event in events {
            if let severity = event.severity {
                counts[severity, default: 0] += 1
                total += 1
            }
        }
        guard total >= minimumSampleSize else { return nil }
        guard let (top, topCount) = counts.max(by: { $0.value < $1.value }) else { return nil }
        let topShare = Double(topCount) / Double(total)
        // With three buckets the even baseline is 33%. Surface only when one severity clearly
        // dominates (>=50%) — at 40% the "pattern" is barely above chance.
        guard topShare >= 0.50 else { return nil }
        let buckets: [Bucket] = order.map { sev in
            let c = counts[sev] ?? 0
            return Bucket(
                label: label(for: sev),
                share: total > 0 ? Double(c) / Double(total) : 0,
                count: c,
                isPeak: sev == top
            )
        }
        let baseline = 1.0 / 3.0
        return Insight(
            id: "severity",
            category: .severity,
            icon: "exclamationmark.triangle.fill",
            title: "Most often: \(label(for: top))",
            detail: "\(percent(topShare)) of headaches you've rated were \(label(for: top).lowercased()).",
            strength: topShare - baseline,
            whyItMatters: "Knowing your typical severity distribution helps frame conversations with a clinician. Frequent extreme attacks — even if they're not your most common bucket — often justify a preventive treatment plan rather than rescue meds alone.",
            yourPattern: "\(percent(topShare)) of your rated headaches were \(label(for: top).lowercased()) — \(String(format: "%.1fx", topShare / baseline)) the even baseline of \(percent(baseline)).",
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: baseline,
                axisCaption: "Severity distribution across rated headaches"
            )
        )
    }

    // MARK: - Helpers

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// Returns " (of the N with weather/health data)" when we're computing a percentage over a
    /// strict subset of events, so users don't read the headline as "X% of every headache I've logged".
    /// Empty string when coverage is full.
    private static func coverageQualifier(subset: Int, of total: Int) -> String {
        guard subset > 0, subset < total else { return "" }
        return " (of the \(subset) with available data)"
    }

    private static func formatHours(_ hours: Double) -> String {
        let total = max(0, hours)
        let h = Int(total)
        let m = Int((total - Double(h)) * 60)
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    private static func othersSummary(_ buckets: [Bucket], excluding peakLabel: String, label: (Bucket) -> String) -> String {
        let rest = buckets.filter { $0.label != peakLabel }
        let parts = rest.map { "\(label($0)) \(Int(($0.share * 100).rounded()))%" }
        return "Others — " + parts.joined(separator: ", ") + "."
    }

    private static func label(for part: PartOfDay) -> String {
        switch part {
        case .overnight: return "Overnight"
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        }
    }

    private static func icon(for part: PartOfDay) -> String {
        switch part {
        case .overnight: return "moon.stars.fill"
        case .morning: return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "sunset.fill"
        }
    }

    private static func label(for severity: HeadacheSeverity) -> String {
        switch severity {
        case .slight: return "Slight"
        case .medium: return "Medium"
        case .extreme: return "Extreme"
        }
    }

    private static func label(for trend: PressureTrend) -> String {
        switch trend {
        case .falling: return "Falling"
        case .rising: return "Rising"
        case .steady: return "Steady"
        case .unavailable: return "Unknown"
        }
    }
}
