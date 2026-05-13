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
        if let item = temperatureInsight(events) { insights.append(item) }
        if let item = precipitationInsight(events) { insights.append(item) }
        if let item = windInsight(events) { insights.append(item) }
        if let item = caffeineInsight(events) { insights.append(item) }
        if let item = hydrationInsight(events) { insights.append(item) }
        if let item = exerciseInsight(events) { insights.append(item) }
        if let item = pollenInsight(events) { insights.append(item) }
        if let item = bloodPressureInsight(events) { insights.append(item) }
        if let item = oxygenSaturationInsight(events) { insights.append(item) }
        if let item = daylightInsight(events) { insights.append(item) }
        if let item = audioExposureInsight(events) { insights.append(item) }
        if let item = hoursSinceWakeInsight(events) { insights.append(item) }
        if let item = menstrualCycleInsight(events) { insights.append(item) }
        if let item = motionActivityInsight(events) { insights.append(item) }
        if let item = multivariateInsight(events, dailyRecords: dailyRecords) { insights.append(item) }

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

    // MARK: - Temperature

    private static func temperatureInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.apparentTemperatureC)
        guard values.count >= minimumSampleSize else { return nil }
        let bins: [(label: String, range: Range<Double>)] = [
            ("Very cold\n<0°C", -100..<0),
            ("Cold\n0–10°C", 0..<10),
            ("Cool\n10–18°C", 10..<18),
            ("Mild\n18–25°C", 18..<25),
            ("Warm\n25–32°C", 25..<32),
            ("Hot\n32°C+", 32..<100)
        ]
        let total = values.count
        let coveragePhrase = coverageQualifier(subset: total, of: events.count)
        var topShare = 0.0
        var topLabel = ""
        let raw = bins.map { bin -> (label: String, count: Int, share: Double) in
            let c = values.filter { bin.range.contains($0) }.count
            let s = Double(c) / Double(total)
            if s > topShare { topShare = s; topLabel = bin.label }
            return (bin.label, c, s)
        }
        guard topShare >= 0.35 else { return nil }
        let baseline = 1.0 / Double(bins.count)
        guard topShare / baseline >= 1.5 else { return nil }
        let buckets = raw.map { Bucket(label: $0.label, share: $0.share, count: $0.count, isPeak: $0.label == topLabel) }
        let isExtreme = topLabel.hasPrefix("Very cold") || topLabel.hasPrefix("Hot")
        let icon = topLabel.hasPrefix("Very cold") || topLabel.hasPrefix("Cold") ? "thermometer.snowflake" : "thermometer.sun.fill"
        let title = isExtreme ? "\(topLabel) weather cluster" : "Temperature cluster: \(topLabel)"
        return Insight(
            id: "temperature",
            category: .weather,
            icon: icon,
            title: title,
            detail: "\(percent(topShare)) of your headaches\(coveragePhrase) happened when it felt \(topLabel.lowercased()).",
            strength: topShare,
            whyItMatters: "Extreme temperatures — both hot and cold — are well-documented migraine triggers. Heat causes vasodilation and dehydration; cold triggers vasoconstriction and muscle tension. The apparent temperature (feels-like) accounts for wind chill and humidity, making it more relevant than raw air temperature.",
            yourPattern: "\(percent(topShare)) of your headaches\(coveragePhrase) occurred in \(topLabel.lowercased()) conditions — \(String(format: "%.1fx", topShare / baseline)) the even baseline of \(percent(baseline)). " + othersSummary(buckets, excluding: topLabel, label: \.label),
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: baseline,
                axisCaption: "Apparent temperature at headache onset"
            )
        )
    }

    // MARK: - Precipitation

    private static func precipitationInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.precipitationMm)
        guard values.count >= minimumSampleSize else { return nil }
        let dry = values.filter { $0 == 0 }.count
        let light = values.filter { $0 > 0 && $0 < 2.5 }.count
        let moderate = values.filter { $0 >= 2.5 && $0 < 10 }.count
        let heavy = values.filter { $0 >= 10 }.count
        let total = values.count
        let dryShare = Double(dry) / Double(total)
        let rainShare = 1.0 - dryShare
        guard rainShare >= 0.35, dryShare > 0 else { return nil }
        let coveragePhrase = coverageQualifier(subset: total, of: events.count)
        let buckets = [
            Bucket(label: "Dry", share: Double(dry) / Double(total), count: dry, isPeak: false),
            Bucket(label: "Light\n<2.5mm", share: Double(light) / Double(total), count: light, isPeak: false),
            Bucket(label: "Moderate\n2.5–10mm", share: Double(moderate) / Double(total), count: moderate, isPeak: false),
            Bucket(label: "Heavy\n10mm+", share: Double(heavy) / Double(total), count: heavy, isPeak: false),
        ]
        let topBucket = buckets.dropFirst().max(by: { $0.share < $1.share }) ?? buckets[1]
        let peaked = buckets.map { Bucket(label: $0.label, share: $0.share, count: $0.count, isPeak: $0.label == topBucket.label) }
        return Insight(
            id: "precipitation",
            category: .weather,
            icon: "cloud.rain.fill",
            title: "Rainy-day cluster",
            detail: "\(percent(rainShare)) of your headaches\(coveragePhrase) happened during rain (\(percent(topBucket.share)) in the \(topBucket.label.lowercased()) band).",
            strength: rainShare,
            whyItMatters: "Rainy weather often co-occurs with falling barometric pressure, high humidity, and reduced light — a multi-factor trigger cocktail. The relationship may be indirect: people tend to stay indoors, sleep differently, or alter caffeine habits on rainy days.",
            yourPattern: "\(percent(rainShare)) of your headaches\(coveragePhrase) occurred during active precipitation, with the most common intensity being \(topBucket.label.lowercased()).",
            breakdown: Breakdown(
                buckets: peaked,
                evenBaseline: nil,
                axisCaption: "Precipitation at headache onset"
            )
        )
    }

    // MARK: - Wind

    private static func windInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.windSpeedKph)
        guard values.count >= minimumSampleSize else { return nil }
        let bins: [(label: String, range: Range<Double>)] = [
            ("Calm\n<5", 0..<5),
            ("Light\n5–15", 5..<15),
            ("Moderate\n15–30", 15..<30),
            ("Windy\n30+", 30..<500)
        ]
        let total = values.count
        let coveragePhrase = coverageQualifier(subset: total, of: events.count)
        var topShare = 0.0
        var topLabel = ""
        let raw = bins.map { bin -> (label: String, count: Int, share: Double) in
            let c = values.filter { bin.range.contains($0) }.count
            let s = Double(c) / Double(total)
            if s > topShare { topShare = s; topLabel = bin.label }
            return (bin.label, c, s)
        }
        let isWindyPeak = topLabel == "Windy\n30+" || topLabel == "Moderate\n15–30"
        guard isWindyPeak, topShare >= 0.30 else { return nil }
        let buckets = raw.map { Bucket(label: $0.label, share: $0.share, count: $0.count, isPeak: $0.label == topLabel) }
        return Insight(
            id: "wind",
            category: .weather,
            icon: "wind",
            title: "Windy conditions",
            detail: "\(percent(topShare)) of your headaches\(coveragePhrase) happened with \(topLabel.lowercased().replacingOccurrences(of: "\n", with: " ")) wind speeds.",
            strength: topShare,
            whyItMatters: "Strong winds can trigger headaches through several mechanisms: drying of mucous membranes, airborne pollen and particulate matter, barometric pressure fluctuations, and even the physical strain of bracing against gusts. Chinook and Santa Ana winds have documented associations with migraine onset.",
            yourPattern: "\(percent(topShare)) of your headaches\(coveragePhrase) occurred during \(topLabel.lowercased().replacingOccurrences(of: "\n", with: " ")) conditions.",
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: "Wind speed at headache onset (km/h)"
            )
        )
    }

    // MARK: - Caffeine

    private static func caffeineInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.caffeineMgToday)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let med = median(values)
        let coveragePhrase = coverageQualifier(subset: total, of: events.count)
        let none = values.filter { $0 == 0 }.count
        let high = values.filter { $0 >= 200 }.count
        let veryHigh = values.filter { $0 >= 400 }.count
        let noneShare = Double(none) / Double(total)
        let highShare = Double(high) / Double(total)
        let veryHighShare = Double(veryHigh) / Double(total)
        // Surface if either extreme is meaningful: very high caffeine, or zero caffeine cluster.
        // For the "none" pattern, require that the user actually varies their intake
        // (at least some events with caffeine) so it's a withdrawal signal, not just
        // "I don't drink coffee."
        let hasCaffeineVariation = values.contains { $0 > 0 }
        let isHighPattern = highShare >= 0.30
        let isNonePattern = noneShare >= 0.40 && hasCaffeineVariation
        guard isHighPattern || isNonePattern else { return nil }
        let bins: [(label: String, range: Range<Double>)] = [
            ("None", 0..<0.5),
            ("Low\n1–100mg", 0.5..<100),
            ("Moderate\n100–200mg", 100..<200),
            ("High\n200–400mg", 200..<400),
            ("Very High\n400mg+", 400..<10000)
        ]
        var topShare = 0.0
        var topLabel = ""
        let raw = bins.map { bin -> (label: String, count: Int, share: Double) in
            let c = values.filter { bin.range.contains($0) }.count
            let s = Double(c) / Double(total)
            if s > topShare { topShare = s; topLabel = bin.label }
            return (bin.label, c, s)
        }
        let buckets = raw.map { Bucket(label: $0.label, share: $0.share, count: $0.count, isPeak: $0.label == topLabel) }
        if isNonePattern && noneShare >= highShare {
            return Insight(
                id: "caffeine-none",
                category: .heart,
                icon: "cup.and.saucer.fill",
                title: "Low-caffeine days",
                detail: "\(percent(noneShare)) of your headaches\(coveragePhrase) happened on days with zero caffeine (\(percent(highShare)) high-caffeine days). Median: \(String(format: "%.0f mg", med)).",
                strength: noneShare,
                whyItMatters: "Caffeine withdrawal is a well-recognized headache trigger — even skipping your usual morning coffee can precipitate a headache within hours. The relationship is U-shaped: both zero and excess caffeine can trigger attacks. Tracking your individual threshold is key.",
                yourPattern: "\(percent(noneShare)) of your headaches occurred on zero-caffeine days, with only \(percent(highShare)) on high-caffeine days (≥200mg).",
                breakdown: Breakdown(
                    buckets: buckets,
                    evenBaseline: nil,
                    axisCaption: "Daily caffeine consumption before headaches"
                )
            )
        } else {
            return Insight(
                id: "caffeine-high",
                category: .heart,
                icon: "cup.and.saucer.fill",
                title: "High-caffeine days",
                detail: "\(percent(highShare)) of your headaches\(coveragePhrase) happened on days with 200mg+ caffeine (\(percent(veryHighShare)) above 400mg). Median: \(String(format: "%.0f mg", med)).",
                strength: highShare,
                whyItMatters: "Caffeine is a double-edged sword for headache sufferers: it can provide acute relief (it's in many rescue medications), but daily high intake can lead to medication-overuse headache and withdrawal cycles. The U-shaped risk curve means both too much and too little can trigger attacks.",
                yourPattern: "\(percent(highShare)) of your headaches occurred on high-caffeine days (≥200mg), including \(percent(veryHighShare)) on very high days (≥400mg).",
                breakdown: Breakdown(
                    buckets: buckets,
                    evenBaseline: nil,
                    axisCaption: "Daily caffeine consumption before headaches"
                )
            )
        }
    }

    // MARK: - Hydration

    private static func hydrationInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.waterMlToday)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let med = median(values)
        let coveragePhrase = coverageQualifier(subset: total, of: events.count)
        let low = values.filter { $0 < 1000 }.count
        let veryLow = values.filter { $0 < 500 }.count
        let lowShare = Double(low) / Double(total)
        guard lowShare >= 0.40 else { return nil }
        let bins: [(label: String, range: Range<Double>)] = [
            ("Very Low\n<500mL", 0..<500),
            ("Low\n500–1000mL", 500..<1000),
            ("Moderate\n1000–2000mL", 1000..<2000),
            ("Adequate\n2000mL+", 2000..<20000)
        ]
        var topShare = 0.0
        var topLabel = ""
        let raw = bins.map { bin -> (label: String, count: Int, share: Double) in
            let c = values.filter { bin.range.contains($0) }.count
            let s = Double(c) / Double(total)
            if s > topShare { topShare = s; topLabel = bin.label }
            return (bin.label, c, s)
        }
        let buckets = raw.map { Bucket(label: $0.label, share: $0.share, count: $0.count, isPeak: $0.label == topLabel) }
        return Insight(
            id: "hydration",
            category: .weather,
            icon: "drop.fill",
            title: "Low hydration pattern",
            detail: "\(percent(lowShare)) of your headaches\(coveragePhrase) happened with under 1L of water that day (\(percent(Double(veryLow) / Double(total))) under 500mL). Median: \(String(format: "%.0f mL", med)).",
            strength: lowShare,
            whyItMatters: "Even mild dehydration (1–2% body water loss) can trigger headaches and impair concentration — one of the most easily preventable triggers. The brain is highly sensitive to fluid balance; reduced blood volume can lower oxygen delivery and trigger pain pathways.",
            yourPattern: "\(percent(lowShare)) of your headaches occurred on days with below 1,000 mL water intake, including \(percent(Double(veryLow) / Double(total))) under 500 mL. Your median intake on headache days was \(String(format: "%.0f mL", med)).",
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: "Daily water intake before headaches"
            )
        )
    }

    // MARK: - Exercise

    private static func exerciseInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.exerciseMinutesToday)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let coveragePhrase = coverageQualifier(subset: total, of: events.count)
        // Check for exertion pattern — headaches after exercise
        let moderate = values.filter { $0 >= 15 }.count
        let moderateShare = Double(moderate) / Double(total)
        guard moderateShare >= 0.20 else { return nil }
        let bins: [(label: String, range: Range<Double>)] = [
            ("None", 0..<0.5),
            ("Light\n1–15m", 0.5..<15),
            ("Moderate\n15–45m", 15..<45),
            ("Active\n45m+", 45..<1000)
        ]
        var topShare = 0.0
        var topLabel = ""
        let raw = bins.map { bin -> (label: String, count: Int, share: Double) in
            let c = values.filter { bin.range.contains($0) }.count
            let s = Double(c) / Double(total)
            if s > topShare { topShare = s; topLabel = bin.label }
            return (bin.label, c, s)
        }
        let buckets = raw.map { Bucket(label: $0.label, share: $0.share, count: $0.count, isPeak: $0.label == topLabel) }
        return Insight(
            id: "exercise-exertion",
            category: .heart,
            icon: "figure.run",
            title: "Exertion-linked",
            detail: "\(percent(moderateShare)) of your headaches\(coveragePhrase) followed 15+ minutes of exercise.",
            strength: moderateShare,
            whyItMatters: "Exercise-induced headaches can occur during or after strenuous activity, likely from venous pressure spikes and cranial vasodilation. The distinction from 'protective' exercise effects depends on individual conditioning and hydration status before activity.",
            yourPattern: "\(percent(moderateShare)) of your headaches occurred on days with 15+ minutes of exercise.",
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: "Exercise minutes on headache days"
            )
        )
    }

    // MARK: - Pollen

    private static func pollenInsight(_ events: [HeadacheEvent]) -> Insight? {
        let keyPaths: [KeyPath<HeadacheEvent, Double?>] = [
            \.grassPollen, \.birchPollen, \.alderPollen,
            \.mugwortPollen, \.olivePollen, \.ragweedPollen
        ]
        let pollenNames = ["Grass", "Birch", "Alder", "Mugwort", "Olive", "Ragweed"]
        let thresholds: [Double] = [20, 30, 20, 10, 30, 10] // grains/m³ moderate thresholds per type

        // Count events where any pollen is elevated
        var elevatedCount = 0
        var typeElevated: [String: Int] = [:]
        var totalWithData = 0

        for event in events {
            var hasAnyData = false
            var hasElevated = false
            for (i, kp) in keyPaths.enumerated() {
                guard let val = event[keyPath: kp] else { continue }
                hasAnyData = true
                if val >= thresholds[i] {
                    hasElevated = true
                    typeElevated[pollenNames[i], default: 0] += 1
                }
            }
            if hasAnyData {
                totalWithData += 1
                if hasElevated { elevatedCount += 1 }
            }
        }

        guard totalWithData >= minimumSampleSize else { return nil }
        let elevatedShare = Double(elevatedCount) / Double(totalWithData)
        guard elevatedShare >= 0.30 else { return nil }
        let coveragePhrase = coverageQualifier(subset: totalWithData, of: events.count)
        let topType = typeElevated.max(by: { $0.value < $1.value })
        let topTypePhrase = topType.map { "\($0.key) (\(percent(Double($0.value) / Double(elevatedCount))))" } ?? "various types"
        let hasMultiple = typeElevated.count >= 3
        let title = hasMultiple ? "Multi-pollen elevation" : "Elevated \(topType?.key ?? "pollen")"
        return Insight(
            id: "pollen",
            category: .weather,
            icon: "leaf.fill",
            title: title,
            detail: "\(percent(elevatedShare)) of your headaches\(coveragePhrase) occurred when at least one pollen type was elevated. Most common: \(topTypePhrase).",
            strength: elevatedShare,
            whyItMatters: "Pollen triggers allergic rhinitis, which causes sinus congestion and inflammation — a known headache precipitant. The relationship may be seasonal: tree pollen in spring, grass in summer, ragweed in autumn. Indoor air filtration can help during high-pollen periods.",
            yourPattern: "\(percent(elevatedShare)) of your headaches with pollen data occurred on days with elevated pollen levels, most commonly \(topTypePhrase).",
            breakdown: Breakdown(
                buckets: [
                    Bucket(label: "No elevation", share: 1.0 - elevatedShare, count: totalWithData - elevatedCount, isPeak: false),
                    Bucket(label: "Elevated", share: elevatedShare, count: elevatedCount, isPeak: true),
                ],
                evenBaseline: nil,
                axisCaption: "Pollen elevation at headache onset"
            )
        )
    }

    // MARK: - Blood Pressure

    private static func bloodPressureInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.bloodPressureSystolicMmHg)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let med = median(values)
        let coveragePhrase = coverageQualifier(subset: total, of: events.count)
        let elevated = values.filter { $0 >= 130 }.count
        let elevatedShare = Double(elevated) / Double(total)
        let high = values.filter { $0 >= 140 }.count
        let highShare = Double(high) / Double(total)
        guard elevatedShare >= 0.30 else { return nil }
        let bins: [(label: String, range: Range<Double>)] = [
            ("Normal\n<120", 0..<120),
            ("Elevated\n120–129", 120..<130),
            ("High\n130–140", 130..<140),
            ("Very High\n140+", 140..<500)
        ]
        var topShare = 0.0
        var topLabel = ""
        let raw = bins.map { bin -> (label: String, count: Int, share: Double) in
            let c = values.filter { bin.range.contains($0) }.count
            let s = Double(c) / Double(total)
            if s > topShare { topShare = s; topLabel = bin.label }
            return (bin.label, c, s)
        }
        let buckets = raw.map { Bucket(label: $0.label, share: $0.share, count: $0.count, isPeak: $0.label == topLabel) }
        return Insight(
            id: "blood-pressure",
            category: .heart,
            icon: "heart.text.square.fill",
            title: "Elevated blood pressure",
            detail: "\(percent(elevatedShare)) of your headaches\(coveragePhrase) showed systolic BP ≥130 (\(percent(highShare)) ≥140). Median: \(String(format: "%.0f mmHg", med)).",
            strength: elevatedShare,
            whyItMatters: "Hypertension is a known headache risk factor, particularly for morning headaches and posterior-head pain. The relationship may be bidirectional — pain elevates BP, and elevated BP can trigger headache. Sustained readings ≥130/80 warrant clinical evaluation.",
            yourPattern: "\(percent(elevatedShare)) of your headaches with BP data occurred with elevated systolic readings (≥130), including \(percent(highShare)) at hypertensive levels (≥140).",
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: "Systolic BP at headache onset (mmHg)"
            )
        )
    }

    // MARK: - Oxygen Saturation

    private static func oxygenSaturationInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.oxygenSaturationPercent)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let coveragePhrase = coverageQualifier(subset: total, of: events.count)
        let low = values.filter { $0 < 95 }.count
        let lowShare = Double(low) / Double(total)
        guard lowShare >= 0.30 else { return nil }
        return Insight(
            id: "oxygen-saturation",
            category: .heart,
            icon: "lungs.fill",
            title: "Lower oxygen saturation",
            detail: "\(percent(lowShare)) of your headaches\(coveragePhrase) showed SpO₂ below 95%.",
            strength: lowShare * 0.8,
            whyItMatters: "Low blood oxygen can trigger headaches through cerebral vasodilation — the brain increases blood flow to compensate for reduced oxygen delivery. Sustained readings below 92% are clinically significant and may warrant discussing sleep apnea screening with a doctor.",
            yourPattern: "\(percent(lowShare)) of your headaches with oxygen data occurred with SpO₂ below 95%.",
            breakdown: Breakdown(
                buckets: [
                    Bucket(label: "Normal\n95–100%", share: 1.0 - lowShare, count: total - low, isPeak: false),
                    Bucket(label: "Low\n<95%", share: lowShare, count: low, isPeak: true),
                ],
                evenBaseline: nil,
                axisCaption: "Oxygen saturation at headache onset"
            )
        )
    }

    // MARK: - Time in Daylight

    private static func daylightInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.timeInDaylightMinutesToday)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let med = median(values)
        let coveragePhrase = coverageQualifier(subset: total, of: events.count)
        let veryLow = values.filter { $0 < 15 }.count
        let high = values.filter { $0 >= 120 }.count
        let veryLowShare = Double(veryLow) / Double(total)
        let highShare = Double(high) / Double(total)
        // Surface if either extreme is meaningful
        guard veryLowShare >= 0.35 || highShare >= 0.30 else { return nil }
        let isLowPattern = veryLowShare >= highShare
        let bins: [(label: String, range: Range<Double>)] = [
            ("Very Low\n<15m", 0..<15),
            ("Low\n15–60m", 15..<60),
            ("Moderate\n60–120m", 60..<120),
            ("High\n120m+", 120..<10000)
        ]
        var topShare = 0.0
        var topLabel = ""
        let raw = bins.map { bin -> (label: String, count: Int, share: Double) in
            let c = values.filter { bin.range.contains($0) }.count
            let s = Double(c) / Double(total)
            if s > topShare { topShare = s; topLabel = bin.label }
            return (bin.label, c, s)
        }
        let buckets = raw.map { Bucket(label: $0.label, share: $0.share, count: $0.count, isPeak: $0.label == topLabel) }
        if isLowPattern {
            return Insight(
                id: "daylight-low",
                category: .weather,
                icon: "moon.fill",
                title: "Low daylight exposure",
                detail: "\(percent(veryLowShare)) of your headaches\(coveragePhrase) happened on days with under 15 minutes of daylight exposure.",
                strength: veryLowShare,
                whyItMatters: "Low daylight exposure may reflect more time indoors, which correlates with screen use, artificial lighting, reduced movement, and irregular sleep-wake cycles — all potential headache contributors. It can also disrupt circadian rhythm via reduced morning light.",
                yourPattern: "\(percent(veryLowShare)) of your headaches occurred on days with under 15 minutes of daylight, median \(String(format: "%.0f min", med)).",
                breakdown: Breakdown(
                    buckets: buckets,
                    evenBaseline: nil,
                    axisCaption: "Daylight exposure on headache days"
                )
            )
        } else {
            return Insight(
                id: "daylight-high",
                category: .weather,
                icon: "sun.max.fill",
                title: "High daylight exposure",
                detail: "\(percent(highShare)) of your headaches\(coveragePhrase) happened on days with 2+ hours of daylight exposure.",
                strength: highShare,
                whyItMatters: "Bright sunlight is a well-known migraine trigger, likely through the trigeminal-autonomic reflex and glare sensitivity. Photophobia is one of the diagnostic criteria for migraine — many sufferers are more sensitive to light between attacks, not just during them.",
                yourPattern: "\(percent(highShare)) of your headaches occurred on days with 2+ hours of daylight exposure.",
                breakdown: Breakdown(
                    buckets: buckets,
                    evenBaseline: nil,
                    axisCaption: "Daylight exposure on headache days"
                )
            )
        }
    }

    // MARK: - Environmental Audio

    private static func audioExposureInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.environmentalAudioExposureDbA)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let coveragePhrase = coverageQualifier(subset: total, of: events.count)
        let elevated = values.filter { $0 >= 70 }.count
        let elevatedShare = Double(elevated) / Double(total)
        guard elevatedShare >= 0.30 else { return nil }
        let bins: [(label: String, range: Range<Double>)] = [
            ("Quiet\n<55dBA", 0..<55),
            ("Moderate\n55–70dBA", 55..<70),
            ("Loud\n70–80dBA", 70..<80),
            ("Very Loud\n80dBA+", 80..<200)
        ]
        var topShare = 0.0
        var topLabel = ""
        let raw = bins.map { bin -> (label: String, count: Int, share: Double) in
            let c = values.filter { bin.range.contains($0) }.count
            let s = Double(c) / Double(total)
            if s > topShare { topShare = s; topLabel = bin.label }
            return (bin.label, c, s)
        }
        let buckets = raw.map { Bucket(label: $0.label, share: $0.share, count: $0.count, isPeak: $0.label == topLabel) }
        return Insight(
            id: "audio-exposure",
            category: .weather,
            icon: "ear.fill",
            title: "Elevated noise environment",
            detail: "\(percent(elevatedShare)) of your headaches\(coveragePhrase) happened in noisy environments (≥70 dBA).",
            strength: elevatedShare * 0.7,
            whyItMatters: "Sustained noise exposure is both a trigger (sensory overload) and a consequence (phonophobia during prodrome) of migraine. Levels above 70 dBA are comparable to busy street traffic — enough to raise stress hormones and muscle tension even if you're not consciously aware of it.",
            yourPattern: "\(percent(elevatedShare)) of your headaches with audio data occurred in environments at or above 70 decibels.",
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: "Environmental audio level at headache onset"
            )
        )
    }

    // MARK: - Hours Since Waking

    private static func hoursSinceWakeInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.hoursSinceMainSleepWake)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let med = median(values)
        let coveragePhrase = coverageQualifier(subset: total, of: events.count)
        let bins: [(label: String, range: Range<Double>)] = [
            ("0–2h", 0..<2),
            ("2–4h", 2..<4),
            ("4–8h", 4..<8),
            ("8–12h", 8..<12),
            ("12h+", 12..<48)
        ]
        var topShare = 0.0
        var topLabel = ""
        var topIdx = 0
        let raw = bins.enumerated().map { (idx, bin) -> (label: String, count: Int, share: Double) in
            let c = values.filter { bin.range.contains($0) }.count
            let s = Double(c) / Double(total)
            if s > topShare { topShare = s; topLabel = bin.label; topIdx = idx }
            return (bin.label, c, s)
        }
        let baseline = 1.0 / Double(bins.count)
        let multiple = topShare / baseline
        guard multiple >= 1.5 else { return nil }
        let buckets = raw.map { Bucket(label: $0.label, share: $0.share, count: $0.count, isPeak: $0.label == topLabel) }
        let earlyCluster = topIdx <= 1
        return Insight(
            id: "hours-since-wake",
            category: .time,
            icon: earlyCluster ? "sunrise.fill" : "clock.fill",
            title: earlyCluster ? "Early post-wake cluster" : "Hours since waking",
            detail: "\(percent(topShare)) of your headaches\(coveragePhrase) hit \(topLabel.lowercased()) after waking (median: \(formatHours(med))).",
            strength: topShare,
            whyItMatters: "The time between waking and headache onset can help identify specific triggers: early-morning headaches may relate to sleep quality, caffeine withdrawal, or blood pressure morning surge; late-day headaches often track accumulated triggers — screen time, skipped meals, stress build-up, or eye strain.",
            yourPattern: "\(percent(topShare)) of your headaches occur \(topLabel.lowercased()) after waking — \(String(format: "%.1fx", multiple)) the even baseline. Median: \(formatHours(med)).",
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: baseline,
                axisCaption: "Hours since waking at headache onset"
            )
        )
    }

    // MARK: - Menstrual Cycle

    private static func menstrualCycleInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.daysSinceLastPeriodStart)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let coveragePhrase = coverageQualifier(subset: total, of: events.count)
        // Standard cycle phases: follicular (0–13), ovulation (~14), luteal (14–28), extended (28+)
        let follicular = values.filter { $0 >= 0 && $0 < 14 }.count
        let luteal = values.filter { $0 >= 14 && $0 < 28 }.count
        let extended = values.filter { $0 >= 28 }.count
        let follicularShare = Double(follicular) / Double(total)
        let lutealShare = Double(luteal) / Double(total)
        let extendedShare = Double(extended) / Double(total)
        // Luteal phase elevation is the most clinically relevant pattern
        guard lutealShare >= 0.35, lutealShare >= follicularShare * 1.3 else { return nil }
        let buckets = [
            Bucket(label: "Follicular\nDays 0–13", share: follicularShare, count: follicular, isPeak: false),
            Bucket(label: "Luteal\nDays 14–28", share: lutealShare, count: luteal, isPeak: true),
            Bucket(label: "Extended\n28+ days", share: extendedShare, count: extended, isPeak: false),
        ]
        return Insight(
            id: "menstrual-cycle",
            category: .severity,
            icon: "facemask.fill",
            title: "Luteal phase link",
            detail: "\(percent(lutealShare)) of logged headaches\(coveragePhrase) landed in the luteal phase (days 14–28).",
            strength: lutealShare - follicularShare,
            whyItMatters: "Menstrual migraine is a well-characterized subtype linked to the natural drop in estrogen during the late luteal phase. These headaches tend to be longer, more severe, and less responsive to standard rescue meds. Tracking across cycles can help time preventive treatment.",
            yourPattern: "\(percent(lutealShare)) of your headaches with cycle data occurred in the luteal phase, compared to \(percent(follicularShare)) in the follicular phase.",
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: "Cycle phase at headache onset"
            )
        )
    }

    // MARK: - Motion Activity

    private static func motionActivityInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.motionActivity)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let coveragePhrase = coverageQualifier(subset: total, of: events.count)
        let order: [MotionActivity] = [.stationary, .walking, .running, .automotive, .cycling, .unknown]
        var counts: [MotionActivity: Int] = [:]
        for v in values { counts[v, default: 0] += 1 }
        guard let (top, topCount) = counts.max(by: { $0.value < $1.value }), topCount > 0 else { return nil }
        // Don't surface "stationary" — people sit to log headaches, that's expected.
        // Only surface when a non-stationary activity dominates.
        guard top != .stationary, top != .unknown else { return nil }
        let topShare = Double(topCount) / Double(total)
        guard topShare >= 0.50 else { return nil }
        let buckets: [Bucket] = order.map { act in
            let c = counts[act] ?? 0
            return Bucket(
                label: label(for: act),
                share: Double(c) / Double(total),
                count: c,
                isPeak: act == top
            )
        }
        return Insight(
            id: "motion-activity",
            category: .time,
            icon: "figure.walk",
            title: "Active when headaches hit",
            detail: "\(percent(topShare)) of your headaches\(coveragePhrase) were logged while \(label(for: top).lowercased()).",
            strength: topShare,
            whyItMatters: "Some people experience exertion-triggered headaches from increased cranial pressure during activity. If this pattern is strong, consider whether onset consistently follows specific movements or postures.",
            yourPattern: "\(percent(topShare)) of your headaches were logged while \(label(for: top).lowercased()).",
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: "Activity at headache onset"
            )
        )
    }

    // MARK: - Multivariate Co-occurrence

    private static func multivariateInsight(_ events: [HeadacheEvent], dailyRecords: [DailyRecord]) -> Insight? {
        guard events.count >= minimumSampleSize * 2 else { return nil }
        // Define meaningful binary conditions using existing computed properties
        struct Condition: Hashable {
            let id: String
            let label: String
        }
        let conditions: [(Condition, (HeadacheEvent) -> Bool)] = [
            (Condition(id: "low-sleep", label: "Less than 6h sleep"), { $0.sleepHoursLastNight ?? 8 < 6 }),
            (Condition(id: "falling-pressure", label: "Falling pressure"), { $0.pressureTrend == .falling }),
            (Condition(id: "high-aqi", label: "US AQI ≥ 75"), { ($0.usAQI ?? 0) >= 75 }),
            (Condition(id: "high-humidity", label: "Humidity ≥ 70%"), { ($0.humidityPercent ?? 0) >= 70 }),
            (Condition(id: "high-caffeine", label: "Caffeine ≥ 200 mg"), { ($0.caffeineMgToday ?? 0) >= 200 }),
            (Condition(id: "low-water", label: "Water < 1 L"), { ($0.waterMlToday ?? 2000) < 1000 }),
            (Condition(id: "no-exercise", label: "Zero exercise"), { ($0.exerciseMinutesToday ?? 1) == 0 }),
        ]
        // Find all pairs that co-occur significantly
        let total = events.count
        var pairCounts: [(Condition, Condition, Int)] = []
        for i in 0..<conditions.count {
            for j in (i + 1)..<conditions.count {
                let (c1, f1) = conditions[i]
                let (c2, f2) = conditions[j]
                let co = events.filter { f1($0) && f2($0) }.count
                guard co >= min(3, total / 10) else { continue }
                pairCounts.append((c1, c2, co))
            }
        }
        guard !pairCounts.isEmpty else { return nil }
        let topPair = pairCounts.max(by: { $0.2 < $1.2 })!
        let (cond1, cond2, coCount) = topPair
        let coShare = Double(coCount) / Double(total)
        guard coShare >= 0.15 else { return nil }
        // Find individual rates for context
        let c1Count = events.filter { conditions.first(where: { $0.0.id == cond1.id })!.1($0) }.count
        let c2Count = events.filter { conditions.first(where: { $0.0.id == cond2.id })!.1($0) }.count
        // Lift: how much more does co-occurrence happen than expected by chance?
        let expectedShare = (Double(c1Count) / Double(total)) * (Double(c2Count) / Double(total))
        let lift = expectedShare > 0 ? coShare / expectedShare : 0
        guard lift >= 1.5 else { return nil }
        return Insight(
            id: "multivariate-\(cond1.id)-\(cond2.id)",
            category: .severity,
            icon: "link.circle.fill",
            title: "Trigger combination: \(cond1.label) & \(cond2.label.lowercased())",
            detail: "\(percent(coShare)) of your headaches hit when both occurred together — \(String(format: "%.1fx", lift)) more often than if they were independent.",
            strength: min(1.0, coShare * (1.0 + lift / 3.0)),
            whyItMatters: "Migraine triggers rarely act in isolation — most attacks result from a cumulative threshold being crossed ('bucket theory'). Identifying the specific combinations that precede your worst headache days is more actionable than looking at single factors alone, because it points to which protective measures matter most on a given day.",
            yourPattern: "\(percent(coShare)) of your headaches occurred when \(cond1.label.lowercased()) and \(cond2.label.lowercased()) coincided — \(String(format: "%.1fx", lift)) the rate expected by chance (\(percent(expectedShare))).",
            breakdown: Breakdown(
                buckets: [
                    Bucket(label: "Neither", share: 1.0 - (Double(c1Count) + Double(c2Count) - Double(coCount)) / Double(total), count: total - c1Count - c2Count + coCount, isPeak: false),
                    Bucket(label: cond1.label.split(separator: " ").prefix(1).joined(), share: Double(c1Count - coCount) / Double(total), count: c1Count - coCount, isPeak: false),
                    Bucket(label: cond2.label.split(separator: " ").prefix(1).joined(), share: Double(c2Count - coCount) / Double(total), count: c2Count - coCount, isPeak: false),
                    Bucket(label: "Both", share: coShare, count: coCount, isPeak: true),
                ],
                evenBaseline: nil,
                axisCaption: "Co-occurrence pattern"
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

    private static func label(for activity: MotionActivity) -> String {
        switch activity {
        case .stationary: return "Stationary"
        case .walking: return "Walking"
        case .running: return "Running"
        case .automotive: return "In a vehicle"
        case .cycling: return "Cycling"
        case .unknown: return "Unknown"
        }
    }
}
