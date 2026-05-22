import Foundation
import SwiftData
import UserNotifications

/// Pulls a 24-hour forecast from Open-Meteo (and the air-quality endpoint) and decides whether
/// the user should get a heads-up notification. All work is value-typed so it can run from a
/// background task without touching the main actor.
enum ProactiveAlertsEngine {
    enum AlertKind: String, Sendable {
        case pressureDrop
        case airQuality
    }

    struct AlertDecision: Sendable {
        let kind: AlertKind
        let title: String
        let body: String
    }

    /// Minimum gap between two notifications so the user doesn't get spammed.
    static let minNotificationGap: TimeInterval = 6 * 60 * 60

    struct PersonalSignalProfile: Codable, Sendable {
        let totalDays: Int
        let conditionDays: Int
        let headacheConditionDays: Int
        let pHeadacheGivenCondition: Double
        let pHeadacheGivenNoCondition: Double
        let relativeRisk: Double
        let lift: Double
        let isSupported: Bool

        static let empty = PersonalSignalProfile(
            totalDays: 0,
            conditionDays: 0,
            headacheConditionDays: 0,
            pHeadacheGivenCondition: 0,
            pHeadacheGivenNoCondition: 0,
            relativeRisk: 0,
            lift: 0,
            isSupported: false
        )
    }

    struct PersonalAlertProfile: Codable, Sendable {
        let updatedAt: Date
        let pressure: PersonalSignalProfile
        let airQuality: PersonalSignalProfile

        static let empty = PersonalAlertProfile(
            updatedAt: .distantPast,
            pressure: .empty,
            airQuality: .empty
        )

        static func current() -> PersonalAlertProfile {
            let defaults = HeadacheAppGroup.userDefaults
            guard let data = defaults.data(forKey: HeadacheStorageKey.proAlertPersonalProfile.rawValue),
                  let decoded = try? JSONDecoder().decode(PersonalAlertProfile.self, from: data) else {
                return .empty
            }
            return decoded
        }

        func save() {
            let data = try? JSONEncoder().encode(self)
            HeadacheAppGroup.userDefaults.set(data, forKey: HeadacheStorageKey.proAlertPersonalProfile.rawValue)
        }
    }

    static func runIfEligible() async -> Bool {
        await StoreService.shared.updateCustomerProductStatus(fetchPolicy: .fetchCurrent)
        guard await StoreService.shared.isProUnlocked else { return false }

        let prefs = ProAlertPreferenceValues.current()
        guard prefs.alertsEnabled else { return false }
        guard let coord = CachedLocation.current() else { return false }

        // Respect quiet hours at fire time, not at decision time.
        let now = Date()
        if prefs.isQuietHour(at: now) { return false }

        // Throttle: don't fire more than once per minNotificationGap.
        let defaults = HeadacheAppGroup.userDefaults
        let lastFired = defaults.object(forKey: HeadacheStorageKey.proAlertLastFiredAt.rawValue) as? Date
        if let lastFired, now.timeIntervalSince(lastFired) < minNotificationGap {
            return false
        }

        guard let forecast = await ForecastClient.fetch24Hour(latitude: coord.latitude, longitude: coord.longitude) else {
            return false
        }

        guard let decision = evaluate(forecast: forecast, prefs: prefs, profile: PersonalAlertProfile.current()) else {
            return false
        }

        let granted = await ensureNotificationAuthorization()
        guard granted else { return false }

        await deliver(decision: decision)
        defaults.set(now, forKey: HeadacheStorageKey.proAlertLastFiredAt.rawValue)
        defaults.set(decision.kind.rawValue, forKey: HeadacheStorageKey.proAlertLastFiredKind.rawValue)
        return true
    }

    /// Pure function used by both runtime and tests.
    static func evaluate(forecast: HourlyForecast, prefs: ProAlertPreferenceValues) -> AlertDecision? {
        evaluate(forecast: forecast, prefs: prefs, profile: PersonalAlertProfile.current())
    }

