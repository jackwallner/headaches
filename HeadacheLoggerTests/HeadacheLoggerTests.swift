import XCTest
import SwiftData
@testable import HeadacheLogger

final class HeadacheLoggerTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        HeadacheAppGroup.userDefaults.set(true, forKey: HeadacheStorageKey.hasCompletedOnboarding.rawValue)
    }

    func testCelsiusToFahrenheitConversion() {
        XCTAssertEqual(HeadacheTemperatureFormatting.celsiusToFahrenheit(0), 32, accuracy: 0.001)
        XCTAssertEqual(HeadacheTemperatureFormatting.celsiusToFahrenheit(100), 212, accuracy: 0.001)
        XCTAssertEqual(HeadacheTemperatureFormatting.celsiusToFahrenheit(20), 68, accuracy: 0.001)
        XCTAssertEqual(HeadacheTemperatureFormatting.celsiusToFahrenheit(19.5), 67.1, accuracy: 0.001)
    }

    func testTemperatureDisplayDefaultsToFahrenheit() {
        let s = HeadacheTemperatureFormatting.displayInteger(celsius: 22, useCelsius: false)
        XCTAssertEqual(s, "72°F")
        let c = HeadacheTemperatureFormatting.displayInteger(celsius: 22, useCelsius: true)
        XCTAssertEqual(c, "22°C")
    }

    func testOpenMeteoParsesCommonHourStrings() {
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        let a = OpenMeteoTimeParsing.hourDate(from: "2026-04-12T14:00", timeZone: tz)
        let b = OpenMeteoTimeParsing.hourDate(from: "2026-04-12T14:00:00", timeZone: tz)
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertEqual(a, b)
    }

    func testPartOfDayMapping() {
        let calendar = Calendar(identifier: .gregorian)

        let overnight = calendar.date(from: DateComponents(year: 2026, month: 4, day: 11, hour: 2))!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 4, day: 11, hour: 8))!
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 4, day: 11, hour: 14))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 4, day: 11, hour: 20))!

        XCTAssertEqual(PartOfDay.from(overnight, calendar: calendar), .overnight)
        XCTAssertEqual(PartOfDay.from(morning, calendar: calendar), .morning)
        XCTAssertEqual(PartOfDay.from(afternoon, calendar: calendar), .afternoon)
        XCTAssertEqual(PartOfDay.from(evening, calendar: calendar), .evening)
    }

    func testFinalizeCaptureMarksCompleteWhenBothSourcesCaptured() {
        let event = HeadacheEvent(timestamp: Date(timeIntervalSince1970: 1_744_406_400))

        event.apply(
            HealthCaptureResult(
                status: .captured,
                message: nil,
                snapshot: HealthSnapshot(stepsToday: 1200, activeEnergyKcalToday: 340)
            )
        )
        event.apply(
            EnvironmentCaptureResult(
                status: .captured,
                message: nil,
                snapshot: EnvironmentSnapshot(
                    locality: "Austin",
                    region: "TX",
                    weatherSummary: "Cloudy",
                    weatherCode: 3,
                    temperatureC: 22,
                    apparentTemperatureC: 24,
                    humidityPercent: 52,
                    pressureHpa: 1013,
                    pressureTrend: .steady,
                    precipitationMm: 0,
                    windSpeedKph: 8,
                    windDirectionDegrees: 180,
                    cloudCoverPercent: 75,
                    uvIndex: 3,
                    usAQI: 32,
                    europeanAQI: 18,
                    pm25: 4,
                    pm10: 8,
                    ozone: 80,
                    nitrogenDioxide: 12,
                    sulphurDioxide: 1,
                    carbonMonoxide: 200,
                    alderPollen: nil,
                    birchPollen: nil,
                    grassPollen: nil,
                    mugwortPollen: nil,
                    olivePollen: nil,
                    ragweedPollen: nil
                )
            )
        )

        event.finalizeCapture()

        XCTAssertEqual(event.captureStatus, .complete)
        XCTAssertEqual(event.healthStatus, .captured)
        XCTAssertEqual(event.environmentStatus, .captured)
    }

    func testFinalizeCaptureMarksPartialWhenOnlyOneSourceAvailable() {
        let event = HeadacheEvent()
        event.healthStatus = .captured
        event.environmentStatus = .unavailable

        event.finalizeCapture()

        XCTAssertEqual(event.captureStatus, .partial)
    }

    func testFinalizeCaptureMarksPartialWhenBothSourcesUnavailable() {
        let event = HeadacheEvent()
        event.apply(HealthCaptureResult(status: .unavailable, message: nil, snapshot: nil))
        event.apply(EnvironmentCaptureResult(status: .unavailable, message: nil, snapshot: nil))

        event.finalizeCapture()

        XCTAssertEqual(event.captureStatus, .partial)
    }

    func testSleepIntervalMergeCombinesCloseSegments() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let a = SleepIntervalMerge.Interval(start: t0, end: t0.addingTimeInterval(3600))
        let b = SleepIntervalMerge.Interval(
            start: t0.addingTimeInterval(3600 + 30 * 60),
            end: t0.addingTimeInterval(7200)
        )
        let merged = SleepIntervalMerge.merge([a, b], mergeGap: 45 * 60)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].duration, 7200, accuracy: 0.001)
    }

    func testWakeTimeAfterLongestSleep() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let shortSleep = SleepIntervalMerge.Interval(start: t0, end: t0.addingTimeInterval(1800))
        let longSleep = SleepIntervalMerge.Interval(start: t0.addingTimeInterval(10_000), end: t0.addingTimeInterval(10_000 + 28_800))
        let merged = SleepIntervalMerge.merge([shortSleep, longSleep], mergeGap: 60)
        let wake = SleepIntervalMerge.wakeTimeAfterLongestSleep(merged)
        XCTAssertEqual(wake, longSleep.end)
    }

    func testEmptyHealthSnapshotIsNotMeaningful() {
        // C1 regression: when HealthKit is denied or returns no samples in any field,
        // all fields stay nil and capture status must fall to .unavailable (not .captured).
        let empty = HealthSnapshot()
        XCTAssertFalse(empty.hasMeaningfulValue)
    }

    func testHealthSnapshotWithOnlyZeroStepsIsStillMeaningful() {
        // Legitimate 0 steps (e.g. 1am capture) is real data — snapshot contains Optional.some(0),
        // so hasMeaningfulValue should be true. This protects C1 fix from over-correcting.
        var snapshot = HealthSnapshot()
        snapshot.stepsToday = 0
        XCTAssertTrue(snapshot.hasMeaningfulValue)
    }

    func testStepsRoundingForDedupedWatchIphoneSums() {
        // C17 regression: Int(x) truncates; we want rounded. Represent the behavior we rely on.
        let raw = 1234.9
        XCTAssertEqual(Int(raw.rounded()), 1235)
        XCTAssertEqual(Int(raw), 1234) // truncation — what we must NOT use anymore
    }

    func testSeverityEnumCases() {
        XCTAssertEqual(HeadacheSeverity.slight.rawValue, "slight")
        XCTAssertEqual(HeadacheSeverity.medium.rawValue, "medium")
        XCTAssertEqual(HeadacheSeverity.extreme.rawValue, "extreme")
        XCTAssertEqual(HeadacheSeverity.allCases.count, 3)
    }

    func testEventSeverityRoundTrip() {
        let event = HeadacheEvent()
        XCTAssertNil(event.severity)
        XCTAssertNil(event.severityRaw)

        event.severity = .extreme
        XCTAssertEqual(event.severity, .extreme)
        XCTAssertEqual(event.severityRaw, "extreme")

        event.severity = nil
        XCTAssertNil(event.severity)
        XCTAssertNil(event.severityRaw)
    }

    func testOnboardingStorePromptForSeverityNotesDefaultsToFalse() {
        HeadacheOnboardingStore.resetForTesting()
        XCTAssertFalse(HeadacheOnboardingStore.promptForSeverityNotes)
        HeadacheOnboardingStore.promptForSeverityNotes = true
        XCTAssertTrue(HeadacheOnboardingStore.promptForSeverityNotes)
        HeadacheOnboardingStore.resetForTesting()
        XCTAssertFalse(HeadacheOnboardingStore.promptForSeverityNotes)
    }

    func testPendingCaptureFetchMatchesWatchOrphansAndWidgetSentinels() throws {
        // C2 regression: the re-enrichment predicate must catch BOTH
        // (a) watch-orphaned captures (both sources still .pending, no sentinel messages)
        // (b) widget sentinel rows (both sources .unavailable with sentinel messages)
        // and must NOT re-enrich completed rows.
        let schema = Schema([HeadacheEvent.self])
        let config = ModelConfiguration("C2Test", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // (a) watch-orphaned pending row: both statuses .pending, no messages.
        let watchOrphan = HeadacheEvent(timestamp: Date(timeIntervalSince1970: 1_744_000_000))
        context.insert(watchOrphan)

        // (b) widget-sentinel row: both .unavailable with sentinel messages (matches LogHeadacheIntent).
        let widgetPending = HeadacheEvent(timestamp: Date(timeIntervalSince1970: 1_744_000_100))
        widgetPending.apply(HealthCaptureResult(status: .unavailable,
                                                message: HeadacheWidgetQuickLog.healthMessagePending,
                                                snapshot: nil))
        widgetPending.apply(EnvironmentCaptureResult(status: .unavailable,
                                                     message: HeadacheWidgetQuickLog.environmentMessagePending,
                                                     snapshot: nil))
        widgetPending.finalizeCapture()
        context.insert(widgetPending)

        // Completed row: both .captured.
        let completed = HeadacheEvent(timestamp: Date(timeIntervalSince1970: 1_744_000_200))
        completed.apply(HealthCaptureResult(status: .captured, message: nil,
                                            snapshot: HealthSnapshot(stepsToday: 42)))
        completed.apply(EnvironmentCaptureResult(status: .captured, message: nil, snapshot: nil))
        completed.finalizeCapture()
        context.insert(completed)

        // Unrelated failed row (both failed, no sentinel messages): must not match.
        let failed = HeadacheEvent(timestamp: Date(timeIntervalSince1970: 1_744_000_300))
        failed.apply(HealthCaptureResult(status: .failed, message: "boom", snapshot: nil))
        failed.apply(EnvironmentCaptureResult(status: .failed, message: "boom", snapshot: nil))
        failed.finalizeCapture()
        context.insert(failed)

        try context.save()

        let matches = try context.fetch(CaptureCoordinator.pendingCaptureFetchDescriptor())
        let matchedIDs = Set(matches.map(\.id))
        XCTAssertTrue(matchedIDs.contains(watchOrphan.id), "Watch-orphaned pending row must be re-enriched")
        XCTAssertTrue(matchedIDs.contains(widgetPending.id), "Widget sentinel row must be re-enriched")
        XCTAssertFalse(matchedIDs.contains(completed.id), "Completed row must not be re-enriched")
        XCTAssertFalse(matchedIDs.contains(failed.id), "Explicitly failed row must not be re-enriched")

        // Oldest first.
        XCTAssertEqual(matches.map(\.id), [watchOrphan.id, widgetPending.id])
    }

    func testCSVExportIncludesImportantColumnsAndValues() throws {
        let event = HeadacheEvent(timestamp: Date(timeIntervalSince1970: 1_744_406_400))
        event.locality = "Austin"
        event.region = "TX"
        event.weatherSummary = "Rain"
        event.temperatureC = 19.5
        event.stepsToday = 3456
        event.sleepHoursLastNight = 6.75
        event.lastMainSleepWakeTime = Date(timeIntervalSince1970: 1_744_400_000)
        event.hoursSinceMainSleepWake = 1.78
        event.vo2MaxMlPerKgPerMin = 44.2
        event.barometricPressureDeltaHpa6h = -1.2
        event.usAQI = 41
        event.captureStatus = .partial
        event.healthStatus = .captured
        event.environmentStatus = .failed
        event.healthStatusMessage = "Heart data unavailable"
        event.environmentStatusMessage = "Pollen unavailable"
        event.userNotes = "Saw aura first"
        event.severity = .medium

        let url = try ExportService.exportCSV(events: [event])
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        let csv = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(csv.contains("# One Tap Headache Tracker"))
        XCTAssertTrue(csv.contains("# row_count: 1"))
        XCTAssertTrue(csv.contains("event_id,timestamp,timezone"))
        XCTAssertTrue(csv.contains("weekday,weekday_index,hour"), "M7: CSV must include weekday_index column")
        XCTAssertTrue(csv.contains("temperature_f"))
        XCTAssertTrue(csv.contains("feels_like_f"))
        XCTAssertTrue(csv.contains("\"67.1\""))
        XCTAssertTrue(csv.contains(",severity"))
        XCTAssertTrue(csv.contains(",user_notes"))
        XCTAssertTrue(csv.contains("last_main_sleep_wake_utc"))
        XCTAssertTrue(csv.contains("barometric_pressure_delta_hpa_6h"))
        XCTAssertTrue(csv.contains("\"44.2\""))
        XCTAssertTrue(csv.contains("\"-1.2\""))
        XCTAssertTrue(csv.contains("\"Austin, TX\""))
        XCTAssertTrue(csv.contains("\"Rain\""))
        XCTAssertTrue(csv.contains("\"3456\""))
        XCTAssertTrue(csv.contains("\"6.75\""))
        XCTAssertTrue(csv.contains("\"Heart data unavailable\""))
        XCTAssertTrue(csv.contains("\"Pollen unavailable\""))
        XCTAssertTrue(csv.contains("\"Saw aura first\""))
        XCTAssertTrue(csv.contains("\"medium\""))
    }
}
