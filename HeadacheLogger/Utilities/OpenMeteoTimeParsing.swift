import Foundation

/// Shared by `EnvironmentService` and unit tests — Open-Meteo hourly `time` strings vary slightly by endpoint.
enum OpenMeteoTimeParsing {
    static func hourDate(from raw: String, timeZone: TimeZone) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        for format in formats {
            formatter.dateFormat = format
            if let d = formatter.date(from: trimmed) { return d }
        }
        return ISO8601DateFormatter().date(from: trimmed)
    }
}
