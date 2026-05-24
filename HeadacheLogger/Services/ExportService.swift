import Foundation
import SwiftUI
import UIKit

enum ExportService {
    static func exportCSV(events: [HeadacheEvent]) throws -> URL {
        let timestampFormatter = makeTimestampFormatter()
        let decimalFormatter = makeDecimalFormatter()

        let generatedAt = ISO8601DateFormatter().string(from: .now)
        let preambleLines = csvPreamble(
            eventCount: events.count,
            generatedAtISO8601: generatedAt
        )

        let header = [
            "event_id",
            "timestamp",
            "timezone",
            "weekday",
            "weekday_index",
            "hour",
            "minute",
            "part_of_day",
            "capture_status",
            "health_status",
            "environment_status",
            "location",
            "weather_summary",
            "temperature_c",
            "feels_like_c",
            "temperature_f",
            "feels_like_f",
            "humidity_percent",
            "pressure_hpa",
            "pressure_trend",
            "precipitation_mm",
            "wind_speed_kph",
            "wind_direction_deg",
            "cloud_cover_percent",
            "uv_index",
            "us_aqi",
            "european_aqi",
            "pm2_5",
            "pm10",
            "ozone",
            "nitrogen_dioxide",
            "sulphur_dioxide",
            "carbon_monoxide",
            "alder_pollen",
            "birch_pollen",
            "grass_pollen",
            "mugwort_pollen",
            "olive_pollen",
            "ragweed_pollen",
            "steps_today",
            "active_energy_kcal_today",
            "distance_walking_running_km_today",
            "exercise_minutes_today",
            "sleep_hours_last_night",
            "last_main_sleep_wake_utc",
            "hours_since_main_sleep_wake",
            "resting_heart_rate_bpm",
            "recent_heart_rate_avg_bpm",
            "hrv_sdnn_ms",
            "respiratory_rate_brpm",
            "workouts_last_24h",
            "workout_minutes_last_24h",
            "environmental_audio_db_a",
            "oxygen_saturation_percent",
            "vo2_max_ml_kg_min",
            "walking_speed_m_s",
            "apple_stand_minutes_today",
            "basal_energy_kcal_today",
            "flights_climbed_today",
            "mindful_minutes_today",
            "barometric_pressure_delta_hpa_6h",
            "health_message",
            "environment_message",
            "severity",
            "user_notes",
        ].joined(separator: ",")

        let rows = events.map { event in
            [
                csv(event.id.uuidString),
                csv(timestampFormatter.string(from: event.timestamp)),
                csv(event.timezoneIdentifier),
                csv(event.weekdayName),
                csv(String(event.weekdayIndex)),
                csv(String(event.hourOfDay)),
                csv(String(event.minuteOfHour)),
                csv(event.partOfDay.rawValue),
                csv(event.captureStatus.rawValue),
                csv(event.healthStatus.rawValue),
                csv(event.environmentStatus.rawValue),
                csv(event.locationLabel),
                csv(event.weatherSummary),
                csv(number(event.temperatureC, formatter: decimalFormatter)),
                csv(number(event.apparentTemperatureC, formatter: decimalFormatter)),
                csv(number(event.temperatureC.map { HeadacheTemperatureFormatting.celsiusToFahrenheit($0) }, formatter: decimalFormatter)),
                csv(number(event.apparentTemperatureC.map { HeadacheTemperatureFormatting.celsiusToFahrenheit($0) }, formatter: decimalFormatter)),
                csv(number(event.humidityPercent, formatter: decimalFormatter)),
                csv(number(event.pressureHpa, formatter: decimalFormatter)),
                csv(event.pressureTrend.rawValue),
                csv(number(event.precipitationMm, formatter: decimalFormatter)),
                csv(number(event.windSpeedKph, formatter: decimalFormatter)),
                csv(number(event.windDirectionDegrees, formatter: decimalFormatter)),
                csv(number(event.cloudCoverPercent, formatter: decimalFormatter)),
                csv(number(event.uvIndex, formatter: decimalFormatter)),
                csv(number(event.usAQI, formatter: decimalFormatter)),
                csv(number(event.europeanAQI, formatter: decimalFormatter)),
                csv(number(event.pm25, formatter: decimalFormatter)),
                csv(number(event.pm10, formatter: decimalFormatter)),
                csv(number(event.ozone, formatter: decimalFormatter)),
                csv(number(event.nitrogenDioxide, formatter: decimalFormatter)),
                csv(number(event.sulphurDioxide, formatter: decimalFormatter)),
                csv(number(event.carbonMonoxide, formatter: decimalFormatter)),
                csv(number(event.alderPollen, formatter: decimalFormatter)),
                csv(number(event.birchPollen, formatter: decimalFormatter)),
                csv(number(event.grassPollen, formatter: decimalFormatter)),
                csv(number(event.mugwortPollen, formatter: decimalFormatter)),
                csv(number(event.olivePollen, formatter: decimalFormatter)),
                csv(number(event.ragweedPollen, formatter: decimalFormatter)),
                csv(event.stepsToday.map(String.init)),
                csv(number(event.activeEnergyKcalToday, formatter: decimalFormatter)),
                csv(number(event.distanceWalkingRunningKmToday, formatter: decimalFormatter)),
                csv(number(event.exerciseMinutesToday, formatter: decimalFormatter)),
                csv(number(event.sleepHoursLastNight, formatter: decimalFormatter)),
                csv(event.lastMainSleepWakeTime.map { timestampFormatter.string(from: $0) }),
                csv(number(event.hoursSinceMainSleepWake, formatter: decimalFormatter)),
                csv(number(event.restingHeartRateBpm, formatter: decimalFormatter)),
                csv(number(event.recentHeartRateAverageBpm, formatter: decimalFormatter)),
                csv(number(event.hrvSDNNMs, formatter: decimalFormatter)),
                csv(number(event.respiratoryRateBrpm, formatter: decimalFormatter)),
                csv(event.workoutsLast24h.map(String.init)),
                csv(number(event.workoutMinutesLast24h, formatter: decimalFormatter)),
                csv(number(event.environmentalAudioExposureDbA, formatter: decimalFormatter)),
                csv(number(event.oxygenSaturationPercent, formatter: decimalFormatter)),
                csv(number(event.vo2MaxMlPerKgPerMin, formatter: decimalFormatter)),
                csv(number(event.walkingSpeedMetersPerSecond, formatter: decimalFormatter)),
                csv(number(event.appleStandMinutesToday, formatter: decimalFormatter)),
                csv(number(event.basalEnergyKcalToday, formatter: decimalFormatter)),
                csv(number(event.flightsClimbedToday, formatter: decimalFormatter)),
                csv(number(event.mindfulMinutesToday, formatter: decimalFormatter)),
                csv(number(event.barometricPressureDeltaHpa6h, formatter: decimalFormatter)),
                csv(event.healthStatusMessage),
                csv(event.environmentStatusMessage),
                csv(event.severity?.rawValue),
                csv(event.userNotes),
            ].joined(separator: ",")
        }

        // M12: CRLF row separator per RFC 4180; Excel and a handful of Windows tools parse
        // quoted multi-line cells more reliably with CRLF than LF.
        let contents = (preambleLines + [header] + rows).joined(separator: "\r\n")
        let filename = "headache-events-\(Int(Date.now.timeIntervalSince1970)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Lines prefixed with `#` so spreadsheet tools and simple parsers can treat them as comments; tabular CSV starts after the preamble.
    private static func csvPreamble(eventCount: Int, generatedAtISO8601: String) -> [String] {
        [
            "# One Tap Headache Tracker: exported headache event log",
            "# What this file is: one row per time you tapped Headache in the app; each row is a timestamped snapshot of optional context (not a diagnosis).",
            "# Time: timestamp (UTC ISO8601 with fractional seconds), timezone ID, weekday name, hour/minute, part_of_day (overnight/morning/afternoon/evening).",
            "# Health (Apple Health when permitted): activity (steps, active/basal energy, distance, exercise, stand, flights), sleep (hours in window, inferred main-sleep wake time, hours since wake), heart (resting, recent avg, HRV, SpO₂, VO₂ max, walking speed), breathing rate, environmental audio (6h avg dB), mindful minutes today, barometric pressure change over 6h (device samples), workouts in last 24h.",
            "# Environment (when location/weather services work): human-readable location, weather summary, temperature (°C and °F columns), humidity, pressure and trend, precipitation, wind, cloud cover, UV, air quality indices and pollutants, pollen-style counts when exposed by the data provider.",
            "# Status columns: capture_status plus health_status / environment_status reflect whether those bundles were captured; health_message and environment_message explain gaps or errors when present.",
            "# severity: optional rating (slight/medium/extreme) captured at tap time when the prompt is enabled.",
            "# user_notes: optional text you can add at tap time or later in History.",
            "# Empty quoted cells mean the value was unavailable or not recorded for that event.",
            "# This export is for personal tracking and sharing with a clinician or researcher; it does not establish medical facts by itself.",
            "#",
            "# export_generated_at_utc: \(generatedAtISO8601)",
            "# row_count: \(eventCount)",
            "#",
        ]
    }

    private static func csv(_ value: String?) -> String {
        let raw = value ?? ""
        let escaped = raw.replacingOccurrences(of: "\"", with: "\"\"")
        let needsFormulaGuard = escaped.first.map({ "=+-@".contains($0) }) == true
            && Double(escaped) == nil
        let safe = needsFormulaGuard ? "'" + escaped : escaped
        return "\"\(safe)\""
    }

    private static func number(_ value: Double?, formatter: NumberFormatter) -> String? {
        guard let value else { return nil }
        return formatter.string(from: NSNumber(value: value))
    }

    private static func makeTimestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func makeDecimalFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.minimumIntegerDigits = 1
        return formatter
    }

