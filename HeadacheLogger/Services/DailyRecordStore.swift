import Foundation

struct DailyRecord: Codable, Sendable, Equatable {
    var date: Date
    var hadHeadache: Bool
    var headacheCount: Int
    var pressureTrendRaw: String
    var usAQI: Double?
    var weatherFetched: Bool
    var sleepHoursLastNight: Double?
    var sleepFetched: Bool

    var pressureTrend: PressureTrend {
        PressureTrend(rawValue: pressureTrendRaw) ?? .unavailable
    }

    var isFallingPressure: Bool {
        pressureTrend == .falling
    }

    var isElevatedAQI: Bool {
        (usAQI ?? 0) >= 75
    }

    static var empty: DailyRecord {
        DailyRecord(
            date: Date.distantPast,
            hadHeadache: false,
            headacheCount: 0,
            pressureTrendRaw: PressureTrend.unavailable.rawValue,
            usAQI: nil,
            weatherFetched: false,
            sleepHoursLastNight: nil,
            sleepFetched: false
        )
    }
}

enum DailyRecordStore {
    private static let fileName = "daily_records.json"

    private static var fileURL: URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: HeadacheAppGroup.identifier) else {
            return nil
        }
        return container.appendingPathComponent(fileName)
    }

    static func load() -> [DailyRecord] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([DailyRecord].self, from: data) else {
            return []
        }
        return records
    }

    static func save(_ records: [DailyRecord]) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: url)
    }

    static func normalizeDate(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    /// Build or update daily records from headache events + backfilled weather.
    /// - Events with pressure data mark that day as `hadHeadache = true` and contribute weather.
    /// - Days without any event get `hadHeadache = false` (weather must be backfilled separately).
    static func rebuild(from events: [HeadacheEvent]) -> [DailyRecord] {
        let calendar = Calendar.current
        var byDate: [Date: DailyRecord] = [:]

        for event in events {
            let day = normalizeDate(event.timestamp)
            var record = byDate[day] ?? DailyRecord(
                date: day,
                hadHeadache: false,
                headacheCount: 0,
                pressureTrendRaw: PressureTrend.unavailable.rawValue,
                usAQI: nil,
                weatherFetched: false,
                sleepHoursLastNight: nil,
                sleepFetched: false
            )
            record.hadHeadache = true
            record.headacheCount += 1
            if event.pressureTrend != .unavailable {
                record.pressureTrendRaw = event.pressureTrend.rawValue
            }
            if let aqi = event.usAQI {
                record.usAQI = max(record.usAQI ?? 0, aqi)
            }
            if let sleepHours = event.sleepHoursLastNight {
                record.sleepHoursLastNight = max(record.sleepHoursLastNight ?? 0, sleepHours)
                record.sleepFetched = true
            }
            record.weatherFetched = event.environmentStatus == .captured
            byDate[day] = record
        }

        return byDate.values.sorted { $0.date < $1.date }
    }

    /// Fill in missing days between the first record and today. Non-headache days get `hadHeadache = false`.
    static func fillGapDays(_ records: [DailyRecord], from startDate: Date, to endDate: Date = Date()) -> [DailyRecord] {
        let cal = Calendar.current
        let start = normalizeDate(startDate)
        let end = normalizeDate(endDate)

        var byDate: [Date: DailyRecord] = [:]
        for r in records {
            byDate[r.date] = r
        }

        var cursor = start
        while cursor <= end {
            if byDate[cursor] == nil {
                byDate[cursor] = DailyRecord(
                    date: cursor,
                    hadHeadache: false,
                    headacheCount: 0,
                    pressureTrendRaw: PressureTrend.unavailable.rawValue,
                    usAQI: nil,
                    weatherFetched: false,
                    sleepHoursLastNight: nil,
                    sleepFetched: false
                )
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86_400)
        }

        return byDate.values.sorted { $0.date < $1.date }
    }

    /// Update a single day's record and persist.
    static func upsert(_ record: DailyRecord) {
        var records = load()
        if let idx = records.firstIndex(where: { normalizeDate($0.date) == normalizeDate(record.date) }) {
            records[idx] = record
        } else {
            records.append(record)
            records.sort { $0.date < $1.date }
        }
        save(records)
    }

    /// Ensure yesterday has a record. Called on app foreground.
    static func ensureYesterdayRecord() {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()).map({ normalizeDate($0) }) else { return }

        let records = load()
        if records.contains(where: { normalizeDate($0.date) == yesterday }) { return }

        var newRecord = DailyRecord(
            date: yesterday,
            hadHeadache: false,
            headacheCount: 0,
            pressureTrendRaw: PressureTrend.unavailable.rawValue,
            usAQI: nil,
            weatherFetched: false,
            sleepHoursLastNight: nil,
            sleepFetched: false
        )
        newRecord.hadHeadache = records.contains(where: { normalizeDate($0.date) == yesterday && $0.hadHeadache })
        upsert(newRecord)
    }

    /// Count statistics for probability calculations.
    struct ConditionCounts {
        let totalDays: Int
        let headacheDays: Int
        let conditionDays: Int
        let headacheConditionDays: Int

        var pHeadacheGivenCondition: Double {
            conditionDays > 0 ? Double(headacheConditionDays) / Double(conditionDays) : 0
        }

        var pHeadacheGivenNoCondition: Double {
            let noCondition = totalDays - conditionDays
            let headacheNoCondition = headacheDays - headacheConditionDays
            return noCondition > 0 ? Double(headacheNoCondition) / Double(noCondition) : 0
        }

        var relativeRisk: Double {
            let bg = pHeadacheGivenNoCondition
            return bg > 0 ? pHeadacheGivenCondition / bg : 0
        }

        var lift: Double {
            relativeRisk - 1.0
        }
    }

    static func pressureConditionCounts(from records: [DailyRecord]) -> ConditionCounts {
        let weatherDays = records.filter { $0.weatherFetched }
        let total = weatherDays.count
        let headacheDays = weatherDays.filter { $0.hadHeadache }.count
        let fallingDays = weatherDays.filter { $0.isFallingPressure }.count
        let headacheFallingDays = weatherDays.filter { $0.hadHeadache && $0.isFallingPressure }.count
        return ConditionCounts(
            totalDays: total,
            headacheDays: headacheDays,
            conditionDays: fallingDays,
            headacheConditionDays: headacheFallingDays
        )
    }

    static func aqiConditionCounts(from records: [DailyRecord]) -> ConditionCounts {
        let weatherDays = records.filter { $0.weatherFetched }
        let total = weatherDays.count
        let headacheDays = weatherDays.filter { $0.hadHeadache }.count
        let elevatedDays = weatherDays.filter { $0.isElevatedAQI }.count
        let headacheElevatedDays = weatherDays.filter { $0.hadHeadache && $0.isElevatedAQI }.count
        return ConditionCounts(
            totalDays: total,
            headacheDays: headacheDays,
            conditionDays: elevatedDays,
            headacheConditionDays: headacheElevatedDays
        )
    }

    /// Backfill sleep hours from HealthKit for all records that don't already have sleep data.
    /// Sleep is queried for the night before each record's date.
    static func backfillSleep(records: [DailyRecord], healthKit: HealthKitService) async -> [DailyRecord] {
        var updated = records
        for i in updated.indices {
            guard !updated[i].sleepFetched else { continue }
            if let hours = await healthKit.fetchSleepHoursForNightBefore(updated[i].date) {
                updated[i].sleepHoursLastNight = hours
                updated[i].sleepFetched = true
            }
        }
        return updated
    }

    /// Compute lift-based counts for sleep: how much more likely is a headache given a sleep range?
    struct SleepBucketCounts {
        let label: String
        let range: Range<Double>
        let totalDays: Int
        let headacheDays: Int
        var headacheRate: Double {
            totalDays > 0 ? Double(headacheDays) / Double(totalDays) : 0
        }
    }

    static func sleepConditionCounts(from records: [DailyRecord]) -> [SleepBucketCounts] {
        let sleepRecords = records.filter { $0.sleepFetched }
        let bins: [(label: String, range: Range<Double>)] = [
            ("<5h", 0..<5),
            ("5–6h", 5..<6),
            ("6–7h", 6..<7),
            ("7–8h", 7..<8),
            ("8h+", 8..<48)
        ]
        return bins.map { bin in
            let inBucket = sleepRecords.filter { rec in
                guard let hours = rec.sleepHoursLastNight else { return false }
                return bin.range.contains(hours)
            }
            return SleepBucketCounts(
                label: bin.label,
                range: bin.range,
                totalDays: inBucket.count,
                headacheDays: inBucket.filter(\.hadHeadache).count
            )
        }
    }
}
