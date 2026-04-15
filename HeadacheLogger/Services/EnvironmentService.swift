import CoreLocation
import Foundation

/// Location + weather enrichment using Core Location and Open-Meteo (no WeatherKit entitlement required).
@MainActor
final class EnvironmentService: NSObject, CLLocationManagerDelegate {
    static let shared = EnvironmentService()

    private let manager = CLLocationManager()
    private var locationOnboardingContinuation: CheckedContinuation<Void, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Call from onboarding so the first capture does not show the location sheet mid-query.
    func prepareLocationAuthorizationDuringOnboarding() async {
        guard CLLocationManager.locationServicesEnabled() else { return }
        guard !HeadacheOnboardingStore.declinedLocation else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                locationOnboardingContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        default:
            break
        }
    }

    func markLocationSkippedInOnboarding() {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.finishLocationOnboardingWaitIfReady()
        }
    }

    private func finishLocationOnboardingWaitIfReady() {
        guard manager.authorizationStatus != .notDetermined else { return }
        locationOnboardingContinuation?.resume()
        locationOnboardingContinuation = nil
    }

    func locationAuthorizationSummary() -> String {
        guard CLLocationManager.locationServicesEnabled() else { return "Off" }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "While Using / Always"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Yet Asked"
        @unknown default:
            return "Unknown"
        }
    }

    func captureSnapshot(at date: Date) async -> EnvironmentCaptureResult {
        if HeadacheOnboardingStore.declinedLocation {
            return EnvironmentCaptureResult(
                status: .unavailable,
                message: "Location was turned off during setup. Enable it in Settings › Privacy › Location to add weather and place context.",
                snapshot: nil
            )
        }

        guard CLLocationManager.locationServicesEnabled() else {
            return EnvironmentCaptureResult(
                status: .unavailable,
                message: "Location services are turned off for this device.",
                snapshot: nil
            )
        }

        switch manager.authorizationStatus {
        case .denied, .restricted:
            return EnvironmentCaptureResult(
                status: .unavailable,
                message: "Location permission is required for weather and place context.",
                snapshot: nil
            )
        default:
            break
        }

        guard let location = await requestLocation() else {
            return EnvironmentCaptureResult(
                status: .failed,
                message: "Could not determine your location.",
                snapshot: nil
            )
        }

        do {
            let placemarks = try await reverseGeocode(location)
            let placemark = placemarks.first

            let openMeteo = try await OpenMeteoClient.fetchWeatherNearestTo(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                eventDate: date
            )

            let snapshot = makeSnapshot(placemark: placemark, openMeteo: openMeteo)

            let meaningful =
                snapshot.locality != nil
                || snapshot.weatherSummary != nil
                || snapshot.temperatureC != nil
                || snapshot.pressureHpa != nil

            let status: CaptureSourceStatus = meaningful ? .captured : .unavailable
            let message: String? = meaningful ? nil : "No environment context was available for this event."
            return EnvironmentCaptureResult(status: status, message: message, snapshot: snapshot)
        } catch {
            consoleError("EnvironmentService.captureSnapshot", error: error, trace: [
                "lat": String(format: "%.4f", location.coordinate.latitude),
                "lon": String(format: "%.4f", location.coordinate.longitude),
            ])
            return EnvironmentCaptureResult(
                status: .failed,
                message: error.localizedDescription,
                snapshot: nil
            )
        }
    }

    private func makeSnapshot(placemark: CLPlacemark?, openMeteo: OpenMeteoClient.CurrentWeather) -> EnvironmentSnapshot {
        let locality = placemark?.locality
        let region = placemark?.administrativeArea

        return EnvironmentSnapshot(
            locality: locality,
            region: region,
            weatherSummary: openMeteo.conditionSummary,
            weatherCode: openMeteo.weatherCode,
            temperatureC: openMeteo.temperatureC,
            apparentTemperatureC: openMeteo.apparentTemperatureC,
            humidityPercent: openMeteo.relativeHumidityPercent,
            pressureHpa: openMeteo.surfacePressureHpa,
            pressureTrend: openMeteo.pressureTrend,
            precipitationMm: openMeteo.precipitationMm,
            windSpeedKph: openMeteo.windSpeedKph,
            windDirectionDegrees: openMeteo.windDirectionDegrees,
            cloudCoverPercent: openMeteo.cloudCoverPercent,
            uvIndex: openMeteo.uvIndex,
            usAQI: nil,
            europeanAQI: nil,
            pm25: nil,
            pm10: nil,
            ozone: nil,
            nitrogenDioxide: nil,
            sulphurDioxide: nil,
            carbonMonoxide: nil,
            alderPollen: nil,
            birchPollen: nil,
            grassPollen: nil,
            mugwortPollen: nil,
            olivePollen: nil,
            ragweedPollen: nil
        )
    }

    private func requestLocation() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            let fetcher = OneShotLocationManager { location in
                continuation.resume(returning: location)
            }
            fetcher.start()
        }
    }

    private func reverseGeocode(_ location: CLLocation) async throws -> [CLPlacemark] {
        try await withCheckedThrowingContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: placemarks ?? [])
            }
        }
    }

    private func consoleError(_ message: String, error: Error, trace: [String: String]) {
        var parts = [message, String(describing: error)]
        if !trace.isEmpty {
            parts.append(trace.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        }
        print(parts.joined(separator: " | "))
    }
}

