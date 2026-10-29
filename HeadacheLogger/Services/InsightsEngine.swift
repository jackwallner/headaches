import Foundation

/// Pure analysis over the user's logged `HeadacheEvent`s. Computes pattern distributions
/// the user can act on without requiring a non-headache baseline.
///
/// All output is descriptive — "what does the data show?" rather than "what causes a headache?".
/// Nothing here leaves the device.
enum InsightsEngine {
    private static let insightDisclaimer = String(localized: "This is a pattern in your logged data. It does not show what caused a headache. It is not medical advice or a diagnosis.")

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

        var displayLabel: String {
            HeadacheTemperatureFormatting.localizedStoredText(label)
        }
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
        /// Reminder that the observed pattern does not establish a cause or provide medical advice.
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
        if let item = headacheFreeDayInsight(dailyRecords) { insights.append(item) }

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
        let yourPattern = String(localized: "\(percent(topShare)) of your logged headaches happened \(narrativeLabel(for: top)).")
        return Insight(
            id: "part-of-day",
            category: .time,
            icon: icon(for: top),
            title: String(localized: "Most common time: \(label(for: top))"),
            detail: String(localized: "\(percent(topShare)) of your logged headaches were logged \(narrativeLabel(for: top))."),
            strength: topShare,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: yourPattern,
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: baseline,
                axisCaption: String(localized: "Share of your headaches by part of day")
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
            return (i >= 0 && i < fullSymbols.count) ? fullSymbols[i] : String(localized: "a weekday")
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
        let yourPattern = String(localized: "\(percent(topShare)) of your headaches fall on \(topName), about \(formatMultiple(multiple)) the even baseline of \(percent(baseline)) per day.")
        return Insight(
            id: "weekday",
            category: .time,
            icon: "calendar",
            title: String(localized: "Headache day: \(topName)"),
            detail: String(localized: "\(percent(topShare)) of your headaches were logged on \(topName)."),
            strength: topShare - baseline,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: yourPattern,
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: baseline,
                axisCaption: String(localized: "Share of your headaches by weekday")
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
            let headlineLabel = HeadacheTemperatureFormatting.localizedStoredText(headline.label)
            let ratePct = Int(bucket.headacheRate * 100)
            let overallPct = Int(overallRate * 100)
            let moreLikely = headline.lift >= 2.0
                ? "\(formatNumber(headline.lift, fractionDigits: 1))×"
                : formatWholePercent(pct)
            detail = String(localized: "Headaches were logged \(moreLikely) more often after \(headlineLabel) of sleep (\(ratePct)% vs \(overallPct)% overall). Median: \(formatHours(med)).")
            strength = 0.5 + min((headline.lift - 1.0) / 2.0, 0.5)
            title = String(localized: "Low sleep: \(headlineLabel)")
            yourPattern = String(localized: "After \(headlineLabel) of sleep, headaches were logged on \(ratePct)% of days, compared with \(overallPct)% across days with sleep data. Median sleep before a headache: \(formatHours(med)).")
        } else {
            let lowSleepShare = Double(headacheSleepValues.filter { $0 < 6 }.count) / Double(total)
            if lowSleepShare >= 0.4 {
                detail = String(localized: "\(percent(lowSleepShare)) of your headaches followed a night with under 6 hours of sleep. Median: \(formatHours(med)).")
                strength = 0.5 + lowSleepShare * 0.4
            } else {
                detail = String(localized: "Median sleep the night before a headache: \(formatHours(med)).")
                strength = 0.35
            }
            title = String(localized: "Sleep before a headache")
            yourPattern = String(localized: "Median sleep the night before a headache: \(formatHours(med)). \(percent(lowSleepShare)) of your headaches followed a night under 6 hours.")
        }

        return Insight(
            id: "sleep",
            category: .sleep,
            icon: "bed.double.fill",
            title: title,
            detail: detail,
            strength: strength,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: yourPattern,
            breakdown: Breakdown(
                buckets: chartBuckets,
                evenBaseline: nil,
                axisCaption: String(localized: "Sleep duration the night before each headache")
            )
        )
    }

