import Foundation

/// Stored weather values are always **Celsius** (Open-Meteo / internal model). UI and CSV add Fahrenheit for US users.
enum HeadacheTemperatureFormatting {
    /// Exact conversion for export and averages.
    static func celsiusToFahrenheit(_ celsius: Double) -> Double {
        celsius * 9.0 / 5.0 + 32.0
    }

    /// Whole degrees with a degree sign and unit (default Fahrenheit when `useCelsius` is false).
    static func displayInteger(celsius: Double?, useCelsius: Bool) -> String? {
        guard let c = celsius else { return nil }
        if useCelsius {
            return "\(Int(c.rounded()))°C"
        }
        let f = celsiusToFahrenheit(c)
        return "\(Int(f.rounded()))°F"
    }

    /// Weather subtitle: `"Clear, 72°F"` or `"Clear, 22°C"`.
    static func weatherSummaryWithTemperature(summary: String?, celsius: Double?, useCelsius: Bool) -> String? {
        guard let summary, !summary.isEmpty else { return nil }
        guard let temp = displayInteger(celsius: celsius, useCelsius: useCelsius) else { return summary }
        return "\(summary), \(temp)"
    }
}