    static func evaluate(forecast: HourlyForecast, prefs: ProAlertPreferenceValues, profile: PersonalAlertProfile) -> AlertDecision? {
        if profile.pressure.isSupported,
           let pressure = pressureDecision(forecast: forecast, threshold: prefs.pressureDropThresholdHpa, signal: profile.pressure) {
            return pressure
        }
        if prefs.airQualityEnabled,
           profile.airQuality.isSupported,
           let aq = airQualityDecision(forecast: forecast, threshold: prefs.airQualityThreshold, signal: profile.airQuality) {
            return aq
        }
        return nil
    }

    private static func pressureDecision(forecast: HourlyForecast, threshold: Double, signal: PersonalSignalProfile) -> AlertDecision? {
        let pressures = forecast.pressureMsl
        guard pressures.count >= 4 else { return nil }
        var maxDrop: Double = 0
        var dropEndIndex: Int = 0
        for i in 0..<(pressures.count - 1) {
            guard let peak = pressures[i] else { continue }
            for j in (i + 1)..<pressures.count {
                guard let trough = pressures[j] else { continue }
                let delta = peak - trough
                if delta > maxDrop {
                    maxDrop = delta
                    dropEndIndex = j
                }
            }
        }
        guard maxDrop >= threshold else { return nil }
        let hours = max(1, dropEndIndex)
        let body = "Forecast: \(formatHpa(maxDrop)) drop over the next \(hours)h. You've recorded headaches on \(signal.headacheConditionDays) of \(signal.conditionDays) similar days in your history."
        return AlertDecision(kind: .pressureDrop, title: "Personal pressure trigger ahead", body: body)
    }

    private static func airQualityDecision(forecast: HourlyForecast, threshold: Int, signal: PersonalSignalProfile) -> AlertDecision? {
        guard let peak = forecast.usAqi.compactMap({ $0 }).max() else { return nil }
        guard Int(peak) >= threshold else { return nil }
        let body = "AQI is forecast to reach \(Int(peak)) today. You've recorded headaches on \(signal.headacheConditionDays) of \(signal.conditionDays) similar days in your history."
        return AlertDecision(kind: .airQuality, title: "Personal air-quality trigger ahead", body: body)
    }

    private static func formatHpa(_ value: Double) -> String {
        String(format: "%.1f hPa", value)
    }