    private static func pressureTrendInsight(_ events: [HeadacheEvent]) -> Insight? {
        let trends = events.map(\.pressureTrend).filter { $0 != .unavailable }
        guard trends.count >= minimumSampleSize else { return nil }
        let order: [PressureTrend] = [.falling, .steady, .rising]
        let total = trends.count
        let coverageSubset = total
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
        let title: String
        let icon: String
        switch top {
        case .falling: title = String(localized: "Falling pressure pattern"); icon = "arrow.down.right.circle.fill"
        case .rising: title = String(localized: "Rising pressure pattern"); icon = "arrow.up.right.circle.fill"
        default: title = String(localized: "Steady pressure"); icon = "minus.circle.fill"
        }
        return Insight(
            id: "pressure-trend",
            category: .pressure,
            icon: icon,
            title: title,
            detail: includingCoverageNote(String(localized: "\(percent(topShare)) of your headaches were logged on days when barometric pressure \(narrativeLabel(for: top))."), subset: coverageSubset, of: events.count),
            strength: topShare,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: includingCoverageNote(String(localized: "\(percent(topShare)) of your headaches were logged on days when barometric pressure \(narrativeLabel(for: top)), \(formatMultiple(topShare / baseline)) the even baseline of \(percent(baseline))."), subset: coverageSubset, of: events.count),
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: baseline,
                axisCaption: String(localized: "Pressure trend at headache onset")
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
        let direction = med < 0 ? String(localized: "drop") : String(localized: "rise")
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
            title: String(localized: "Typical 6h pressure shift"),
            detail: String(localized: "Median pressure change in the 6 hours before your headaches: \(HeadacheTemperatureFormatting.localizedMeasurement(value: med, unit: UnitPressure.hectopascals, fractionDigits: 1)), a typical \(direction)."),
            strength: min(1.0, abs(med) / 6),
            whyItMatters: Self.insightDisclaimer,
            yourPattern: String(localized: "Median 6-hour pressure change before your headaches: \(HeadacheTemperatureFormatting.localizedMeasurement(value: med, unit: UnitPressure.hectopascals, fractionDigits: 1)). The histogram on the right shows the full distribution."),
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: String(localized: "6-hour pressure change (hPa) before each headache")
            )
        )
    }

    private static func airQualityInsight(_ events: [HeadacheEvent]) -> Insight? {
        let aqi = events.compactMap(\.usAQI)
        guard aqi.count >= minimumSampleSize else { return nil }
        let elevated = Double(aqi.filter { $0 >= 75 }.count) / Double(aqi.count)
        guard elevated >= 0.30 else { return nil }
        let coverageSubset = aqi.count
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
            title: String(localized: "Elevated air quality"),
            detail: includingCoverageNote(String(localized: "\(percent(elevated)) of your headaches happened with US AQI ≥ 75."), subset: coverageSubset, of: events.count),
            strength: elevated,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: includingCoverageNote(String(localized: "\(percent(elevated)) of your headaches occurred with US AQI at or above 75, the threshold where sensitive groups commonly start to feel effects."), subset: coverageSubset, of: events.count),
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: String(localized: "Air quality at headache onset (US AQI)")
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
            title: String(localized: "HRV around your headaches"),
            detail: String(localized: "Median HRV (SDNN) when you've logged a headache: \(HeadacheTemperatureFormatting.localizedMeasurement(value: med, unit: UnitDuration.milliseconds, fractionDigits: 0))."),
            strength: 0.30,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: String(localized: "Your median pre-headache HRV (SDNN) is \(HeadacheTemperatureFormatting.localizedMeasurement(value: med, unit: UnitDuration.milliseconds, fractionDigits: 0)). The chart shows where your HRV typically sat at the moment you logged."),
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: String(localized: "HRV (SDNN, ms) at headache onset")
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
            title: String(localized: "High humidity pattern"),
            detail: String(localized: "\(percent(high)) of your headaches happened with humidity at or above 70%."),
            strength: high * 0.7,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: String(localized: "\(percent(high)) of your headaches occurred with humidity ≥ 70%. The chart shows the full breakdown."),
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: String(localized: "Relative humidity at headache onset")
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
            title: String(localized: "Most often: \(label(for: top))"),
            detail: String(localized: "\(percent(topShare)) of headaches you've rated were rated \(narrativeLabel(for: top))."),
            strength: topShare - baseline,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: String(localized: "\(percent(topShare)) of your rated headaches were rated \(narrativeLabel(for: top)), \(formatMultiple(topShare / baseline)) the even baseline of \(percent(baseline))."),
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: baseline,
                axisCaption: String(localized: "Severity distribution across rated headaches")
            )
        )
    }

    // MARK: - Temperature

    private static func temperatureInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.apparentTemperatureC)
        guard values.count >= minimumSampleSize else { return nil }
        let useCelsius = HeadacheAppGroup.userDefaults.bool(forKey: HeadacheStorageKey.useCelsiusTemperature.rawValue)
        let bins: [(label: String, range: Range<Double>)] = temperatureBins(useCelsius: useCelsius)
        let total = values.count
        let coverageSubset = total
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
        let displayTop = HeadacheTemperatureFormatting.localizedStoredText(topLabel).replacingOccurrences(of: "\n", with: " ")
        let title = isExtreme ? String(localized: "\(displayTop) weather cluster") : String(localized: "Temperature cluster: \(displayTop)")
        return Insight(
            id: "temperature",
            category: .weather,
            icon: icon,
            title: title,
            detail: includingCoverageNote(String(localized: "\(percent(topShare)) of your headaches happened when it felt \(displayTop)."), subset: coverageSubset, of: events.count),
            strength: topShare,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: String(localized: "\(percent(topShare)) of your logged headaches happened in \(displayTop) conditions."),
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: baseline,
                axisCaption: String(localized: "Apparent temperature at headache onset")
            )
        )
    }

    /// Bucket boundaries match the Fahrenheit ranges users will recognize (freezing, sub-freezing, room temp, hot)
    /// while the underlying values stay in Celsius for the comparison.
    private static func temperatureBins(useCelsius: Bool) -> [(label: String, range: Range<Double>)] {
        if useCelsius {
            return [
                ("Very cold\n<0°C", -100..<0),
                ("Cold\n0–10°C", 0..<10),
                ("Cool\n10–18°C", 10..<18),
                ("Mild\n18–25°C", 18..<25),
                ("Warm\n25–32°C", 25..<32),
                ("Hot\n32°C+", 32..<100)
            ]
        }
        // Fahrenheit boundaries map to: 0, 10, 18, 25, 32 °C → 32, 50, 65, 77, 90 °F
        return [
            ("Very cold\n<32°F", -100..<0),
            ("Cold\n32–50°F", 0..<10),
            ("Cool\n50–65°F", 10..<18),
            ("Mild\n65–77°F", 18..<25),
            ("Warm\n77–90°F", 25..<32),
            ("Hot\n90°F+", 32..<100)
        ]
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
        let coverageSubset = total
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
            title: String(localized: "Rainy-day cluster"),
            detail: includingCoverageNote(String(localized: "\(percent(rainShare)) of your headaches happened during rain (\(percent(topBucket.share)) in the \(HeadacheTemperatureFormatting.localizedStoredText(topBucket.label)) band)."), subset: coverageSubset, of: events.count),
            strength: rainShare,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: includingCoverageNote(String(localized: "\(percent(rainShare)) of your headaches occurred during active precipitation, with the most common intensity being \(HeadacheTemperatureFormatting.localizedStoredText(topBucket.label))."), subset: coverageSubset, of: events.count),
            breakdown: Breakdown(
                buckets: peaked,
                evenBaseline: nil,
                axisCaption: String(localized: "Precipitation at headache onset")
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
        let coverageSubset = total
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
            title: String(localized: "Windy conditions"),
            detail: includingCoverageNote(String(localized: "\(percent(topShare)) of your headaches happened with \(HeadacheTemperatureFormatting.localizedStoredText(topLabel).replacingOccurrences(of: "\n", with: " ")) wind speeds."), subset: coverageSubset, of: events.count),
            strength: topShare,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: includingCoverageNote(String(localized: "\(percent(topShare)) of your headaches occurred during \(HeadacheTemperatureFormatting.localizedStoredText(topLabel).replacingOccurrences(of: "\n", with: " ")) conditions."), subset: coverageSubset, of: events.count),
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: String(localized: "Wind speed at headache onset (km/h)")
            )
        )
    }

    // MARK: - Caffeine

    private static func caffeineInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.caffeineMgToday)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let med = median(values)
        let coverageSubset = total
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
                title: String(localized: "Low-caffeine days"),
                detail: includingCoverageNote(String(localized: "\(percent(noneShare)) of your headaches happened on days with zero caffeine (\(percent(highShare)) high-caffeine days). Median: \(HeadacheTemperatureFormatting.localizedMeasurement(value: med, unit: UnitMass.milligrams, fractionDigits: 0))."), subset: coverageSubset, of: events.count),
                strength: noneShare,
                whyItMatters: Self.insightDisclaimer,
                yourPattern: String(localized: "\(percent(noneShare)) of your headaches occurred on zero-caffeine days, with only \(percent(highShare)) on high-caffeine days (≥200mg)."),
                breakdown: Breakdown(
                    buckets: buckets,
                    evenBaseline: nil,
                    axisCaption: String(localized: "Daily caffeine consumption before headaches")
                )
            )
        } else {
            return Insight(
                id: "caffeine-high",
                category: .heart,
                icon: "cup.and.saucer.fill",
                title: String(localized: "High-caffeine days"),
                detail: includingCoverageNote(String(localized: "\(percent(highShare)) of your headaches happened on days with 200mg+ caffeine (\(percent(veryHighShare)) above 400mg). Median: \(HeadacheTemperatureFormatting.localizedMeasurement(value: med, unit: UnitMass.milligrams, fractionDigits: 0))."), subset: coverageSubset, of: events.count),
                strength: highShare,
                whyItMatters: Self.insightDisclaimer,
                yourPattern: String(localized: "\(percent(highShare)) of your headaches occurred on high-caffeine days (≥200mg), including \(percent(veryHighShare)) on very high days (≥400mg)."),
                breakdown: Breakdown(
                    buckets: buckets,
                    evenBaseline: nil,
                    axisCaption: String(localized: "Daily caffeine consumption before headaches")
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
        let coverageSubset = total
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
            title: String(localized: "Low hydration pattern"),
            detail: includingCoverageNote(String(localized: "\(percent(lowShare)) of your headaches happened with under 1L of water that day (\(percent(Double(veryLow) / Double(total))) under 500mL). Median: \(HeadacheTemperatureFormatting.localizedMeasurement(value: med, unit: UnitVolume.milliliters, fractionDigits: 0))."), subset: coverageSubset, of: events.count),
            strength: lowShare,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: String(localized: "\(percent(lowShare)) of your headaches occurred on days with below 1,000 mL water intake, including \(percent(Double(veryLow) / Double(total))) under 500 mL. Your median intake on headache days was \(HeadacheTemperatureFormatting.localizedMeasurement(value: med, unit: UnitVolume.milliliters, fractionDigits: 0))."),
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: String(localized: "Daily water intake before headaches")
            )
        )
    }

    // MARK: - Exercise

    private static func exerciseInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.exerciseMinutesToday)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let coverageSubset = total
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
            title: String(localized: "Exertion-linked"),
            detail: includingCoverageNote(String(localized: "\(percent(moderateShare)) of your headaches followed 15+ minutes of exercise."), subset: coverageSubset, of: events.count),
            strength: moderateShare,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: String(localized: "\(percent(moderateShare)) of your headaches occurred on days with 15+ minutes of exercise."),
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: String(localized: "Exercise minutes on headache days")
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
        let coverageSubset = totalWithData
        let topType = typeElevated.max(by: { $0.value < $1.value })
        let topTypePhrase = topType.map {
            String(localized: "\(HeadacheTemperatureFormatting.localizedStoredText($0.key)) (\(percent(Double($0.value) / Double(elevatedCount))))")
        } ?? String(localized: "various pollen types")
        let hasMultiple = typeElevated.count >= 3
        let pollenType = HeadacheTemperatureFormatting.localizedStoredText(topType?.key ?? "pollen")
        let title = hasMultiple ? String(localized: "Multi-pollen elevation") : String(localized: "Elevated \(pollenType)")
        return Insight(
            id: "pollen",
            category: .weather,
            icon: "leaf.fill",
            title: title,
            detail: includingCoverageNote(String(localized: "\(percent(elevatedShare)) of your headaches occurred when at least one pollen type was elevated. Most common: \(topTypePhrase)."), subset: coverageSubset, of: events.count),
            strength: elevatedShare,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: String(localized: "\(percent(elevatedShare)) of your headaches with pollen data occurred on days with elevated pollen levels, most commonly \(topTypePhrase)."),
            breakdown: Breakdown(
                buckets: [
                    Bucket(label: "No elevation", share: 1.0 - elevatedShare, count: totalWithData - elevatedCount, isPeak: false),
                    Bucket(label: "Elevated", share: elevatedShare, count: elevatedCount, isPeak: true),
                ],
                evenBaseline: nil,
                axisCaption: String(localized: "Pollen elevation at headache onset")
            )
        )
    }

    // MARK: - Blood Pressure

    private static func bloodPressureInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.bloodPressureSystolicMmHg)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let med = median(values)
        let coverageSubset = total
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
            title: String(localized: "Elevated blood pressure"),
            detail: includingCoverageNote(String(localized: "\(percent(elevatedShare)) of your headaches showed systolic BP ≥130 (\(percent(highShare)) ≥140). Median: \(HeadacheTemperatureFormatting.localizedMeasurement(value: med, unit: UnitPressure.millimetersOfMercury, fractionDigits: 0))."), subset: coverageSubset, of: events.count),
            strength: elevatedShare,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: String(localized: "\(percent(elevatedShare)) of your headaches with BP data occurred with elevated systolic readings (≥130), including \(percent(highShare)) at hypertensive levels (≥140)."),
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: String(localized: "Systolic BP at headache onset (mmHg)")
            )
        )
    }

    // MARK: - Oxygen Saturation

    private static func oxygenSaturationInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.oxygenSaturationPercent)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let coverageSubset = total
        let low = values.filter { $0 < 95 }.count
        let lowShare = Double(low) / Double(total)
        guard lowShare >= 0.30 else { return nil }
        return Insight(
            id: "oxygen-saturation",
            category: .heart,
            icon: "lungs.fill",
            title: String(localized: "Lower oxygen saturation"),
            detail: includingCoverageNote(String(localized: "\(percent(lowShare)) of your headaches showed SpO₂ below 95%."), subset: coverageSubset, of: events.count),
            strength: lowShare * 0.8,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: String(localized: "\(percent(lowShare)) of your headaches with oxygen data occurred with SpO₂ below 95%."),
            breakdown: Breakdown(
                buckets: [
                    Bucket(label: "Normal\n95–100%", share: 1.0 - lowShare, count: total - low, isPeak: false),
                    Bucket(label: "Low\n<95%", share: lowShare, count: low, isPeak: true),
                ],
                evenBaseline: nil,
                axisCaption: String(localized: "Oxygen saturation at headache onset")
            )
        )
    }

    // MARK: - Time in Daylight

    private static func daylightInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.timeInDaylightMinutesToday)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let med = median(values)
        let coverageSubset = total
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
                title: String(localized: "Low daylight exposure"),
                detail: includingCoverageNote(String(localized: "\(percent(veryLowShare)) of your headaches happened on days with under 15 minutes of daylight exposure."), subset: coverageSubset, of: events.count),
                strength: veryLowShare,
                whyItMatters: Self.insightDisclaimer,
                yourPattern: String(localized: "\(percent(veryLowShare)) of your headaches occurred on days with under 15 minutes of daylight, median \(HeadacheTemperatureFormatting.localizedMeasurement(value: med, unit: UnitDuration.minutes, fractionDigits: 0))."),
                breakdown: Breakdown(
                    buckets: buckets,
                    evenBaseline: nil,
                    axisCaption: String(localized: "Daylight exposure on headache days")
                )
            )
        } else {
            return Insight(
                id: "daylight-high",
                category: .weather,
                icon: "sun.max.fill",
                title: String(localized: "High daylight exposure"),
                detail: includingCoverageNote(String(localized: "\(percent(highShare)) of your headaches happened on days with 2+ hours of daylight exposure."), subset: coverageSubset, of: events.count),
                strength: highShare,
                whyItMatters: Self.insightDisclaimer,
                yourPattern: String(localized: "\(percent(highShare)) of your headaches occurred on days with 2+ hours of daylight exposure."),
                breakdown: Breakdown(
                    buckets: buckets,
                    evenBaseline: nil,
                    axisCaption: String(localized: "Daylight exposure on headache days")
                )
            )
        }
    }

    // MARK: - Environmental Audio

    private static func audioExposureInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.environmentalAudioExposureDbA)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let coverageSubset = total
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
            title: String(localized: "Elevated noise environment"),
            detail: includingCoverageNote(String(localized: "\(percent(elevatedShare)) of your headaches happened in noisy environments (≥70 dBA)."), subset: coverageSubset, of: events.count),
            strength: elevatedShare * 0.7,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: String(localized: "\(percent(elevatedShare)) of your headaches with audio data occurred in environments at or above 70 decibels."),
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: String(localized: "Environmental audio level at headache onset")
            )
        )
    }

    // MARK: - Hours Since Waking

    private static func hoursSinceWakeInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.hoursSinceMainSleepWake)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let med = median(values)
        let coverageSubset = total
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
            detail: includingCoverageNote(String(localized: "\(percent(topShare)) of your headaches hit \(HeadacheTemperatureFormatting.localizedStoredText(topLabel)) after waking (median: \(formatHours(med)))."), subset: coverageSubset, of: events.count),
            strength: topShare,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: String(localized: "\(percent(topShare)) of your headaches occur \(HeadacheTemperatureFormatting.localizedStoredText(topLabel)) after waking, \(formatMultiple(multiple)) the even baseline. Median: \(formatHours(med))."),
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: baseline,
                axisCaption: String(localized: "Hours since waking at headache onset")
            )
        )
    }

    // MARK: - Menstrual Cycle

    private static func menstrualCycleInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.daysSinceLastPeriodStart)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let coverageSubset = total
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
            title: String(localized: "Luteal phase link"),
            detail: includingCoverageNote(String(localized: "\(percent(lutealShare)) of logged headaches landed in the luteal phase (days 14–28)."), subset: coverageSubset, of: events.count),
            strength: lutealShare - follicularShare,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: String(localized: "\(percent(lutealShare)) of your headaches with cycle data occurred in the luteal phase, compared to \(percent(follicularShare)) in the follicular phase."),
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: String(localized: "Cycle phase at headache onset")
            )
        )
    }

    // MARK: - Motion Activity

    private static func motionActivityInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.motionActivity)
        guard values.count >= minimumSampleSize else { return nil }
        let total = values.count
        let coverageSubset = total
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
            title: String(localized: "Active when headaches hit"),
            detail: includingCoverageNote(String(localized: "\(percent(topShare)) of your headaches were logged while \(narrativeLabel(for: top))."), subset: coverageSubset, of: events.count),
            strength: topShare,
            whyItMatters: Self.insightDisclaimer,
            yourPattern: String(localized: "\(percent(topShare)) of your headaches were logged while \(narrativeLabel(for: top))."),
            breakdown: Breakdown(
                buckets: buckets,
                evenBaseline: nil,
                axisCaption: String(localized: "Activity at headache onset")
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
            (Condition(id: "low-sleep", label: String(localized: "Less than 6h sleep")), { $0.sleepHoursLastNight ?? 8 < 6 }),
            (Condition(id: "falling-pressure", label: String(localized: "Falling pressure")), { $0.pressureTrend == .falling }),
            (Condition(id: "high-aqi", label: String(localized: "US AQI ≥ 75")), { ($0.usAQI ?? 0) >= 75 }),
            (Condition(id: "high-humidity", label: String(localized: "Humidity ≥ 70%")), { ($0.humidityPercent ?? 0) >= 70 }),
            (Condition(id: "high-caffeine", label: String(localized: "Caffeine ≥ 200 mg")), { ($0.caffeineMgToday ?? 0) >= 200 }),
            (Condition(id: "low-water", label: String(localized: "Water < 1 L")), { ($0.waterMlToday ?? 2000) < 1000 }),
            (Condition(id: "no-exercise", label: String(localized: "Zero exercise")), { ($0.exerciseMinutesToday ?? 1) == 0 }),
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
            title: String(localized: "Signal combination: \(cond1.label) & \(cond2.label)"),
            detail: String(localized: "\(percent(coShare)) of your headaches hit when both occurred together, \(formatMultiple(lift)) more often than if they were independent."),
            strength: min(1.0, coShare * (1.0 + lift / 3.0)),
            whyItMatters: Self.insightDisclaimer,
            yourPattern: String(localized: "\(percent(coShare)) of your headaches occurred when \(cond1.label) and \(cond2.label) coincided, \(formatMultiple(lift)) the rate expected by chance (\(percent(expectedShare)))."),
            breakdown: Breakdown(
                buckets: [
                    Bucket(label: "Neither", share: 1.0 - (Double(c1Count) + Double(c2Count) - Double(coCount)) / Double(total), count: total - c1Count - c2Count + coCount, isPeak: false),
                    Bucket(label: cond1.label.split(separator: " ").prefix(1).joined(), share: Double(c1Count - coCount) / Double(total), count: c1Count - coCount, isPeak: false),
                    Bucket(label: cond2.label.split(separator: " ").prefix(1).joined(), share: Double(c2Count - coCount) / Double(total), count: c2Count - coCount, isPeak: false),
                    Bucket(label: "Both", share: coShare, count: coCount, isPeak: true),
                ],
                evenBaseline: nil,
                axisCaption: String(localized: "Co-occurrence pattern")
            )
        )
    }

    // MARK: - Headache-free days (protective patterns)

    /// The flip side of trigger analysis: using the daily baseline (which records non-headache days
    /// too), find the condition under which the user most often stays headache-free. Requires the
    /// `DailyRecord` history, so it stays silent for event-only callers (and below sample size).
    private struct ProtectiveCandidate {
        let category: InsightCategory
        let icon: String
        let factorName: String
        let conditionLabel: String
        let conditionRate: Double
        let overallRate: Double
        let conditionDays: Int
        let conditionHeadacheDays: Int
        let buckets: [Bucket]
        let axisCaption: String

        var gap: Double { overallRate - conditionRate }
    }

    /// Minimum baseline days (with a usable signal) before a protective pattern is trustworthy.
    private static let protectiveMinimumTotalDays = 10
    /// A protective condition must carry headaches at most this fraction of the overall rate.
    private static let protectiveRateCeilingFactor = 0.6
    /// ...and the absolute drop in headache rate must clear this, so a tiny edge isn't dressed up.
    private static let protectiveMinimumGap = 0.15

    private static func headacheFreeDayInsight(_ dailyRecords: [DailyRecord]) -> Insight? {
        guard !dailyRecords.isEmpty else { return nil }
        let candidates = [
            protectiveSleepCandidate(dailyRecords),
            protectivePressureCandidate(dailyRecords),
            protectiveAirQualityCandidate(dailyRecords),
        ].compactMap { $0 }
        guard let best = candidates.max(by: { $0.gap < $1.gap }) else { return nil }

        let freePct = percent(1 - best.conditionRate)
        let conditionHeadachePct = percent(best.conditionRate)
        let overallHeadachePct = percent(best.overallRate)
        return Insight(
            id: "headache-free-days",
            category: best.category,
            icon: best.icon,
            title: String(localized: "Your headache-free days"),
            detail: String(localized: "You stay headache-free on \(freePct) of days with \(best.conditionLabel), the best of any condition tracked. Overall you log a headache on \(overallHeadachePct) of days."),
            strength: min(0.85, 0.4 + best.gap),
            whyItMatters: Self.insightDisclaimer,
            yourPattern: String(localized: "Across \(best.conditionDays) days with \(best.conditionLabel), headaches were logged on \(conditionHeadachePct) of days, below the overall rate of \(overallHeadachePct)."),
            breakdown: Breakdown(
                buckets: best.buckets,
                evenBaseline: nil,
                axisCaption: best.axisCaption
            )
        )
    }

    private static func protectiveSleepCandidate(_ records: [DailyRecord]) -> ProtectiveCandidate? {
        let counts = DailyRecordStore.sleepConditionCounts(from: records).filter { $0.totalDays > 0 }
        let totalDays = counts.reduce(0) { $0 + $1.totalDays }
        let headacheDays = counts.reduce(0) { $0 + $1.headacheDays }
        guard totalDays >= protectiveMinimumTotalDays,
              headacheDays >= 3,
              totalDays - headacheDays >= 3 else { return nil }
        let overall = Double(headacheDays) / Double(totalDays)
        guard let best = counts.filter({ $0.totalDays >= 4 }).min(by: { $0.headacheRate < $1.headacheRate }) else { return nil }
        guard best.headacheRate <= overall * protectiveRateCeilingFactor,
              overall - best.headacheRate >= protectiveMinimumGap else { return nil }
        let buckets = counts.map { bucket in
            Bucket(
                label: bucket.label,
                share: max(0, 1 - bucket.headacheRate),
                count: bucket.totalDays - bucket.headacheDays,
                isPeak: bucket.label == best.label
            )
        }
        return ProtectiveCandidate(
            category: .sleep,
            icon: "bed.double.fill",
            factorName: "sleep",
            conditionLabel: String(localized: "\(HeadacheTemperatureFormatting.localizedStoredText(best.label)) of sleep"),
            conditionRate: best.headacheRate,
            overallRate: overall,
            conditionDays: best.totalDays,
            conditionHeadacheDays: best.headacheDays,
            buckets: buckets,
            axisCaption: String(localized: "Share of days that stayed headache-free, by sleep duration")
        )
    }

    private static func protectivePressureCandidate(_ records: [DailyRecord]) -> ProtectiveCandidate? {
        let known = records.filter { $0.weatherFetched && $0.pressureTrend != .unavailable }
        guard known.count >= protectiveMinimumTotalDays else { return nil }
        let headacheDays = known.filter(\.hadHeadache).count
        guard headacheDays >= 3, known.count - headacheDays >= 3 else { return nil }
        let overall = Double(headacheDays) / Double(known.count)
        let order: [(label: String, trend: PressureTrend)] = [
            ("Falling", .falling), ("Steady", .steady), ("Rising", .rising)
        ]
        let bins = order.map { entry -> (label: String, total: Int, headache: Int) in
            let inBin = known.filter { $0.pressureTrend == entry.trend }
            return (entry.label, inBin.count, inBin.filter(\.hadHeadache).count)
        }
        let rate: (Int, Int) -> Double = { headache, total in total > 0 ? Double(headache) / Double(total) : 1 }
        guard let best = bins.filter({ $0.total >= 4 }).min(by: { rate($0.headache, $0.total) < rate($1.headache, $1.total) }) else { return nil }
        let bestRate = rate(best.headache, best.total)
        guard bestRate <= overall * protectiveRateCeilingFactor,
              overall - bestRate >= protectiveMinimumGap else { return nil }
        let buckets = bins.map { bin in
            Bucket(
                label: bin.label,
                share: bin.total > 0 ? max(0, 1 - Double(bin.headache) / Double(bin.total)) : 0,
                count: bin.total - bin.headache,
                isPeak: bin.label == best.label
            )
        }
        return ProtectiveCandidate(
            category: .pressure,
            icon: "barometer",
            factorName: "barometric pressure",
            conditionLabel: String(localized: "\(HeadacheTemperatureFormatting.localizedStoredText(best.label)) pressure"),
            conditionRate: bestRate,
            overallRate: overall,
            conditionDays: best.total,
            conditionHeadacheDays: best.headache,
            buckets: buckets,
            axisCaption: String(localized: "Share of days that stayed headache-free, by pressure trend")
        )
    }

    private static func protectiveAirQualityCandidate(_ records: [DailyRecord]) -> ProtectiveCandidate? {
        let withAQI = records.filter { $0.weatherFetched && $0.usAQI != nil }
        guard withAQI.count >= protectiveMinimumTotalDays else { return nil }
        let headacheDays = withAQI.filter(\.hadHeadache).count
        guard headacheDays >= 3, withAQI.count - headacheDays >= 3 else { return nil }
        let overall = Double(headacheDays) / Double(withAQI.count)
        let good = withAQI.filter { !$0.isElevatedAQI }
        let elevated = withAQI.filter { $0.isElevatedAQI }
        guard good.count >= 4 else { return nil }
        let goodHeadache = good.filter(\.hadHeadache).count
        let goodRate = Double(goodHeadache) / Double(good.count)
        guard goodRate <= overall * protectiveRateCeilingFactor,
              overall - goodRate >= protectiveMinimumGap else { return nil }
        let elevatedHeadache = elevated.filter(\.hadHeadache).count
        let buckets = [
            Bucket(label: "Clean\n<75", share: max(0, 1 - goodRate), count: good.count - goodHeadache, isPeak: true),
            Bucket(
                label: "Elevated\n75+",
                share: elevated.isEmpty ? 0 : max(0, 1 - Double(elevatedHeadache) / Double(elevated.count)),
                count: elevated.count - elevatedHeadache,
                isPeak: false
            ),
        ]
        return ProtectiveCandidate(
            category: .airQuality,
            icon: "aqi.low",
            factorName: "air quality",
            conditionLabel: String(localized: "Clean air (US AQI under 75)"),
            conditionRate: goodRate,
            overallRate: overall,
            conditionDays: good.count,
            conditionHeadacheDays: goodHeadache,
            buckets: buckets,
            axisCaption: String(localized: "Share of days that stayed headache-free, by air quality")
        )
    }

    // MARK: - Helpers

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private static func formatNumber(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    private static func formatMultiple(_ value: Double) -> String {
        "\(formatNumber(value, fractionDigits: 1))×"
    }

    private static func formatWholePercent(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: Double(value) / 100)) ?? "\(value)%"
    }

    private static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private static func includingCoverageNote(_ sentence: String, subset: Int, of total: Int) -> String {
        guard subset < total else { return sentence }
        let note = String(localized: "Some logged entries do not include this data.")
        return "\(sentence) \(note)"
    }

    private static func formatHours(_ hours: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(0, hours) * 3_600) ?? String(localized: "0 hours")
    }

    private static func label(for part: PartOfDay) -> String {
        switch part {
        case .overnight: return String(localized: "Overnight")
        case .morning: return String(localized: "Morning")
        case .afternoon: return String(localized: "Afternoon")
        case .evening: return String(localized: "Evening")
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
        case .slight: return String(localized: "Mild")
        case .medium: return String(localized: "Moderate")
        case .extreme: return String(localized: "Severe")
        }
    }

    private static func label(for trend: PressureTrend) -> String {
        switch trend {
        case .falling: return String(localized: "Falling")
        case .rising: return String(localized: "Rising")
        case .steady: return String(localized: "Steady")
        case .unavailable: return String(localized: "Unknown")
        }
    }

    private static func label(for activity: MotionActivity) -> String {
        switch activity {
        case .stationary: return String(localized: "Stationary")
        case .walking: return String(localized: "Walking")
        case .running: return String(localized: "Running")
        case .automotive: return String(localized: "In a vehicle")
        case .cycling: return String(localized: "Cycling")
        case .unknown: return String(localized: "Unknown")
        }
    }

    private static func narrativeLabel(for part: PartOfDay) -> String {
        switch part {
        case .overnight: return String(localized: "at night")
        case .morning: return String(localized: "in the morning")
        case .afternoon: return String(localized: "in the afternoon")
        case .evening: return String(localized: "in the evening")
        }
    }

    private static func narrativeLabel(for severity: HeadacheSeverity) -> String {
        switch severity {
        case .slight: return String(localized: "mild")
        case .medium: return String(localized: "moderate")
        case .extreme: return String(localized: "severe")
        }
    }

    private static func narrativeLabel(for trend: PressureTrend) -> String {
        switch trend {
        case .falling: return String(localized: "falling")
        case .rising: return String(localized: "rising")
        case .steady: return String(localized: "steady")
        case .unavailable: return String(localized: "unknown")
        }
    }

    private static func narrativeLabel(for activity: MotionActivity) -> String {
        switch activity {
        case .stationary: return String(localized: "stationary")
        case .walking: return String(localized: "walking")
        case .running: return String(localized: "running")
        case .automotive: return String(localized: "in a vehicle")
        case .cycling: return String(localized: "cycling")
        case .unknown: return String(localized: "unknown")
        }
    }
}