    // MARK: - Doctor PDF

    /// Renders a one-page clinical-style report covering the trailing 90 days.
    @MainActor
    static func exportDoctorPDF(events: [HeadacheEvent], now: Date = .now) throws -> URL {
        let calendar = Calendar.current
        let windowDays = 90
        let windowEnd = now
        let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: calendar.startOfDay(for: now)) ?? now
        let inWindow = events.filter { $0.timestamp >= windowStart && $0.timestamp <= windowEnd }
        let heatmap = HeatmapData.build(from: events, days: windowDays, endingAt: now)
        let summary = InsightsEngine.summarize(events)

        // US Letter portrait.
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: UIGraphicsPDFRendererFormat())

        let filename = "headache-report-\(Int(now.timeIntervalSince1970)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        try renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            var y: CGFloat = 36
            let leftMargin: CGFloat = 36
            let rightMargin: CGFloat = 36
            let contentWidth = pageRect.width - leftMargin - rightMargin

            y = drawHeader(at: y, leftMargin: leftMargin, contentWidth: contentWidth, windowStart: windowStart, windowEnd: windowEnd, generatedAt: now)
            y += 16

            y = drawSummaryStats(at: y, leftMargin: leftMargin, contentWidth: contentWidth, events: inWindow, calendar: calendar)
            y += 18

            y = drawHeatmap(at: y, leftMargin: leftMargin, contentWidth: contentWidth, days: heatmap)
            y += 18

            y = drawTopPatterns(at: y, leftMargin: leftMargin, contentWidth: contentWidth, summary: summary)
            y += 18

            drawFooter(in: pageRect, leftMargin: leftMargin)
        }

        return url
    }

    private static func drawHeader(at y: CGFloat, leftMargin: CGFloat, contentWidth: CGFloat, windowStart: Date, windowEnd: Date, generatedAt: Date) -> CGFloat {
        let title = "Headache Report"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 26, weight: .heavy),
            .foregroundColor: UIColor.label,
        ]
        (title as NSString).draw(at: CGPoint(x: leftMargin, y: y), withAttributes: titleAttrs)

        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .medium
        let subtitle = "\(dateFmt.string(from: windowStart)) to \(dateFmt.string(from: windowEnd))"
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        (subtitle as NSString).draw(at: CGPoint(x: leftMargin, y: y + 32), withAttributes: subtitleAttrs)

        let generated = "Generated \(dateFmt.string(from: generatedAt))"
        let genSize = (generated as NSString).size(withAttributes: subtitleAttrs)
        (generated as NSString).draw(
            at: CGPoint(x: leftMargin + contentWidth - genSize.width, y: y + 32),
            withAttributes: subtitleAttrs
        )

        let separatorY = y + 54
        UIColor.separator.setStroke()
        let path = UIBezierPath()
        path.lineWidth = 0.5
        path.move(to: CGPoint(x: leftMargin, y: separatorY))
        path.addLine(to: CGPoint(x: leftMargin + contentWidth, y: separatorY))
        path.stroke()

        return separatorY + 8
    }

    private static func drawSummaryStats(at y: CGFloat, leftMargin: CGFloat, contentWidth: CGFloat, events: [HeadacheEvent], calendar: Calendar) -> CGFloat {
        let total = events.count
        let attackDays = Set(events.map { calendar.startOfDay(for: $0.timestamp) }).count
        let severities = events.compactMap(\.severity)
        let extreme = severities.filter { $0 == .extreme }.count

        var dayCounts: [Int: Int] = [:]
        var partCounts: [PartOfDay: Int] = [:]
        for event in events {
            dayCounts[event.weekdayIndex, default: 0] += 1
            partCounts[event.partOfDay, default: 0] += 1
        }
        let topWeekday: String = {
            guard let top = dayCounts.max(by: { $0.value < $1.value })?.key else { return "—" }
            let symbols = calendar.standaloneWeekdaySymbols
            let i = top - 1
            return (i >= 0 && i < symbols.count) ? symbols[i] : "—"
        }()
        let topPart: String = {
            guard let top = partCounts.max(by: { $0.value < $1.value })?.key else { return "—" }
            return top.rawValue.capitalized
        }()

        let stats: [(String, String)] = [
            ("Attacks", String(total)),
            ("Days affected", String(attackDays)),
            ("Severe rated", String(extreme)),
            ("Peak weekday", topWeekday),
            ("Peak time", topPart),
        ]

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor.label,
        ]
        ("Summary" as NSString).draw(at: CGPoint(x: leftMargin, y: y), withAttributes: headerAttrs)

        let rowY = y + 24
        let cellWidth = contentWidth / CGFloat(stats.count)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: UIColor.label,
        ]
        for (index, stat) in stats.enumerated() {
            let originX = leftMargin + cellWidth * CGFloat(index)
            (stat.0.uppercased() as NSString).draw(at: CGPoint(x: originX, y: rowY), withAttributes: labelAttrs)
            (stat.1 as NSString).draw(at: CGPoint(x: originX, y: rowY + 12), withAttributes: valueAttrs)
        }

        return rowY + 40
    }

    private static func drawHeatmap(at y: CGFloat, leftMargin: CGFloat, contentWidth: CGFloat, days: [HeatmapDay]) -> CGFloat {
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor.label,
        ]
        ("Last 90 days" as NSString).draw(at: CGPoint(x: leftMargin, y: y), withAttributes: headerAttrs)

        let gridTop = y + 22
        let cellSize: CGFloat = 14
        let cellSpacing: CGFloat = 3

        guard let first = days.first else { return gridTop + cellSize }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: first.date) // 1 = Sunday
        let leadingPad = weekday - 1

        var column = 0
        var row = leadingPad

        let brand = UIColor(red: 0.95, green: 0.25, blue: 0.36, alpha: 1.0)
        for day in days {
            let originX = leftMargin + CGFloat(column) * (cellSize + cellSpacing)
            let originY = gridTop + CGFloat(row) * (cellSize + cellSpacing)
            let rect = CGRect(x: originX, y: originY, width: cellSize, height: cellSize)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 2.5)
            heatmapPDFColor(for: day, brand: brand).setFill()
            path.fill()
            row += 1
            if row >= 7 {
                row = 0
                column += 1
            }
        }

        let gridBottom = gridTop + 7 * (cellSize + cellSpacing)

        // Legend.
        let legendY = gridBottom + 6
        let legendAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        ("Less" as NSString).draw(at: CGPoint(x: leftMargin, y: legendY + 2), withAttributes: legendAttrs)
        let swatches: [HeatmapDay] = [
            HeatmapDay(date: .now, count: 0, peakSeverity: nil),
            HeatmapDay(date: .now, count: 1, peakSeverity: .slight),
            HeatmapDay(date: .now, count: 1, peakSeverity: .medium),
            HeatmapDay(date: .now, count: 1, peakSeverity: .extreme),
        ]
        var swatchX = leftMargin + 32
        for swatch in swatches {
            let rect = CGRect(x: swatchX, y: legendY, width: 12, height: 12)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 2)
            heatmapPDFColor(for: swatch, brand: brand).setFill()
            path.fill()
            swatchX += 16
        }
        ("More" as NSString).draw(at: CGPoint(x: swatchX, y: legendY + 2), withAttributes: legendAttrs)

        return legendY + 18
    }

    private static func heatmapPDFColor(for day: HeatmapDay, brand: UIColor) -> UIColor {
        if day.count == 0 { return UIColor.tertiaryLabel.withAlphaComponent(0.25) }
        if let severity = day.peakSeverity {
            switch severity {
            case .slight: return brand.withAlphaComponent(0.35)
            case .medium: return brand.withAlphaComponent(0.65)
            case .extreme: return brand.withAlphaComponent(0.95)
            }
        }
        return brand.withAlphaComponent(day.count >= 2 ? 0.75 : 0.50)
    }

    private static func drawTopPatterns(at y: CGFloat, leftMargin: CGFloat, contentWidth: CGFloat, summary: InsightsEngine.Summary) -> CGFloat {
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor.label,
        ]
        ("Top patterns" as NSString).draw(at: CGPoint(x: leftMargin, y: y), withAttributes: headerAttrs)

        var cursorY = y + 22
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: UIColor.label,
        ]
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel,
        ]

        let topInsights = Array(summary.insights.prefix(3))
        if topInsights.isEmpty {
            let body = summary.totalEvents < InsightsEngine.minimumSampleSize
                ? "Not enough logged headaches yet for pattern detection (need at least \(InsightsEngine.minimumSampleSize))."
                : "No single signal yet stands out at the confidence threshold. Continued logging will surface patterns as they emerge."
            cursorY = drawWrappedText(body, at: CGPoint(x: leftMargin, y: cursorY), width: contentWidth, attributes: detailAttrs) + 4
            return cursorY
        }

        for insight in topInsights {
            (insight.title as NSString).draw(at: CGPoint(x: leftMargin, y: cursorY), withAttributes: titleAttrs)
            cursorY += 16
            cursorY = drawWrappedText(insight.detail, at: CGPoint(x: leftMargin, y: cursorY), width: contentWidth, attributes: detailAttrs) + 8
        }
        return cursorY
    }

    private static func drawWrappedText(_ text: String, at origin: CGPoint, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let constraint = CGSize(width: width, height: .greatestFiniteMagnitude)
        let bounds = attributed.boundingRect(with: constraint, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        attributed.draw(with: CGRect(origin: origin, size: CGSize(width: width, height: ceil(bounds.height))), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return origin.y + ceil(bounds.height)
    }

    private static func drawFooter(in pageRect: CGRect, leftMargin: CGFloat) {
        let footerY = pageRect.height - 40
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .regular),
            .foregroundColor: UIColor.tertiaryLabel,
        ]
        let line = "Generated by One Tap Headache Tracker. Descriptive only, not a clinical diagnosis. Discuss with a qualified clinician."
        (line as NSString).draw(at: CGPoint(x: leftMargin, y: footerY), withAttributes: attrs)
    }
}
