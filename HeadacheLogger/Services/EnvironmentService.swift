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
        // C13: same main-thread hazard as in captureSnapshot — keep it off main.
        let servicesEnabled: Bool = await Task.detached(priority: .userInitiated) {
            CLLocationManager.locationServicesEnabled()
        }.value
        guard servicesEnabled else { return }
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

        // C13: `CLLocationManager.locationServicesEnabled()` is synchronous and Apple explicitly
        // warns it must not run on the main thread (main-thread checker flags it in logs).
        // Move it to a background executor so the capture Task doesn't stall the UI on cold launch.
        let servicesEnabled: Bool = await Task.detached(priority: .userInitiated) {
            CLLocationManager.locationServicesEnabled()
        }.value
        guard servicesEnabled else {
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

            async let weatherTask = OpenMeteoClient.fetchWeatherNearestTo(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                eventDate: date
            )
            async let airQualityTask = OpenMeteoClient.fetchAirQuality(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                eventDate: date
            )

            let openMeteo = try await weatherTask
            let airQuality = await airQualityTask

            let snapshot = makeSnapshot(placemark: placemark, openMeteo: openMeteo, airQuality: airQuality)

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

    private func makeSnapshot(placemark: CLPlacemark?, openMeteo: OpenMeteoClient.CurrentWeather, airQuality: OpenMeteoClient.AirQualityData?) -> EnvironmentSnapshot {
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
            usAQI: airQuality?.usAQI,
            europeanAQI: airQuality?.europeanAQI,
            pm25: airQuality?.pm25,
            pm10: airQuality?.pm10,
            ozone: airQuality?.ozone,
            nitrogenDioxide: airQuality?.nitrogenDioxide,
            sulphurDioxide: airQuality?.sulphurDioxide,
            carbonMonoxide: airQuality?.carbonMonoxide,
            alderPollen: airQuality?.alderPollen,
            birchPollen: airQuality?.birchPollen,
            grassPollen: airQuality?.grassPollen,
            mugwortPollen: airQuality?.mugwortPollen,
            olivePollen: airQuality?.olivePollen,
            ragweedPollen: airQuality?.ragweedPollen
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
    /// C15: 8s ceiling keeps the capture flow snappy. Default URLSession timeout is 60s, which
    /// leaves the "Saving and collecting context…" banner spinning for a minute on network failure.
    /// At 8s we fall back to the archive API or current-conditions branch much faster.
    static let requestTimeout: TimeInterval = 8

    static func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        return request
    }

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
            let pressureMsl: Double?
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
                case pressureMsl = "pressure_msl"
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
                // C7: `pressure_msl` (mean sea level) so users at altitude see meteorologically
                // comparable values (Denver's station pressure ~830 hPa would otherwise confuse).
                // Matches how migraine-pressure studies report values.
                value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,uv_index"
            ),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url))
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
            surfacePressureHpa: c.pressureMsl,
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
            let pressureMsl: [Double?]
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
                case pressureMsl = "pressure_msl"
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
        // C8: request the previous day alongside the event day so the 3-hour-prior index for
        // pressure trend is always populated (otherwise any event before ~03:00 local had
        // `priorIdx = idx - 3 < 0`, collapsing trend to `.unavailable`).
        let priorDay: String = {
            let cal = Calendar.current
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = cal.timeZone
            df.dateFormat = "yyyy-MM-dd"
            let prior = cal.date(byAdding: .day, value: -1, to: eventDate)
                ?? eventDate.addingTimeInterval(-86_400)
            return df.string(from: prior)
        }()

        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: priorDay),
            URLQueryItem(name: "end_date", value: day),
            URLQueryItem(
                name: "hourly",
                // C7: use `pressure_msl` to match current-weather query; comparable across altitudes.
                value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,uv_index"
            ),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
        ]
        guard let url = components.url else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(for: makeRequest(url: url)),
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
            guard let current = at(h.pressureMsl, idx).flatMap({ $0 }),
                  let prior = at(h.pressureMsl, priorIdx).flatMap({ $0 }) else {
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
            surfacePressureHpa: at(h.pressureMsl, idx).flatMap { $0 },
            pressureTrend: trend,
            precipitationMm: at(h.precipitation, idx).flatMap { $0 },
            windSpeedKph: at(h.windSpeed10m, idx).flatMap { $0 },
            windDirectionDegrees: at(h.windDirection10m, idx).flatMap { $0 },
            cloudCoverPercent: at(h.cloudCover, idx).flatMap { $0 },
            uvIndex: at(h.uvIndex, idx).flatMap { $0 }
        )
    }

    // MARK: - Air Quality

    struct AirQualityData {
        let usAQI: Double?
        let europeanAQI: Double?
        let pm25: Double?
        let pm10: Double?
        let ozone: Double?
        let nitrogenDioxide: Double?
        let sulphurDioxide: Double?
        let carbonMonoxide: Double?
        let alderPollen: Double?
        let birchPollen: Double?
        let grassPollen: Double?
        let mugwortPollen: Double?
        let olivePollen: Double?
        let ragweedPollen: Double?
    }

    private struct AirQualityHourlyPayload: Decodable {
        let timezone: String
        let hourly: Hourly
        struct Hourly: Decodable {
            let time: [String]
            let usAqi: [Double?]
            let europeanAqi: [Double?]
            let pm25: [Double?]
            let pm10: [Double?]
            let ozone: [Double?]
            let nitrogenDioxide: [Double?]
            let sulphurDioxide: [Double?]
            let carbonMonoxide: [Double?]
            let alderPollen: [Double?]?
            let birchPollen: [Double?]?
            let grassPollen: [Double?]?
            let mugwortPollen: [Double?]?
            let olivePollen: [Double?]?
            let ragweedPollen: [Double?]?

            enum CodingKeys: String, CodingKey {
                case time
                case usAqi = "us_aqi"
                case europeanAqi = "european_aqi"
                case pm25 = "pm2_5"
                case pm10
                case ozone
                case nitrogenDioxide = "nitrogen_dioxide"
                case sulphurDioxide = "sulphur_dioxide"
                case carbonMonoxide = "carbon_monoxide"
                case alderPollen = "alder_pollen"
                case birchPollen = "birch_pollen"
                case grassPollen = "grass_pollen"
                case mugwortPollen = "mugwort_pollen"
                case olivePollen = "olive_pollen"
                case ragweedPollen = "ragweed_pollen"
            }
        }
    }

    static func fetchAirQuality(latitude: Double, longitude: Double, eventDate: Date) async -> AirQualityData? {
        let cal = Calendar.current
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = cal.timeZone
        df.dateFormat = "yyyy-MM-dd"
        let day = df.string(from: eventDate)

        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: day),
            URLQueryItem(name: "end_date", value: day),
            URLQueryItem(
                name: "hourly",
                value: "us_aqi,european_aqi,pm2_5,pm10,ozone,nitrogen_dioxide,sulphur_dioxide,carbon_monoxide,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen"
            ),
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url))
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(AirQualityHourlyPayload.self, from: data)
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

            func at(_ arr: [Double?]?, _ i: Int) -> Double? {
                guard let arr, i >= 0, i < arr.count else { return nil }
                return arr[i]
            }

            return AirQualityData(
                usAQI: at(h.usAqi, idx),
                europeanAQI: at(h.europeanAqi, idx),
                pm25: at(h.pm25, idx),
                pm10: at(h.pm10, idx),
                ozone: at(h.ozone, idx),
                nitrogenDioxide: at(h.nitrogenDioxide, idx),
                sulphurDioxide: at(h.sulphurDioxide, idx),
                carbonMonoxide: at(h.carbonMonoxide, idx),
                alderPollen: at(h.alderPollen, idx),
                birchPollen: at(h.birchPollen, idx),
                grassPollen: at(h.grassPollen, idx),
                mugwortPollen: at(h.mugwortPollen, idx),
                olivePollen: at(h.olivePollen, idx),
                ragweedPollen: at(h.ragweedPollen, idx)
            )
        } catch {
            print("OpenMeteoClient.fetchAirQuality failed | \(error)")
            return nil
        }
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
    private var timeoutWorkItem: DispatchWorkItem?
    /// Hard cap so a dropped auth prompt or flaky Core Location never leaks the instance (C14).
    private let timeoutSeconds: TimeInterval = 15

    init(completion: @escaping (CLLocation?) -> Void) {
        self.completion = completion
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        selfRetain = self
        // C14: arm a timeout so we don't rely solely on a delegate callback arriving.
        let workItem = DispatchWorkItem { [weak self] in
            self?.finish(nil)
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: workItem)

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
        // C14: guard against double-finish from (a) delegate callback and (b) timeout racing.
        guard selfRetain != nil else { return }
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
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