// MARK: - Open-Meteo

private enum OpenMeteoClient {
    struct CurrentWeather {
        let conditionSummary: String?
        let weatherCode: Int?
        let temperatureC: Double?
        let apparentTemperatureC: Double?
        let relativeHumidityPercent: Double?
        let surfacePressureHpa: Double?
        let pressureTrend: PressureTrend
        let precipitationMm: Double?
        let windSpeedKph: Double?
        let windDirectionDegrees: Double?
        let cloudCoverPercent: Double?
        let uvIndex: Double?
    }

    private struct Response: Decodable {
        let current: Current

        struct Current: Decodable {
            let time: String
            let temperature2m: Double?
            let apparentTemperature: Double?
            let relativeHumidity2m: Double?
            let precipitation: Double?
            let weatherCode: Int?
            let cloudCover: Double?
            let surfacePressure: Double?
            let windSpeed10m: Double?
            let windDirection10m: Double?
            let uvIndex: Double?

            enum CodingKeys: String, CodingKey {
                case time
                case temperature2m = "temperature_2m"
                case apparentTemperature = "apparent_temperature"
                case relativeHumidity2m = "relative_humidity_2m"
                case precipitation
                case weatherCode = "weather_code"
                case cloudCover = "cloud_cover"
                case surfacePressure = "surface_pressure"
                case windSpeed10m = "wind_speed_10m"
                case windDirection10m = "wind_direction_10m"
                case uvIndex = "uv_index"
            }
        }
    }

    static func fetchCurrent(latitude: Double, longitude: Double) async throws -> CurrentWeather {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,cloud_cover,surface_pressure,wind_speed_10m,wind_direction_10m,uv_index"
            ),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let c = decoded.current

