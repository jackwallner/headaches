import Foundation
import SwiftUI

/// User-tunable thresholds for Proactive Alerts. Persisted via the shared app-group `UserDefaults`
/// so the background task can read them without instantiating SwiftData.
@MainActor
final class ProAlertPreferences: ObservableObject {
    static let shared = ProAlertPreferences()

    @AppStorage(HeadacheStorageKey.proAlertsEnabled.rawValue, store: HeadacheAppGroup.userDefaults)
    var alertsEnabled: Bool = false

    @AppStorage(HeadacheStorageKey.proAlertPressureDropThreshold.rawValue, store: HeadacheAppGroup.userDefaults)
    var pressureDropThresholdHpa: Double = 4.0

    @AppStorage(HeadacheStorageKey.proAlertAirQualityEnabled.rawValue, store: HeadacheAppGroup.userDefaults)
    var airQualityEnabled: Bool = true

    @AppStorage(HeadacheStorageKey.proAlertAirQualityThreshold.rawValue, store: HeadacheAppGroup.userDefaults)
    var airQualityThreshold: Int = 100

    @AppStorage(HeadacheStorageKey.proAlertQuietHoursEnabled.rawValue, store: HeadacheAppGroup.userDefaults)
    var quietHoursEnabled: Bool = true

    @AppStorage(HeadacheStorageKey.proAlertQuietStartHour.rawValue, store: HeadacheAppGroup.userDefaults)
    var quietHoursStart: Int = 22

    @AppStorage(HeadacheStorageKey.proAlertQuietEndHour.rawValue, store: HeadacheAppGroup.userDefaults)
    var quietHoursEnd: Int = 7
}

/// Plain-value snapshot of preferences. Safe to read from any thread / background task.
struct ProAlertPreferenceValues: Sendable {
    var alertsEnabled: Bool
    var pressureDropThresholdHpa: Double
    var airQualityEnabled: Bool
    var airQualityThreshold: Int
    var quietHoursEnabled: Bool
    var quietHoursStart: Int
    var quietHoursEnd: Int

    static func current() -> ProAlertPreferenceValues {
        let defaults = HeadacheAppGroup.userDefaults
        let pressureRaw = defaults.object(forKey: HeadacheStorageKey.proAlertPressureDropThreshold.rawValue) as? Double
        let aqEnabled = defaults.object(forKey: HeadacheStorageKey.proAlertAirQualityEnabled.rawValue) as? Bool ?? true
        let aqThreshold = defaults.object(forKey: HeadacheStorageKey.proAlertAirQualityThreshold.rawValue) as? Int ?? 100
        let quietEnabled = defaults.object(forKey: HeadacheStorageKey.proAlertQuietHoursEnabled.rawValue) as? Bool ?? true
        let quietStart = defaults.object(forKey: HeadacheStorageKey.proAlertQuietStartHour.rawValue) as? Int ?? 22
        let quietEnd = defaults.object(forKey: HeadacheStorageKey.proAlertQuietEndHour.rawValue) as? Int ?? 7
        return ProAlertPreferenceValues(
            alertsEnabled: defaults.bool(forKey: HeadacheStorageKey.proAlertsEnabled.rawValue),
            pressureDropThresholdHpa: pressureRaw ?? 4.0,
            airQualityEnabled: aqEnabled,
            airQualityThreshold: aqThreshold,
            quietHoursEnabled: quietEnabled,
            quietHoursStart: quietStart,
            quietHoursEnd: quietEnd
        )
    }

    /// Returns true if `date` falls inside the user's quiet window. Wraps midnight when end < start.
    func isQuietHour(at date: Date, calendar: Calendar = .current) -> Bool {
        guard quietHoursEnabled else { return false }
        let hour = calendar.component(.hour, from: date)
        if quietHoursStart == quietHoursEnd { return false }
        if quietHoursStart < quietHoursEnd {
            return hour >= quietHoursStart && hour < quietHoursEnd
        } else {
            return hour >= quietHoursStart || hour < quietHoursEnd
        }
    }
}