    private static func ensureNotificationAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    private static func deliver(decision: AlertDecision) async {
        let content = UNMutableNotificationContent()
        content.title = decision.title
        content.body = decision.body
        content.sound = .default
        content.threadIdentifier = "pro-alerts"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// 24-hour forward window of forecast data used by the engine.
struct HourlyForecast: Sendable {
    let times: [Date]
    let pressureMsl: [Double?]
    let usAqi: [Double?]
}

struct CachedLocation: Sendable {
    let latitude: Double
    let longitude: Double
    let capturedAt: Date

    static func current() -> CachedLocation? {
        let defaults = HeadacheAppGroup.userDefaults
        guard
            let lat = defaults.object(forKey: HeadacheStorageKey.lastKnownLatitude.rawValue) as? Double,
            let lon = defaults.object(forKey: HeadacheStorageKey.lastKnownLongitude.rawValue) as? Double,
            let at = defaults.object(forKey: HeadacheStorageKey.lastKnownLocationCapturedAt.rawValue) as? Date
        else {
            return nil
        }
        return CachedLocation(latitude: lat, longitude: lon, capturedAt: at)
    }

    static func save(latitude: Double, longitude: Double, capturedAt: Date = Date()) {
        let defaults = HeadacheAppGroup.userDefaults
        defaults.set(latitude, forKey: HeadacheStorageKey.lastKnownLatitude.rawValue)
        defaults.set(longitude, forKey: HeadacheStorageKey.lastKnownLongitude.rawValue)
        defaults.set(capturedAt, forKey: HeadacheStorageKey.lastKnownLocationCapturedAt.rawValue)
    }
}

/// Network shim used by the engine — separate from `EnvironmentService` so it works without
/// `@MainActor` and so the JSON parsing can be unit-tested in isolation.
enum ForecastClient {
    static let timeout: TimeInterval = 10

    static func fetch24Hour(latitude: Double, longitude: Double) async -> HourlyForecast? {
        async let weather = fetchWeatherWindow(latitude: latitude, longitude: longitude)
        async let air = fetchAirQualityWindow(latitude: latitude, longitude: longitude)

        guard let weather = await weather else { return nil }
        let aq = await air

        let aqiAligned: [Double?] = {
            guard let aq else { return Array(repeating: nil, count: weather.times.count) }
            // Align by timestamp; AQI feed and forecast feed both use the same `auto` timezone so
            // the strings should match — but cross-reference defensively in case Open-Meteo skips an hour.
            var index: [String: Double?] = [:]
            for (i, t) in aq.times.enumerated() {
                index[t] = aq.values[i]
            }
            return weather.timeStrings.map { index[$0] ?? nil }
        }()

        return HourlyForecast(times: weather.times, pressureMsl: weather.pressureMsl, usAqi: aqiAligned)
    }

    private struct WeatherWindow {
        let times: [Date]
        let timeStrings: [String]
        let pressureMsl: [Double?]
    }

    private struct WeatherResponse: Decodable {
        let timezone: String
        let hourly: Hourly
        struct Hourly: Decodable {
            let time: [String]
            let pressureMsl: [Double?]
            enum CodingKeys: String, CodingKey {
                case time
                case pressureMsl = "pressure_msl"
            }
        }
    }

    private static func fetchWeatherWindow(latitude: Double, longitude: Double) async -> WeatherWindow? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "hourly", value: "pressure_msl"),
            URLQueryItem(name: "forecast_days", value: "2"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(WeatherResponse.self, from: data),
              let tz = TimeZone(identifier: decoded.timezone)
        else {
            return nil
        }

        let now = Date()
        let horizon = now.addingTimeInterval(24 * 60 * 60)
        var times: [Date] = []
        var timeStrings: [String] = []
        var pressures: [Double?] = []
        for (i, raw) in decoded.hourly.time.enumerated() {
            guard let parsed = OpenMeteoTimeParsing.hourDate(from: raw, timeZone: tz) else { continue }
            if parsed < now.addingTimeInterval(-30 * 60) { continue }
            if parsed > horizon { break }
            times.append(parsed)
            timeStrings.append(raw)
            pressures.append(i < decoded.hourly.pressureMsl.count ? decoded.hourly.pressureMsl[i] : nil)
        }
        return WeatherWindow(times: times, timeStrings: timeStrings, pressureMsl: pressures)
    }

    private struct AirWindow {
        let times: [String]
        let values: [Double?]
    }

    private struct AirResponse: Decodable {
        let timezone: String
        let hourly: Hourly
        struct Hourly: Decodable {
            let time: [String]
            let usAqi: [Double?]
            enum CodingKeys: String, CodingKey {
                case time
                case usAqi = "us_aqi"
            }
        }
    }

    private static func fetchAirQualityWindow(latitude: Double, longitude: Double) async -> AirWindow? {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "hourly", value: "us_aqi"),
            URLQueryItem(name: "forecast_days", value: "2"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(AirResponse.self, from: data)
        else {
            return nil
        }
        return AirWindow(times: decoded.hourly.time, values: decoded.hourly.usAqi)
    }
}

// MARK: - Pattern-based predictive alerts

extension ProactiveAlertsEngine {

    static let personalSignalMinimumSampleSize: Int = 5
    static let personalSignalMinimumConditionDays: Int = 5
    static let personalSignalMinimumRelativeRisk: Double = 1.5
    static let personalSignalMinimumHeadacheConditionDays: Int = 3

    @MainActor
    static func refreshPersonalAlertProfile(in context: ModelContext) {
        makePersonalAlertProfile(in: context).save()
    }

    static func makePersonalAlertProfile(in context: ModelContext) -> PersonalAlertProfile {
        let records = DailyRecordStore.load()
        guard !records.isEmpty else { return .empty }
        let now = Date()
        return PersonalAlertProfile(
            updatedAt: now,
            pressure: pressureSignalProfile(from: records),
            airQuality: airQualitySignalProfile(from: records)
        )
    }