// MARK: - Calendar heatmap

/// One row per calendar day in a fixed lookback window. Used by the in-app heatmap and by
/// the doctor-facing PDF so both renderings see the same severity colouring.
struct HeatmapDay: Identifiable, Sendable {
    let date: Date
    let count: Int
    let peakSeverity: HeadacheSeverity?

    var id: Date { date }
}

enum HeatmapData {
    static func build(from events: [HeadacheEvent], days: Int = 90, endingAt end: Date = .now, calendar: Calendar = .current) -> [HeatmapDay] {
        let today = calendar.startOfDay(for: end)
        guard let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        // Don't render days before the first logged headache; that would imply data we don't have.
        guard let firstEvent = events.map({ $0.timestamp }).min() else { return [] }
        let firstDay = calendar.startOfDay(for: firstEvent)
        let start = max(windowStart, min(firstDay, today))
        var byDay: [Date: (count: Int, peak: HeadacheSeverity?)] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.timestamp)
            guard day >= start, day <= today else { continue }
            var entry = byDay[day] ?? (count: 0, peak: nil)
            entry.count += 1
            if let severity = event.severity {
                entry.peak = HeadacheSeverity.peak(entry.peak, severity)
            }
            byDay[day] = entry
        }
        var out: [HeatmapDay] = []
        var cursor = start
        while cursor <= today {
            let entry = byDay[cursor]
            out.append(HeatmapDay(date: cursor, count: entry?.count ?? 0, peakSeverity: entry?.peak))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86_400)
        }
        return out
    }
}

extension HeadacheSeverity {
    var rank: Int {
        switch self {
        case .slight: 1
        case .medium: 2
        case .extreme: 3
        }
    }

    static func peak(_ a: HeadacheSeverity?, _ b: HeadacheSeverity) -> HeadacheSeverity {
        guard let a else { return b }
        return a.rank >= b.rank ? a : b
    }
}