        return CurrentWeather(
            conditionSummary: c.weatherCode.map { wmoWeatherSummary(code: $0) },
            weatherCode: c.weatherCode,
            temperatureC: c.temperature2m,
            apparentTemperatureC: c.apparentTemperature,
            relativeHumidityPercent: c.relativeHumidity2m,
            surfacePressureHpa: c.surfacePressure,
            pressureTrend: .unavailable,
            precipitationMm: c.precipitation,
            windSpeedKph: c.windSpeed10m,
            windDirectionDegrees: c.windDirection10m,
            cloudCoverPercent: c.cloudCover,
            uvIndex: c.uvIndex
        )
    }

    /// Weather at **event time** (hour slot nearest to `eventDate` on that calendar day), not “now”.
    /// Uses forecast API first, then archive for older days — then falls back to current conditions.
    static func fetchWeatherNearestTo(latitude: Double, longitude: Double, eventDate: Date) async throws -> CurrentWeather {
        let cal = Calendar.current
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = cal.timeZone
        df.dateFormat = "yyyy-MM-dd"
        let day = df.string(from: eventDate)

        if let w = await fetchHourlySlot(
            baseURL: "https://api.open-meteo.com/v1/forecast",
            latitude: latitude,
            longitude: longitude,
            day: day,
            eventDate: eventDate
        ) {
            return w
        }
        if let w = await fetchHourlySlot(
            baseURL: "https://archive-api.open-meteo.com/v1/archive",
            latitude: latitude,
            longitude: longitude,
            day: day,
            eventDate: eventDate
        ) {
            return w
        }
        return try await fetchCurrent(latitude: latitude, longitude: longitude)
    }

    private struct HourlyPayload: Decodable {
        let timezone: String
        let hourly: Hourly
        struct Hourly: Decodable {
            let time: [String]
            let temperature2m: [Double?]
            let apparentTemperature: [Double?]
            let relativeHumidity2m: [Double?]
            let precipitation: [Double?]
            /// Open-Meteo may encode codes as integers or floats in JSON arrays.
            let weatherCode: [Double?]
            let cloudCover: [Double?]
            let surfacePressure: [Double?]
            let windSpeed10m: [Double?]
            let windDirection10m: [Double?]
            let uvIndex: [Double?]

            enum CodingKeys: String, CodingKey {
                case time
                case temperature2m = "temperature_2m"
                case apparentTemperature = "apparent_temperature"
                case relativeHumidity2m = "relative_humidity_2m"
                case precipitation
                case weatherCode = "weather_code"
                case cloudCover = "cloud_cover"
                case surfacePressure = "surface_pressure"
                case windSpeed10m = "wind_speed_10m"
                case windDirection10m = "wind_direction_10m"
                case uvIndex = "uv_index"
            }
        }
    }

    private static func fetchHourlySlot(
        baseURL: String,
        latitude: Double,
        longitude: Double,
        day: String,
        eventDate: Date
    ) async -> CurrentWeather? {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: day),
            URLQueryItem(name: "end_date", value: day),
            URLQueryItem(
                name: "hourly",
                value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,cloud_cover,surface_pressure,wind_speed_10m,wind_direction_10m,uv_index"
            ),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
        ]
        guard let url = components.url else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode) else {
            return nil
        }
        guard let decoded = try? JSONDecoder().decode(HourlyPayload.self, from: data) else {
            return nil
        }
        let h = decoded.hourly
        guard !h.time.isEmpty else { return nil }

        guard let tz = TimeZone(identifier: decoded.timezone) else { return nil }

        var bestIdx: Int?
        var bestDelta = TimeInterval.greatestFiniteMagnitude
        for (i, s) in h.time.enumerated() {
            guard let t = OpenMeteoTimeParsing.hourDate(from: s, timeZone: tz) else { continue }
            let d = abs(t.timeIntervalSince(eventDate))
            if d < bestDelta {
                bestDelta = d
                bestIdx = i
            }
        }
        guard let idx = bestIdx else { return nil }

        func at<T>(_ arr: [T?], _ i: Int) -> T? {
            guard i >= 0, i < arr.count else { return nil }
            return arr[i]
        }

        let wc: Int? = at(h.weatherCode, idx).flatMap { $0 }.map { Int(round($0)) }

        let trend: PressureTrend = {
            let priorIdx = idx - 3
            guard let current = at(h.surfacePressure, idx).flatMap({ $0 }),
                  let prior = at(h.surfacePressure, priorIdx).flatMap({ $0 }) else {
                return .unavailable
            }
            let delta = current - prior
            if delta > 1.0 { return .rising }
            if delta < -1.0 { return .falling }
            return .steady
        }()

        return CurrentWeather(
            conditionSummary: wc.map { wmoWeatherSummary(code: $0) },
            weatherCode: wc,
            temperatureC: at(h.temperature2m, idx).flatMap { $0 },
            apparentTemperatureC: at(h.apparentTemperature, idx).flatMap { $0 },
            relativeHumidityPercent: at(h.relativeHumidity2m, idx).flatMap { $0 },
            surfacePressureHpa: at(h.surfacePressure, idx).flatMap { $0 },
            pressureTrend: trend,
            precipitationMm: at(h.precipitation, idx).flatMap { $0 },
            windSpeedKph: at(h.windSpeed10m, idx).flatMap { $0 },
            windDirectionDegrees: at(h.windDirection10m, idx).flatMap { $0 },
            cloudCoverPercent: at(h.cloudCover, idx).flatMap { $0 },
            uvIndex: at(h.uvIndex, idx).flatMap { $0 }
        )
    }

    /// Short WMO code summary (Open-Meteo uses WMO Weather interpretation codes).
    private static func wmoWeatherSummary(code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2, 3: return "Mainly clear to overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75: return "Snow"
        case 77: return "Snow grains"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with hail"
        default: return "Weather code \(code)"
        }
    }
}

// MARK: - One-shot location

private final class OneShotLocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let completion: (CLLocation?) -> Void
    private var selfRetain: OneShotLocationManager?

    init(completion: @escaping (CLLocation?) -> Void) {
        self.completion = completion
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        selfRetain = self
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            finish(nil)
        }
    }

    private func finish(_ location: CLLocation?) {
        completion(location)
        selfRetain = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("OneShotLocationManager.didFailWithError | \(error)")
        finish(nil)
    }
}
