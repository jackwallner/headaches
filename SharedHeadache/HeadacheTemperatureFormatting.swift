import Foundation

/// Stored weather values are always **Celsius** (Open-Meteo / internal model). UI and CSV add Fahrenheit for US users.
enum HeadacheTemperatureFormatting {
    static func loggedCountDescription(_ count: Int) -> String {
        String(localized: "You have logged \(count) headaches.")
    }

    static func basedOnCountDescription(_ count: Int) -> String {
        String(localized: "Based on \(count) logged headaches.")
    }

    static func deleteEntryCountTitle(_ count: Int) -> String {
        String(localized: "Delete \(count) entries?")
    }

    static func headacheDayCountLabel(_ count: Int) -> String {
        String(localized: "\(count) headache days")
    }

    static func headacheFreeDayCountLabel(_ count: Int) -> String {
        String(localized: "\(count) headache-free days")
    }

    /// Exact conversion for export and averages.
    static func celsiusToFahrenheit(_ celsius: Double) -> Double {
        celsius * 9.0 / 5.0 + 32.0
    }

    /// Whole degrees with a degree sign and unit (default Fahrenheit when `useCelsius` is false).
    static func displayInteger(celsius: Double?, useCelsius: Bool) -> String? {
        guard let c = celsius else { return nil }
        let value = useCelsius ? c : celsiusToFahrenheit(c)
        let unit = useCelsius ? UnitTemperature.celsius : UnitTemperature.fahrenheit
        return localizedMeasurement(value: value, unit: unit, fractionDigits: 0)
    }