    /// Used by tests with a provided event list (backward compatibility).
    static func makePersonalAlertProfile(events: [HeadacheEvent], now: Date = Date()) -> PersonalAlertProfile {
        let records = DailyRecordStore.rebuild(from: events)
        let filled = DailyRecordStore.fillGapDays(
            records,
            from: records.first?.date ?? now,
            to: records.last?.date ?? now
        )
        return PersonalAlertProfile(
            updatedAt: now,
            pressure: pressureSignalProfile(from: filled),
            airQuality: airQualitySignalProfile(from: filled)
        )
    }

    static func pressureSignalProfile(from records: [DailyRecord]) -> PersonalSignalProfile {
        let counts = DailyRecordStore.pressureConditionCounts(from: records)
        return signalProfile(from: counts, totalMin: personalSignalMinimumSampleSize)
    }

    private static func airQualitySignalProfile(from records: [DailyRecord]) -> PersonalSignalProfile {
        let counts = DailyRecordStore.aqiConditionCounts(from: records)
        return signalProfile(from: counts, totalMin: personalSignalMinimumSampleSize)
    }

    private static func signalProfile(from counts: DailyRecordStore.ConditionCounts, totalMin: Int) -> PersonalSignalProfile {
        guard counts.totalDays >= totalMin else { return .empty }
        let supported = counts.totalDays >= totalMin
            && counts.conditionDays >= personalSignalMinimumConditionDays
            && counts.headacheConditionDays >= personalSignalMinimumHeadacheConditionDays
            && counts.relativeRisk >= personalSignalMinimumRelativeRisk
        return PersonalSignalProfile(
            totalDays: counts.totalDays,
            conditionDays: counts.conditionDays,
            headacheConditionDays: counts.headacheConditionDays,
            pHeadacheGivenCondition: counts.pHeadacheGivenCondition,
            pHeadacheGivenNoCondition: counts.pHeadacheGivenNoCondition,
            relativeRisk: counts.relativeRisk,
            lift: counts.lift,
            isSupported: supported
        )
    }

    struct PatternCluster: Sendable {
        let weekdayIndex: Int
        let weekdayName: String
        let startHour: Int
        let endHour: Int
        let headacheCount: Int
        let totalHeadaches: Int
        var share: Double { totalHeadaches > 0 ? Double(headacheCount) / Double(totalHeadaches) : 0 }
    }

    /// Minimum events needed before pattern-prediction alerts are meaningful.
    static let patternMinimumEvents: Int = 7

    /// Analyzes headache history for recurring time patterns (weekday × hour) and returns clusters
    /// that meet the sensitivity threshold. All computation is local — no data leaves the device.
    static func analyzeTimePatterns(events: [HeadacheEvent], sensitivity: Double) -> [PatternCluster] {
        guard events.count >= patternMinimumEvents else { return [] }

        // Threshold curve: sensitivity 0 (high-chance only) → 0.30 share + 5 count
        //                 sensitivity 1 (any chance)    → 0.15 share + 3 count
        let minShare = 0.30 - (0.15 * sensitivity)
        let minCount = max(3, Int(Double(5) - (2.0 * sensitivity)))

        let total = events.count
        let calendar = Calendar.current
        let symbols = calendar.standaloneWeekdaySymbols

        var buckets: [Int: [Int: Int]] = [:] // [weekdayIndex: [hour: count]]
        for event in events {
            let wd = event.weekdayIndex
            let hour = event.hourOfDay
            buckets[wd, default: [:]][hour, default: 0] += 1
        }

        var clusters: [PatternCluster] = []
        for wd in 1...7 {
            guard let hours = buckets[wd] else { continue }
            // Find hours that individually meet threshold
            let qualifying = hours.filter { hour, count in
                Double(count) / Double(total) >= minShare && count >= minCount
            }
            guard !qualifying.isEmpty else { continue }

            // Merge adjacent qualifying hours into contiguous windows
            let sorted = qualifying.keys.sorted()
            var windowStart = sorted[0]
            var windowEnd = sorted[0]
            var windowCount = qualifying[sorted[0]]!

            for i in 1..<sorted.count {
                let h = sorted[i]
                if h == windowEnd + 1 {
                    windowEnd = h
                    windowCount += qualifying[h]!
                } else {
                    clusters.append(makeCluster(wd: wd, start: windowStart, end: windowEnd, count: windowCount, total: total, symbols: symbols))
                    windowStart = h
                    windowEnd = h
                    windowCount = qualifying[h]!
                }
            }
            clusters.append(makeCluster(wd: wd, start: windowStart, end: windowEnd, count: windowCount, total: total, symbols: symbols))
        }

        return clusters.sorted { $0.share > $1.share }
    }

