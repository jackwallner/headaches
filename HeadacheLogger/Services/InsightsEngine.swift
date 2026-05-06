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

    struct Insight: Sendable, Identifiable {
        let id: String
        let category: InsightCategory
        let icon: String
        let title: String
        let detail: String
        /// 0...1 strength used to rank insights — higher means a more concentrated pattern.
        let strength: Double
    }

    struct Summary: Sendable {
        let totalEvents: Int
        let dateRange: ClosedRange<Date>?
        let insights: [Insight]
    }

    static func summarize(_ events: [HeadacheEvent], calendar: Calendar = .current) -> Summary {
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
        if let item = sleepInsight(events) { insights.append(item) }
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
        var counts: [PartOfDay: Int] = [:]
        for event in events {
            counts[event.partOfDay, default: 0] += 1
        }
        guard let (top, count) = counts.max(by: { $0.value < $1.value }), count > 0 else { return nil }
        let share = Double(count) / Double(events.count)
        guard share >= 0.30 else { return nil }
        return Insight(
            id: "part-of-day",
            category: .time,
            icon: icon(for: top),
            title: "Most common time: \(label(for: top))",
            detail: "\(percent(share)) of your logged headaches happened in the \(label(for: top).lowercased()).",
            strength: share
        )
    }

    private static func weekdayInsight(_ events: [HeadacheEvent], calendar: Calendar) -> Insight? {
        var counts: [Int: Int] = [:]
        for event in events {
            counts[event.weekdayIndex, default: 0] += 1
        }
        guard let (topIndex, count) = counts.max(by: { $0.value < $1.value }), count > 0 else { return nil }
        let share = Double(count) / Double(events.count)
        // Uniform across 7 days would be ~14%. Surface only when meaningfully concentrated.
        guard share >= 0.20 else { return nil }
        let symbols = calendar.standaloneWeekdaySymbols
        let dayName: String = {
            let i = topIndex - 1
            return (i >= 0 && i < symbols.count) ? symbols[i] : "a weekday"
        }()
        return Insight(
            id: "weekday",
            category: .time,
            icon: "calendar",
            title: "Headache day: \(dayName)",
            detail: "\(percent(share)) of your headaches fall on \(dayName).",
            strength: share - 0.14
        )
    }

    private static func sleepInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.sleepHoursLastNight)
        guard values.count >= minimumSampleSize else { return nil }
        let median = median(values)
        let lowSleepShare = Double(values.filter { $0 < 6 }.count) / Double(values.count)
        let detail: String
        let strength: Double
        if lowSleepShare >= 0.4 {
            detail = "\(percent(lowSleepShare)) of your headaches followed a night with under 6 hours of sleep. Median sleep the night before: \(formatHours(median))."
            strength = 0.5 + lowSleepShare * 0.4
        } else {
            detail = "Median sleep the night before a headache: \(formatHours(median))."
            strength = 0.35
        }
        return Insight(
            id: "sleep",
            category: .sleep,
            icon: "bed.double.fill",
            title: "Sleep before a headache",
            detail: detail,
            strength: strength
        )
    }

    private static func pressureTrendInsight(_ events: [HeadacheEvent]) -> Insight? {
        let trends = events.map(\.pressureTrend).filter { $0 != .unavailable }
        guard trends.count >= minimumSampleSize else { return nil }
        let falling = trends.filter { $0 == .falling }.count
        let rising = trends.filter { $0 == .rising }.count
        let steady = trends.filter { $0 == .steady }.count
        let total = trends.count
        let fallingShare = Double(falling) / Double(total)
        let risingShare = Double(rising) / Double(total)
        let topShare = max(fallingShare, risingShare, Double(steady) / Double(total))
        guard topShare >= 0.45 else { return nil }
        if fallingShare == topShare {
            return Insight(
                id: "pressure-trend",
                category: .pressure,
                icon: "arrow.down.right.circle.fill",
                title: "Falling pressure pattern",
                detail: "\(percent(fallingShare)) of your headaches happened during falling barometric pressure.",
                strength: fallingShare
            )
        }
        if risingShare == topShare {
            return Insight(
                id: "pressure-trend",
                category: .pressure,
                icon: "arrow.up.right.circle.fill",
                title: "Rising pressure pattern",
                detail: "\(percent(risingShare)) of your headaches happened during rising barometric pressure.",
                strength: risingShare
            )
        }
        return Insight(
            id: "pressure-trend",
            category: .pressure,
            icon: "minus.circle.fill",
            title: "Steady pressure",
            detail: "\(percent(topShare)) of your headaches happened with stable barometric pressure.",
            strength: topShare
        )
    }

    private static func pressureDeltaInsight(_ events: [HeadacheEvent]) -> Insight? {
        let deltas = events.compactMap(\.barometricPressureDeltaHpa6h)
        guard deltas.count >= minimumSampleSize else { return nil }
        let med = median(deltas)
        guard abs(med) >= 1.5 else { return nil }
        let direction = med < 0 ? "drop" : "rise"
        return Insight(
            id: "pressure-delta",
            category: .pressure,
            icon: "barometer",
            title: "Typical 6h pressure shift",
            detail: "Median pressure change in the 6 hours before your headaches: \(String(format: "%+.1f hPa", med)) — a typical \(direction).",
            strength: min(1.0, abs(med) / 6)
        )
    }

    private static func airQualityInsight(_ events: [HeadacheEvent]) -> Insight? {
        let aqi = events.compactMap(\.usAQI)
        guard aqi.count >= minimumSampleSize else { return nil }
        let elevated = Double(aqi.filter { $0 >= 75 }.count) / Double(aqi.count)
        guard elevated >= 0.30 else { return nil }
        return Insight(
            id: "aqi",
            category: .airQuality,
            icon: "aqi.medium",
            title: "Elevated air quality",
            detail: "\(percent(elevated)) of your headaches happened with US AQI ≥ 75.",
            strength: elevated
        )
    }

    private static func hrvInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.hrvSDNNMs)
        guard values.count >= minimumSampleSize else { return nil }
        let med = median(values)
        return Insight(
            id: "hrv",
            category: .heart,
            icon: "waveform.path.ecg",
            title: "HRV around your headaches",
            detail: "Median HRV (SDNN) when you've logged a headache: \(String(format: "%.0f ms", med)).",
            strength: 0.30
        )
    }

    private static func humidityInsight(_ events: [HeadacheEvent]) -> Insight? {
        let values = events.compactMap(\.humidityPercent)
        guard values.count >= minimumSampleSize else { return nil }
        let high = Double(values.filter { $0 >= 70 }.count) / Double(values.count)
        guard high >= 0.40 else { return nil }
        return Insight(
            id: "humidity",
            category: .weather,
            icon: "humidity.fill",
            title: "High humidity pattern",
            detail: "\(percent(high)) of your headaches happened with humidity at or above 70%.",
            strength: high * 0.7
        )
    }

    private static func severityInsight(_ events: [HeadacheEvent]) -> Insight? {
        var counts: [HeadacheSeverity: Int] = [:]
        var total = 0
        for event in events {
            if let severity = event.severity {
                counts[severity, default: 0] += 1
                total += 1
            }
        }
        guard total >= minimumSampleSize else { return nil }
        guard let (top, count) = counts.max(by: { $0.value < $1.value }) else { return nil }
        let share = Double(count) / Double(total)
        guard share >= 0.40 else { return nil }
        return Insight(
            id: "severity",
            category: .severity,
            icon: "exclamationmark.triangle.fill",
            title: "Most often: \(label(for: top))",
            detail: "\(percent(share)) of headaches you've rated were \(label(for: top).lowercased()).",
            strength: share - 0.33
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

    private static func formatHours(_ hours: Double) -> String {
        let total = max(0, hours)
        let h = Int(total)
        let m = Int((total - Double(h)) * 60)
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
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
}