    static func localizedMeasurement<UnitType: Dimension>(
        value: Double,
        unit: UnitType,
        fractionDigits: Int
    ) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = .current
        formatter.unitStyle = .short
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: Measurement(value: value, unit: unit))
    }

    /// Weather subtitle, using a full localized phrase and localized weather terms.
    static func weatherSummaryWithTemperature(summary: String?, celsius: Double?, useCelsius: Bool) -> String? {
        guard let summary, !summary.isEmpty else { return nil }
        let displaySummary = localizedStoredText(summary)
        guard let temp = displayInteger(celsius: celsius, useCelsius: useCelsius) else { return displaySummary }
        return String(localized: "\(displaySummary), \(temp)")
    }

    static func localizedStoredText(_ value: String) -> String {
        let weatherCodePrefix = "Weather code "
        if value.hasPrefix(weatherCodePrefix),
           let code = Int(String(value.dropFirst(weatherCodePrefix.count))) {
            return String(localized: "Weather code \(code)")
        }
        switch value {
        case "Clear": String(localized: "Clear")
        case "Mainly clear to overcast": String(localized: "Mainly clear to overcast")
        case "Fog": String(localized: "Fog")
        case "Drizzle": String(localized: "Drizzle")
        case "Freezing drizzle": String(localized: "Freezing drizzle")
        case "Rain": String(localized: "Rain")
        case "Freezing rain": String(localized: "Freezing rain")
        case "Snow": String(localized: "Snow")
        case "Snow grains": String(localized: "Snow grains")
        case "Rain showers": String(localized: "Rain showers")
        case "Snow showers": String(localized: "Snow showers")
        case "Thunderstorm": String(localized: "Thunderstorm")
        case "Thunderstorm with hail": String(localized: "Thunderstorm with hail")
        case "Partly cloudy": String(localized: "Partly cloudy")
        case "Cloudy": String(localized: "Cloudy")
        case "Light rain": String(localized: "Light rain")
        case "Monday": String(localized: "Monday")
        case "Tuesday": String(localized: "Tuesday")
        case "Wednesday": String(localized: "Wednesday")
        case "Thursday": String(localized: "Thursday")
        case "Friday": String(localized: "Friday")
        case "Saturday": String(localized: "Saturday")
        case "Sunday": String(localized: "Sunday")
        case "What time of day do you most often get headaches?": String(localized: "What time of day do you most often get headaches?")
        case "Do you notice headaches after poor or too little sleep?": String(localized: "Do you notice headaches after poor or too little sleep?")
        case "Have you noticed a link between weather changes and your headaches?": String(localized: "Have you noticed a link between weather changes and your headaches?")
        case "Do certain foods or drinks seem to be linked with your headaches?": String(localized: "Do certain foods or drinks seem to be linked with your headaches?")
        case "Are your headaches typically on one side of your head?": String(localized: "Are your headaches typically on one side of your head?")
        case "How severe are your headaches on a typical day?": String(localized: "How severe are your headaches on a typical day?")
        case "Morning": String(localized: "Morning")
        case "Afternoon": String(localized: "Afternoon")
        case "Evening": String(localized: "Evening")
        case "Overnight": String(localized: "Overnight")
        case "No pattern": String(localized: "No pattern")
        case "Yes": String(localized: "Yes")
        case "No": String(localized: "No")
        case "Not sure": String(localized: "Not sure")
        case "Pressure drops": String(localized: "Pressure drops")
        case "Heat": String(localized: "Heat")
        case "Cold": String(localized: "Cold")
        case "Yes, usually right": String(localized: "Yes, usually right")
        case "Yes, usually left": String(localized: "Yes, usually left")
        case "No, both sides": String(localized: "No, both sides")
        case "It varies": String(localized: "It varies")
        case "Slight (can ignore it)": String(localized: "Mild (easy to ignore)")
        case "Medium (noticeable but functional)": String(localized: "Moderate (noticeable but manageable)")
        case "Extreme (hard to function)": String(localized: "Severe (hard to function)")
        case "It varies a lot": String(localized: "It varies a lot")
        case "Open the app to capture Health context.": String(localized: "Open the app to capture Health context.")
        case "Open the app to capture weather.": String(localized: "Open the app to capture weather.")
        case "Health data is not available on this device.": String(localized: "Health data is not available on this device.")
        case "No Health context was available for this event.": String(localized: "No Health context was available for this event.")
        case "Location was turned off during setup. Enable it in Settings › Privacy › Location to add weather and place context.": String(localized: "Location was turned off during setup. Enable it in Settings › Privacy › Location to add weather and place context.")
        case "Location services are turned off for this device.": String(localized: "Location services are turned off for this device.")
        case "Location permission is required for weather and place context.": String(localized: "Location permission is required for weather and place context.")
        case "Could not determine your location.": String(localized: "Could not determine your location.")
        case "No environment context was available for this event.": String(localized: "No environment context was available for this event.")
        case "No details available.": String(localized: "No details available.")
        case "<5h": String(localized: "<5h")
        case "5–6h": String(localized: "5-6h")
        case "6–7h": String(localized: "6-7h")
        case "7–8h": String(localized: "7-8h")
        case "8h+": String(localized: "8h+")
        case "≤−6": String(localized: "≤−6")
        case "−6 to −3": String(localized: "−6 to −3")
        case "−3 to −1": String(localized: "−3 to −1")
        case "−1 to +1": String(localized: "−1 to +1")
        case "+1 to +3": String(localized: "+1 to +3")
        case "+3 to +6": String(localized: "+3 to +6")
        case "≥+6": String(localized: "≥+6")
        case "Good\n0–50": String(localized: "Good\n0-50")
        case "Moderate\n51–100": String(localized: "Moderate\n51-100")
        case "USG\n101–150": String(localized: "Sensitive groups\n101-150")
        case "Unhealthy\n151–200": String(localized: "Unhealthy\n151-200")
        case "Worse\n201+": String(localized: "Worse\n201+")
        case "<30": String(localized: "<30")
        case "30–50": String(localized: "30-50")
        case "50–80": String(localized: "50-80")
        case "<40%": String(localized: "<40%")
        case "40–60%": String(localized: "40-60%")
        case "60–80%": String(localized: "60-80%")
        case "80%+": String(localized: "80%+")
        case "Very cold": String(localized: "Very cold")
        case "Hot": String(localized: "Hot")
        case "Very cold\n<0°C": String(localized: "Very cold\n<0°C")
        case "Cold\n0–10°C": String(localized: "Cold\n0-10°C")
        case "Cool\n10–18°C": String(localized: "Cool\n10-18°C")
        case "Mild\n18–25°C": String(localized: "Mild\n18-25°C")
        case "Warm\n25–32°C": String(localized: "Warm\n25-32°C")
        case "Hot\n32°C+": String(localized: "Hot\n32°C+")
        case "Very cold\n<32°F": String(localized: "Very cold\n<32°F")
        case "Cold\n32–50°F": String(localized: "Cold\n32-50°F")
        case "Cool\n50–65°F": String(localized: "Cool\n50-65°F")
        case "Mild\n65–77°F": String(localized: "Mild\n65-77°F")
        case "Warm\n77–90°F": String(localized: "Warm\n77-90°F")
        case "Hot\n90°F+": String(localized: "Hot\n90°F+")
        case "Dry": String(localized: "Dry")
        case "Light\n<2.5mm": String(localized: "Light\n<2.5mm")
        case "Moderate\n2.5–10mm": String(localized: "Moderate\n2.5-10mm")
        case "Heavy\n10mm+": String(localized: "Heavy\n10mm+")
        case "Calm\n<5": String(localized: "Calm\n<5")
        case "Light\n5–15": String(localized: "Light\n5-15")
        case "Moderate\n15–30": String(localized: "Moderate\n15-30")
        case "Windy\n30+": String(localized: "Windy\n30+")
        case "None": String(localized: "None")
        case "Low\n1–100mg": String(localized: "Low\n1-100mg")
        case "Moderate\n100–200mg": String(localized: "Moderate\n100-200mg")
        case "High\n200–400mg": String(localized: "High\n200-400mg")
        case "Very High\n400mg+": String(localized: "Very High\n400mg+")
        case "Very Low\n<500mL": String(localized: "Very Low\n<500mL")
        case "Low\n500–1000mL": String(localized: "Low\n500-1000mL")
        case "Moderate\n1000–2000mL": String(localized: "Moderate\n1000-2000mL")
        case "Adequate\n2000mL+": String(localized: "Adequate\n2000mL+")
        case "Light\n1–15m": String(localized: "Light\n1-15m")
        case "Moderate\n15–45m": String(localized: "Moderate\n15-45m")
        case "Active\n45m+": String(localized: "Active\n45m+")
        case "No elevation": String(localized: "No elevation")
        case "Elevated": String(localized: "Elevated")
        case "Normal\n<120": String(localized: "Normal\n<120")
        case "Elevated\n120–129": String(localized: "Elevated\n120-129")
        case "High\n130–140": String(localized: "High\n130-140")
        case "Very High\n140+": String(localized: "Very High\n140+")
        case "Normal\n95–100%": String(localized: "Normal\n95-100%")
        case "Low\n<95%": String(localized: "Low\n<95%")
        case "Very Low\n<15m": String(localized: "Very Low\n<15m")
        case "Low\n15–60m": String(localized: "Low\n15-60m")
        case "Moderate\n60–120m": String(localized: "Moderate\n60-120m")
        case "High\n120m+": String(localized: "High\n120m+")
        case "Quiet\n<55dBA": String(localized: "Quiet\n<55dBA")
        case "Moderate\n55–70dBA": String(localized: "Moderate\n55-70dBA")
        case "Loud\n70–80dBA": String(localized: "Loud\n70-80dBA")
        case "Very Loud\n80dBA+": String(localized: "Very Loud\n80dBA+")
        case "0–2h": String(localized: "0-2h")
        case "2–4h": String(localized: "2-4h")
        case "4–8h": String(localized: "4-8h")
        case "8–12h": String(localized: "8-12h")
        case "12h+": String(localized: "12h+")
        case "Follicular\nDays 0–13": String(localized: "Follicular\nDays 0-13")
        case "Luteal\nDays 14–28": String(localized: "Luteal\nDays 14-28")
        case "Extended\n28+ days": String(localized: "Extended\n28+ days")
        case "Neither": String(localized: "Neither")
        case "Both": String(localized: "Both")
        case "Falling": String(localized: "Falling")
        case "Steady": String(localized: "Steady")
        case "Rising": String(localized: "Rising")
        case "Clean\n<75": String(localized: "Clean\n<75")
        case "Elevated\n75+": String(localized: "Elevated\n75+")
        case "Grass": String(localized: "Grass")
        case "Birch": String(localized: "Birch")
        case "Alder": String(localized: "Alder")
        case "Mugwort": String(localized: "Mugwort")
        case "Olive": String(localized: "Olive")
        case "Ragweed": String(localized: "Ragweed")
        case "pollen": String(localized: "pollen")
        case "various pollen types": String(localized: "various pollen types")
        case "a weekday": String(localized: "a weekday")
        case "stationary": String(localized: "stationary")
        case "walking": String(localized: "walking")
        case "running": String(localized: "running")
        case "in a vehicle": String(localized: "in a vehicle")
        case "cycling": String(localized: "cycling")
        case "unknown": String(localized: "unknown")
        case "day": String(localized: "day")
        case "week": String(localized: "week")
        case "month": String(localized: "month")
        case "year": String(localized: "year")
        case "mild": String(localized: "mild")
        case "moderate": String(localized: "moderate")
        case "severe": String(localized: "severe")
        case "overnight": String(localized: "overnight")
        case "morning": String(localized: "morning")
        case "afternoon": String(localized: "afternoon")
        case "evening": String(localized: "evening")
        case "falling": String(localized: "falling")
        case "rising": String(localized: "rising")
        case "steady": String(localized: "steady")
        default: value
        }
    }
}
