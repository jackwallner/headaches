import Foundation
import SwiftData

enum ImportStrategy {
    case skipExisting
    case overwriteExisting
}

struct ImportResult {
    let imported: Int
    let skipped: Int
    let overwritten: Int
    let errors: Int
}

enum ImportService {
    nonisolated(unsafe) private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Parse a CSV export file and return an array of parsed rows as dictionaries.
    static func parseCSV(from url: URL) throws -> [[String: String]] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = parseCSVLines(from: contents)

        guard let headerLine = lines.first else {
            throw ImportError.emptyFile
        }

        let header = parseCSVRow(headerLine)
        guard !header.isEmpty else {
            throw ImportError.invalidHeader
        }

        var rows: [[String: String]] = []
        var errorCount = 0

        for line in lines.dropFirst() {
            let fields = parseCSVRow(line)
            if fields.count == header.count {
                var row: [String: String] = [:]
                for (index, value) in fields.enumerated() {
                    row[header[index]] = value
                }
                rows.append(row)
            } else {
                errorCount += 1
            }
        }

        return rows
    }

    /// Import parsed rows into the SwiftData context.
    static func importEvents(
        from rows: [[String: String]],
        into modelContext: ModelContext,
        strategy: ImportStrategy
    ) -> ImportResult {
        var imported = 0
        var skipped = 0
        var overwritten = 0
        var errors = 0

        for row in rows {
            guard let idString = row["event_id"], let id = UUID(uuidString: idString) else {
                errors += 1
                continue
            }

            let existingPredicate = #Predicate<HeadacheEvent> { $0.id == id }
            var descriptor = FetchDescriptor<HeadacheEvent>(predicate: existingPredicate)
            descriptor.fetchLimit = 1

            let existing = try? modelContext.fetch(descriptor).first

            if let existing {
                switch strategy {
                case .skipExisting:
                    skipped += 1
                    continue
                case .overwriteExisting:
                    applyRow(row, to: existing)
                    overwritten += 1
                }
            } else {
                if let event = createEvent(from: row, id: id) {
                    modelContext.insert(event)
                    imported += 1
                } else {
                    errors += 1
                }
            }
        }

        if imported + overwritten > 0 {
            try? modelContext.save()
        }

        return ImportResult(
            imported: imported,
            skipped: skipped,
            overwritten: overwritten,
            errors: errors
        )
    }

    // MARK: - Private CSV Parsing

    /// Split CSV content into lines, handling CRLF and quoted newlines.
    private static func parseCSVLines(from contents: String) -> [String] {
        // Replace CRLF with LF for consistent handling
        let normalized = contents.replacingOccurrences(of: "\r\n", with: "\n")
        var lines: [String] = []
        var current = ""
        var inQuotes = false

        for char in normalized {
            switch char {
            case "\"":
                inQuotes.toggle()
                current.append(char)
            case "\n":
                if inQuotes {
                    current.append(char)
                } else {
                    let trimmed = current.trimmingCharacters(in: .newlines)
                    if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                        lines.append(trimmed)
                    }
                    current = ""
                }
            default:
                current.append(char)
            }
        }

        let trimmed = current.trimmingCharacters(in: .newlines)
        if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
            lines.append(trimmed)
        }

        return lines
    }

    /// Parse a single CSV row into fields, handling quoted values and escaped quotes.
    private static func parseCSVRow(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            switch char {
            case "\"":
                inQuotes.toggle()
            case ",":
                if inQuotes {
                    current.append(char)
                } else {
                    let cleaned = unescapeQuotes(current).trimmingCharacters(in: .whitespaces)
                    fields.append(cleaned)
                    current = ""
                }
            default:
                current.append(char)
            }
        }

        let cleaned = unescapeQuotes(current).trimmingCharacters(in: .whitespaces)
        fields.append(cleaned)
        return fields
    }

    private static func unescapeQuotes(_ value: String) -> String {
        value.replacingOccurrences(of: "\"\"", with: "\"")
    }

    // MARK: - Event Creation and Population

    private static func createEvent(from row: [String: String], id: UUID) -> HeadacheEvent? {
        guard let timestampString = row["timestamp"],
              let timestamp = timestampFormatter.date(from: timestampString) else {
            return nil
        }

        let event = HeadacheEvent(timestamp: timestamp)
        event.id = id
        applyRow(row, to: event)
        return event
    }

    private static func applyRow(_ row: [String: String], to event: HeadacheEvent) {
        let calendar = Calendar.current

        if let ts = row["timestamp"].flatMap({ timestampFormatter.date(from: $0) }) {
            event.timestamp = ts
        }

        event.timezoneIdentifier = row["timezone"] ?? TimeZone.current.identifier
        event.weekdayIndex = row["weekday_index"].flatMap(Int.init) ?? calendar.component(.weekday, from: event.timestamp)
        event.weekdayName = row["weekday"] ?? ""
        event.hourOfDay = row["hour"].flatMap(Int.init) ?? calendar.component(.hour, from: event.timestamp)
        event.minuteOfHour = row["minute"].flatMap(Int.init) ?? calendar.component(.minute, from: event.timestamp)
        event.partOfDayRaw = row["part_of_day"] ?? PartOfDay.from(event.timestamp, calendar: calendar).rawValue

        event.captureStatusRaw = row["capture_status"] ?? CaptureStatus.complete.rawValue
        event.healthStatusRaw = row["health_status"] ?? CaptureSourceStatus.captured.rawValue
        event.environmentStatusRaw = row["environment_status"] ?? CaptureSourceStatus.captured.rawValue
        event.healthStatusMessage = emptyToNil(row["health_message"])
        event.environmentStatusMessage = emptyToNil(row["environment_message"])

        // Prefer the structured locality/region columns (newer exports); fall back to the
        // combined human-readable `location` column for files exported before they existed.
        event.locality = emptyToNil(row["locality"]) ?? emptyToNil(row["location"])
        event.region = emptyToNil(row["region"])
        event.altitudeM = parseDouble(row["altitude_m"])
        event.weatherSummary = emptyToNil(row["weather_summary"])
        event.weatherCode = row["weather_code"].flatMap(Int.init)
        event.temperatureC = parseDouble(row["temperature_c"])
        event.apparentTemperatureC = parseDouble(row["feels_like_c"])
        event.humidityPercent = parseDouble(row["humidity_percent"])
        event.pressureHpa = parseDouble(row["pressure_hpa"])
        event.pressureTrendRaw = row["pressure_trend"] ?? PressureTrend.unavailable.rawValue
        event.precipitationMm = parseDouble(row["precipitation_mm"])
        event.windSpeedKph = parseDouble(row["wind_speed_kph"])
        event.windDirectionDegrees = parseDouble(row["wind_direction_deg"])
        event.cloudCoverPercent = parseDouble(row["cloud_cover_percent"])
        event.uvIndex = parseDouble(row["uv_index"])
        event.dewPointC = parseDouble(row["dew_point_c"])
        event.usAQI = parseDouble(row["us_aqi"])
        event.europeanAQI = parseDouble(row["european_aqi"])
        event.pm25 = parseDouble(row["pm2_5"])
        event.pm10 = parseDouble(row["pm10"])
        event.ozone = parseDouble(row["ozone"])
        event.nitrogenDioxide = parseDouble(row["nitrogen_dioxide"])
        event.sulphurDioxide = parseDouble(row["sulphur_dioxide"])
        event.carbonMonoxide = parseDouble(row["carbon_monoxide"])
        event.alderPollen = parseDouble(row["alder_pollen"])
        event.birchPollen = parseDouble(row["birch_pollen"])
        event.grassPollen = parseDouble(row["grass_pollen"])
        event.mugwortPollen = parseDouble(row["mugwort_pollen"])
        event.olivePollen = parseDouble(row["olive_pollen"])
        event.ragweedPollen = parseDouble(row["ragweed_pollen"])

        event.stepsToday = row["steps_today"].flatMap(Int.init)
        event.activeEnergyKcalToday = parseDouble(row["active_energy_kcal_today"])
        event.distanceWalkingRunningKmToday = parseDouble(row["distance_walking_running_km_today"])
        event.exerciseMinutesToday = parseDouble(row["exercise_minutes_today"])
        event.sleepHoursLastNight = parseDouble(row["sleep_hours_last_night"])
        event.lastMainSleepWakeTime = row["last_main_sleep_wake_utc"].flatMap { timestampFormatter.date(from: $0) }
        event.hoursSinceMainSleepWake = parseDouble(row["hours_since_main_sleep_wake"])
        event.restingHeartRateBpm = parseDouble(row["resting_heart_rate_bpm"])
        event.recentHeartRateAverageBpm = parseDouble(row["recent_heart_rate_avg_bpm"])
        event.hrvSDNNMs = parseDouble(row["hrv_sdnn_ms"])
        event.respiratoryRateBrpm = parseDouble(row["respiratory_rate_brpm"])
        event.workoutsLast24h = row["workouts_last_24h"].flatMap(Int.init)
        event.workoutMinutesLast24h = parseDouble(row["workout_minutes_last_24h"])
        event.environmentalAudioExposureDbA = parseDouble(row["environmental_audio_db_a"])
        event.oxygenSaturationPercent = parseDouble(row["oxygen_saturation_percent"])
        event.vo2MaxMlPerKgPerMin = parseDouble(row["vo2_max_ml_kg_min"])
        event.walkingSpeedMetersPerSecond = parseDouble(row["walking_speed_m_s"])
        event.appleStandMinutesToday = parseDouble(row["apple_stand_minutes_today"])
        event.basalEnergyKcalToday = parseDouble(row["basal_energy_kcal_today"])
        event.flightsClimbedToday = parseDouble(row["flights_climbed_today"])
        event.mindfulMinutesToday = parseDouble(row["mindful_minutes_today"])
        event.barometricPressureDeltaHpa6h = parseDouble(row["barometric_pressure_delta_hpa_6h"])
        event.caffeineMgToday = parseDouble(row["caffeine_mg_today"])
        event.waterMlToday = parseDouble(row["water_ml_today"])
        event.daysSinceLastPeriodStart = row["days_since_last_period_start"].flatMap(Int.init)
        event.bloodPressureSystolicMmHg = parseDouble(row["blood_pressure_systolic_mmhg"])
        event.bloodPressureDiastolicMmHg = parseDouble(row["blood_pressure_diastolic_mmhg"])
        event.bloodGlucoseMgPerDL = parseDouble(row["blood_glucose_mg_dl"])
        event.headphoneAudioExposureDbA = parseDouble(row["headphone_audio_db_a"])
        event.timeInDaylightMinutesToday = parseDouble(row["time_in_daylight_minutes_today"])
        event.batteryLevelPercent = parseDouble(row["battery_level_percent"])
        event.isCharging = parseBool(row["is_charging"])
        event.isLowPowerMode = parseBool(row["is_low_power_mode"])
        event.motionActivityRaw = emptyToNil(row["motion_activity"])

        event.severityRaw = emptyToNil(row["severity"])
        event.userNotes = emptyToNil(row["user_notes"])

        event.createdAt = event.createdAt
        event.captureCompletedAt = event.captureCompletedAt ?? event.timestamp
    }

    private static func parseDouble(_ string: String?) -> Double? {
        guard let string, !string.isEmpty else { return nil }
        return numberFormatter.number(from: string)?.doubleValue
    }

    private static func parseBool(_ string: String?) -> Bool? {
        guard let string, !string.isEmpty else { return nil }
        switch string.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }

    private static func emptyToNil(_ string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        return string
    }
}

enum ImportError: LocalizedError {
    case emptyFile
    case invalidHeader
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            "The file is empty or contains no valid data rows."
        case .invalidHeader:
            "The file doesn't appear to be a valid headache event export."
        case .parseError(let message):
            "Parse error: \(message)"
        }
    }
}
