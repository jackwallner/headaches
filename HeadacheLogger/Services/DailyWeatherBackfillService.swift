import Foundation

enum DailyWeatherBackfillService {
    static let timeout: TimeInterval = 15

    /// Fetch weather for a date range and update DailyRecords that lack weather data.
    /// Dates are fetched in batches to avoid huge API responses.
    static func backfill(
        for records: [DailyRecord],
        latitude: Double,
        longitude: Double,
        maxDaysPerRequest: Int = 30
    ) async -> [DailyRecord] {
        let weatherDays = records.filter { !$0.weatherFetched }
        guard !weatherDays.isEmpty else { return records }
        guard let first = weatherDays.first?.date, let last = weatherDays.last?.date else { return records }

        var updated = records
        let calendar = Calendar.current
        let start = DailyRecordStore.normalizeDate(first)

        let batches = computeBatches(from: start, to: last, maxDaysPerRequest: maxDaysPerRequest, calendar: calendar)

        for batch in batches {
            let batchRecords = records.filter { r in
                let d = DailyRecordStore.normalizeDate(r.date)
                return d >= batch.start && d <= batch.end && !r.weatherFetched
            }
            guard !batchRecords.isEmpty else { continue }

            async let weatherTask = fetchWeatherBatch(
                latitude: latitude,
                longitude: longitude,
                startDate: batch.start,
                endDate: batch.end
            )
            async let aqiTask = fetchAirQualityBatch(
                latitude: latitude,
                longitude: longitude,
                startDate: batch.start,
                endDate: batch.end
            )

            let weatherData = await weatherTask
            let aqiData = await aqiTask

            for i in updated.indices {
                let d = DailyRecordStore.normalizeDate(updated[i].date)
                guard d >= batch.start && d <= batch.end else { continue }
                let dayStr = dateString(from: d)

                if let (trend, fetched) = weatherData?[dayStr] {
                    updated[i].pressureTrendRaw = trend.rawValue
                    if fetched { updated[i].weatherFetched = true }
                }
                if let aqi = aqiData?[dayStr] {
                    updated[i].usAQI = aqi
                    updated[i].weatherFetched = true
                }
            }
        }

        return updated
    }

    private struct DateBatch: Sendable {
        let start: Date
        let end: Date
    }

    private static func computeBatches(from start: Date, to end: Date, maxDaysPerRequest: Int, calendar: Calendar) -> [DateBatch] {
        var batches: [DateBatch] = []
        var cursor = start
        while cursor <= end {
            let batchEnd = min(
                calendar.date(byAdding: .day, value: maxDaysPerRequest - 1, to: cursor) ?? cursor.addingTimeInterval(Double(maxDaysPerRequest - 1) * 86_400),
                end
            )
            batches.append(DateBatch(start: cursor, end: batchEnd))
            cursor = calendar.date(byAdding: .day, value: 1, to: batchEnd) ?? batchEnd.addingTimeInterval(86_400)
        }
        return batches
    }

    /// Returns [dateString: (PressureTrend, hasData)] for each day in the range.
    private static func fetchWeatherBatch(
        latitude: Double,
        longitude: Double,
        startDate: Date,
        endDate: Date
    ) async -> [String: (PressureTrend, Bool)]? {
        let start = dateString(from: startDate)
        let end = dateString(from: endDate)

        var components = URLComponents(string: "https://archive-api.open-meteo.com/v1/archive")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: start),
            URLQueryItem(name: "end_date", value: end),
            URLQueryItem(name: "hourly", value: "pressure_msl"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(WeatherArchiveResponse.self, from: data) else {
            return nil
        }

        let h = decoded.hourly
        var result: [String: (PressureTrend, Bool)] = [:]
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        var pressuresByDay: [String: [Double]] = [:]

        for (i, timeStr) in h.time.enumerated() {
            guard i < h.pressureMsl.count, let pressure = h.pressureMsl[i] else { continue }
            let dayStr = String(timeStr.prefix(10))
            pressuresByDay[dayStr, default: []].append(pressure)
        }

        for (day, pressures) in pressuresByDay {
            guard pressures.count >= 2 else {
                result[day] = (.unavailable, false)
                continue
            }
            let firstThree = pressures.prefix(3)
            let lastThree = pressures.suffix(3)
            let firstAvg = firstThree.reduce(0, +) / Double(firstThree.count)
            let lastAvg = lastThree.reduce(0, +) / Double(lastThree.count)
            let delta = lastAvg - firstAvg
            let trend: PressureTrend
            if delta <= -1.5 {
                trend = .falling
            } else if delta >= 1.5 {
                trend = .rising
            } else {
                trend = .steady
            }
            result[day] = (trend, true)
        }

        return result
    }

    /// Returns [dateString: usAQI] for each day in the range.
    private static func fetchAirQualityBatch(
        latitude: Double,
        longitude: Double,
        startDate: Date,
        endDate: Date
    ) async -> [String: Double]? {
        let start = dateString(from: startDate)
        let end = dateString(from: endDate)

        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: start),
            URLQueryItem(name: "end_date", value: end),
            URLQueryItem(name: "hourly", value: "us_aqi"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(AQIArchiveResponse.self, from: data) else {
            return nil
        }

        let h = decoded.hourly
        var result: [String: Double] = [:]

        for (i, timeStr) in h.time.enumerated() {
            guard i < h.usAqi.count, let aqi = h.usAqi[i] else { continue }
            let dayStr = String(timeStr.prefix(10))
            result[dayStr] = max(result[dayStr] ?? 0, aqi)
        }

        return result
    }

    private static func dateString(from date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    // MARK: - Response models

    private struct WeatherArchiveResponse: Decodable {
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

    private struct AQIArchiveResponse: Decodable {
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
}