    private static func makeCluster(wd: Int, start: Int, end: Int, count: Int, total: Int, symbols: [String]) -> PatternCluster {
        let name: String = {
            let i = wd - 1
            return (i >= 0 && i < symbols.count) ? symbols[i] : "?"
        }()
        return PatternCluster(
            weekdayIndex: wd,
            weekdayName: name,
            startHour: start,
            endHour: end,
            headacheCount: count,
            totalHeadaches: total
        )
    }

    /// Cancels all previously scheduled pattern-based notifications, then schedules new ones
    /// for each cluster. Notifications fire 1 hour before the predicted headache window.
    static func reschedulePatternNotifications(clusters: [PatternCluster]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let patternIDs = pending.filter { $0.identifier.hasPrefix("pattern-alert-") }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: patternIDs)

        for cluster in clusters {
            let triggerHour = cluster.startHour > 0 ? cluster.startHour - 1 : 23
            var components = DateComponents()
            components.weekday = cluster.weekdayIndex
            components.hour = triggerHour
            components.minute = 0

            // Schedule for the next occurrence only — rescheduled on each capture/app-foreground.
            // Using repeated weekly triggers would keep firing stale patterns if the user's
            // schedule changes and they stop opening the app.
            guard let nextDate = Calendar.current.nextDate(
                after: Date(),
                matching: components,
                matchingPolicy: .nextTime
            ) else { continue }
            let fireComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: nextDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: fireComponents, repeats: false)

            let content = UNMutableNotificationContent()
            content.title = "Headache pattern ahead"
            content.body = notificationBody(for: cluster)
            content.sound = .default
            content.threadIdentifier = "pro-alerts"

            let id = "pattern-alert-\(cluster.weekdayIndex)-\(cluster.startHour)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// Cancels all pattern-based notifications (called when the user disables the feature).
    static func cancelAllPatternNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let patternIDs = pending.filter { $0.identifier.hasPrefix("pattern-alert-") }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: patternIDs)
    }

    private static func notificationBody(for cluster: PatternCluster) -> String {
        let timeRange = formatHourRange(start: cluster.startHour, end: cluster.endHour)
        let day = cluster.weekdayName
        let share = Int((cluster.share * 100).rounded())
        return "\(share)% of your headaches fall on \(day)s around \(timeRange)."
    }

    private static func formatHourRange(start: Int, end: Int) -> String {
        let fmt: (Int) -> String = { hour in
            var dc = DateComponents()
            dc.hour = hour
            guard let date = Calendar.current.date(from: dc) else { return "\(hour):00" }
            let f = DateFormatter()
            f.dateFormat = "h a"
            return f.string(from: date).lowercased()
        }
        if start == end { return fmt(start) }
        return "\(fmt(start))–\(fmt(end))"
    }

    /// Runs pattern analysis from a ModelContext and schedules notifications if enabled.
    @MainActor
    static func schedulePatternAlertsIfEnabled(in context: ModelContext) async {
        refreshPersonalAlertProfile(in: context)

        let prefs = ProAlertPreferenceValues.current()
        guard prefs.patternAlertsEnabled else {
            await cancelAllPatternNotifications()
            return
        }
        guard await StoreService.shared.isProUnlocked else {
            await cancelAllPatternNotifications()
            return
        }

        let allEvents = allHeadacheEvents(in: context)
        let clusters = analyzeTimePatterns(events: allEvents, sensitivity: prefs.patternAlertSensitivity)
        await reschedulePatternNotifications(clusters: clusters)
    }

    private static func allHeadacheEvents(in context: ModelContext) -> [HeadacheEvent] {
        var descriptor = FetchDescriptor<HeadacheEvent>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        descriptor.fetchLimit = 2000
        return (try? context.fetch(descriptor)) ?? []
    }
}
