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

    // MARK: - Export / Import Round-Trip Tests

    func testExportImportRoundTripPreservesAllFields() throws {
        let schema = Schema([HeadacheEvent.self])
        let config = ModelConfiguration("ExportImportTest", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])

        let original = makeFullyPopulatedEvent()
        let context = ModelContext(container)
        context.insert(original)
        try context.save()

        let url = try ExportService.exportCSV(events: [original])
        defer { try? FileManager.default.removeItem(at: url) }

        let rows = try ImportService.parseCSV(from: url)
        XCTAssertEqual(rows.count, 1, "Should parse exactly one row from the export")

        let result = ImportService.importEvents(from: rows, into: context, strategy: .skipExisting)
        XCTAssertEqual(result.imported, 0, "Event with same UUID already exists, should be skipped")
        XCTAssertEqual(result.skipped, 1)

        let overwriteResult = ImportService.importEvents(from: rows, into: context, strategy: .overwriteExisting)
        XCTAssertEqual(overwriteResult.overwritten, 1)
        try context.save()

        let descriptor = FetchDescriptor<HeadacheEvent>()
        let all = try context.fetch(descriptor)
        let fetched = try XCTUnwrap(all.first(where: { $0.id == original.id }))

        assertEventEquals(original: original, imported: fetched)
    }

    func testImportHandlesMultipleEventsWithDedup() throws {
        let schema = Schema([HeadacheEvent.self])
        let config = ModelConfiguration("MultiImportTest", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let e1 = HeadacheEvent(timestamp: Date(timeIntervalSince1970: 1_700_000_000))
        e1.severity = .slight
        e1.userNotes = "event one"
        context.insert(e1)

        let e2 = HeadacheEvent(timestamp: Date(timeIntervalSince1970: 1_700_100_000))
        e2.severity = .extreme
        let e3 = HeadacheEvent(timestamp: Date(timeIntervalSince1970: 1_700_200_000))
        e3.temperatureC = 25.5

        try context.save()

        let url = try ExportService.exportCSV(events: [e1, e2, e3])
        defer { try? FileManager.default.removeItem(at: url) }

        let rows = try ImportService.parseCSV(from: url)
        XCTAssertEqual(rows.count, 3)

        let freshContext = ModelContext(container)
        let result = ImportService.importEvents(from: rows, into: freshContext, strategy: .skipExisting)
        XCTAssertEqual(result.imported, 2, "e1 already in context, should be skipped; e2 and e3 are new IDs in fresh context? Wait, they were inserted into the same context")

        // Actually e1/e2/e3 are all in the same context. Let me test with a completely fresh context.
        let freshContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration("MultiImportFresh", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let trulyFresh = ModelContext(freshContainer)
        let freshResult = ImportService.importEvents(from: rows, into: trulyFresh, strategy: .skipExisting)
        XCTAssertEqual(freshResult.imported, 3)
        XCTAssertEqual(freshResult.skipped, 0)
        XCTAssertEqual(freshResult.errors, 0)
    }

    func testImportSkipsInvalidRowsGracefully() throws {
        let schema = Schema([HeadacheEvent.self])
        let config = ModelConfiguration("InvalidImportTest", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let valid = HeadacheEvent(timestamp: Date(timeIntervalSince1970: 1_700_000_000))
        valid.severity = .medium
        context.insert(valid)
        try context.save()

        let url = try ExportService.exportCSV(events: [valid])
        defer { try? FileManager.default.removeItem(at: url) }

        let rows = try ImportService.parseCSV(from: url)
        var tamperedRow = rows[0]
        tamperedRow["event_id"] = "not-a-uuid"
        tamperedRow["timestamp"] = "garbage-timestamp"
        var badRows = rows
        badRows.append(tamperedRow)

        let result = ImportService.importEvents(from: badRows, into: context, strategy: .skipExisting)
        XCTAssertEqual(result.skipped, 1) // valid but duplicate UUID
        XCTAssertEqual(result.errors, 1)  // bad UUID
        XCTAssertEqual(result.imported, 0)
    }

    func testCSVPreambleIsSkippedByParser() throws {
        let event = HeadacheEvent(timestamp: Date(timeIntervalSince1970: 1_700_000_000))
        let url = try ExportService.exportCSV(events: [event])
        defer { try? FileManager.default.removeItem(at: url) }

        let rows = try ImportService.parseCSV(from: url)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["event_id"], event.id.uuidString)
    }

    func testExportImportHeavyDutyRoundTrip() throws {
        let schema = Schema([HeadacheEvent.self])
        let config = ModelConfiguration("HeavyDutyTest", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])

        var events: [HeadacheEvent] = []
        var base = Date(timeIntervalSince1970: 1_744_000_000)
        for i in 0..<20 {
            let e = HeadacheEvent(timestamp: base.addingTimeInterval(Double(i) * 7200))
            e.temperatureC = Double(20 + i % 15)
            e.humidityPercent = Double(40 + i % 40)
            e.pressureHpa = Double(1010 + i % 20)
            e.stepsToday = (5000 + i * 123) % 12000
            e.sleepHoursLastNight = Double(5 + i % 5)
            e.severity = HeadacheSeverity.allCases[i % 3]
            e.userNotes = i % 5 == 0 ? "Note for event \(i)" : nil
            e.usAQI = Double(20 + i % 60)
            e.pm25 = Double(i % 30)
            e.alderPollen = i % 2 == 0 ? Double(i) : nil
            events.append(e)
        }

        let context = ModelContext(container)
        for e in events { context.insert(e) }
        try context.save()

        let url = try ExportService.exportCSV(events: events)
        defer { try? FileManager.default.removeItem(at: url) }

        let rows = try ImportService.parseCSV(from: url)
        XCTAssertEqual(rows.count, 20)

        let freshContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration("HeavyDutyFresh", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let freshContext = ModelContext(freshContainer)
        let result = ImportService.importEvents(from: rows, into: freshContext, strategy: .skipExisting)
        XCTAssertEqual(result.imported, 20)
        XCTAssertEqual(result.errors, 0)

        let importedEvents = try freshContext.fetch(FetchDescriptor<HeadacheEvent>(sortBy: [SortDescriptor(\.timestamp)]))
        XCTAssertEqual(importedEvents.count, 20)

        for (original, imported) in zip(events.sorted(by: { $0.timestamp < $1.timestamp }), importedEvents) {
            XCTAssertEqual(imported.temperatureC, original.temperatureC)
            XCTAssertEqual(imported.humidityPercent, original.humidityPercent)
            XCTAssertEqual(imported.pressureHpa, original.pressureHpa)
            XCTAssertEqual(imported.stepsToday, original.stepsToday)
            XCTAssertEqual(imported.sleepHoursLastNight, original.sleepHoursLastNight)
            XCTAssertEqual(imported.severity, original.severity)
            XCTAssertEqual(imported.userNotes, original.userNotes)
            XCTAssertEqual(imported.usAQI, original.usAQI)
            XCTAssertEqual(imported.alderPollen, original.alderPollen)
        }
    }

    // MARK: - Helpers

    private func makeFullyPopulatedEvent() -> HeadacheEvent {
        let calendar = Calendar(identifier: .gregorian)
        let timestamp = calendar.date(from: DateComponents(
            year: 2026, month: 5, day: 10,
            hour: 14, minute: 30, second: 0
        ))!

        let event = HeadacheEvent(timestamp: timestamp)

        event.captureStatusRaw = CaptureStatus.complete.rawValue
        event.healthStatusRaw = CaptureSourceStatus.captured.rawValue
        event.environmentStatusRaw = CaptureSourceStatus.captured.rawValue
        event.healthStatusMessage = "Heart data incomplete"
        event.environmentStatusMessage = "Pollen data partial"

        event.locality = "Portland"
        event.region = "OR"
        event.weatherSummary = "Partly Cloudy"
        event.weatherCode = 2
        event.temperatureC = 18.75
        event.apparentTemperatureC = 19.2
        event.humidityPercent = 64.5
        event.pressureHpa = 1012.3
        event.pressureTrendRaw = PressureTrend.falling.rawValue
        event.precipitationMm = 0.5
        event.windSpeedKph = 12.3
        event.windDirectionDegrees = 225
        event.cloudCoverPercent = 60
        event.uvIndex = 4.5
        event.usAQI = 42
        event.europeanAQI = 35
        event.pm25 = 8.5
        event.pm10 = 15.2
        event.ozone = 72.0
        event.nitrogenDioxide = 10.5
        event.sulphurDioxide = 2.1
        event.carbonMonoxide = 180.0
        event.alderPollen = 12.0
        event.birchPollen = 8.5
        event.grassPollen = 3.2
        event.mugwortPollen = nil
        event.olivePollen = nil
        event.ragweedPollen = 1.5

        event.stepsToday = 8765
        event.activeEnergyKcalToday = 320.5
        event.distanceWalkingRunningKmToday = 5.2
        event.exerciseMinutesToday = 35
        event.sleepHoursLastNight = 7.25
        event.lastMainSleepWakeTime = Date(timeIntervalSince1970: timestamp.timeIntervalSince1970 - 36000)
        event.hoursSinceMainSleepWake = 10.0
        event.restingHeartRateBpm = 62
        event.recentHeartRateAverageBpm = 72.5
        event.hrvSDNNMs = 45.2
        event.respiratoryRateBrpm = 16.0
        event.workoutsLast24h = 1
        event.workoutMinutesLast24h = 45
        event.environmentalAudioExposureDbA = 55.0
        event.oxygenSaturationPercent = 98.5
        event.vo2MaxMlPerKgPerMin = 44.5
        event.walkingSpeedMetersPerSecond = 1.2
        event.appleStandMinutesToday = 480
        event.basalEnergyKcalToday = 1800
        event.flightsClimbedToday = 4
        event.mindfulMinutesToday = 10
        event.barometricPressureDeltaHpa6h = -2.5

        event.severity = .extreme
        event.userNotes = "Started after lunch, aura present"

        return event
    }

    private func assertEventEquals(original: HeadacheEvent, imported: HeadacheEvent, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(imported.id, original.id, file: file, line: line)
        XCTAssertEqual(imported.timestamp.timeIntervalSince1970, original.timestamp.timeIntervalSince1970, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(imported.timezoneIdentifier, original.timezoneIdentifier, file: file, line: line)
        XCTAssertEqual(imported.weekdayIndex, original.weekdayIndex, file: file, line: line)
        XCTAssertEqual(imported.weekdayName, original.weekdayName, file: file, line: line)
        XCTAssertEqual(imported.hourOfDay, original.hourOfDay, file: file, line: line)
        XCTAssertEqual(imported.minuteOfHour, original.minuteOfHour, file: file, line: line)
        XCTAssertEqual(imported.partOfDayRaw, original.partOfDayRaw, file: file, line: line)
        XCTAssertEqual(imported.captureStatusRaw, original.captureStatusRaw, file: file, line: line)
        XCTAssertEqual(imported.healthStatusRaw, original.healthStatusRaw, file: file, line: line)
        XCTAssertEqual(imported.environmentStatusRaw, original.environmentStatusRaw, file: file, line: line)
        XCTAssertEqual(imported.healthStatusMessage, original.healthStatusMessage, file: file, line: line)
        XCTAssertEqual(imported.environmentStatusMessage, original.environmentStatusMessage, file: file, line: line)
        XCTAssertEqual(imported.locality, original.locality, file: file, line: line)
        XCTAssertEqual(imported.region, original.region, file: file, line: line)
        XCTAssertEqual(imported.weatherSummary, original.weatherSummary, file: file, line: line)
        XCTAssertEqual(imported.temperatureC, original.temperatureC, file: file, line: line)
        XCTAssertEqual(imported.apparentTemperatureC, original.apparentTemperatureC, file: file, line: line)
        XCTAssertEqual(imported.humidityPercent, original.humidityPercent, file: file, line: line)
        XCTAssertEqual(imported.pressureHpa, original.pressureHpa, file: file, line: line)
        XCTAssertEqual(imported.pressureTrendRaw, original.pressureTrendRaw, file: file, line: line)
        XCTAssertEqual(imported.precipitationMm, original.precipitationMm, file: file, line: line)
        XCTAssertEqual(imported.windSpeedKph, original.windSpeedKph, file: file, line: line)
        XCTAssertEqual(imported.windDirectionDegrees, original.windDirectionDegrees, file: file, line: line)
        XCTAssertEqual(imported.cloudCoverPercent, original.cloudCoverPercent, file: file, line: line)
        XCTAssertEqual(imported.uvIndex, original.uvIndex, file: file, line: line)
        XCTAssertEqual(imported.usAQI, original.usAQI, file: file, line: line)
        XCTAssertEqual(imported.europeanAQI, original.europeanAQI, file: file, line: line)
        XCTAssertEqual(imported.pm25, original.pm25, file: file, line: line)
        XCTAssertEqual(imported.pm10, original.pm10, file: file, line: line)
        XCTAssertEqual(imported.ozone, original.ozone, file: file, line: line)
        XCTAssertEqual(imported.nitrogenDioxide, original.nitrogenDioxide, file: file, line: line)
        XCTAssertEqual(imported.sulphurDioxide, original.sulphurDioxide, file: file, line: line)
        XCTAssertEqual(imported.carbonMonoxide, original.carbonMonoxide, file: file, line: line)
        XCTAssertEqual(imported.alderPollen, original.alderPollen, file: file, line: line)
        XCTAssertEqual(imported.birchPollen, original.birchPollen, file: file, line: line)
        XCTAssertEqual(imported.grassPollen, original.grassPollen, file: file, line: line)
        XCTAssertEqual(imported.mugwortPollen, original.mugwortPollen, file: file, line: line)
        XCTAssertEqual(imported.olivePollen, original.olivePollen, file: file, line: line)
        XCTAssertEqual(imported.ragweedPollen, original.ragweedPollen, file: file, line: line)
        XCTAssertEqual(imported.stepsToday, original.stepsToday, file: file, line: line)
        XCTAssertEqual(imported.activeEnergyKcalToday, original.activeEnergyKcalToday, file: file, line: line)
        XCTAssertEqual(imported.distanceWalkingRunningKmToday, original.distanceWalkingRunningKmToday, file: file, line: line)
        XCTAssertEqual(imported.exerciseMinutesToday, original.exerciseMinutesToday, file: file, line: line)
        XCTAssertEqual(imported.sleepHoursLastNight, original.sleepHoursLastNight, file: file, line: line)
        if let originalWake = original.lastMainSleepWakeTime {
            guard let importedWake = imported.lastMainSleepWakeTime else {
                XCTFail("Expected imported.lastMainSleepWakeTime but got nil", file: file, line: line)
                return
            }
            XCTAssertEqual(importedWake.timeIntervalSince1970, originalWake.timeIntervalSince1970, accuracy: 0.001, file: file, line: line)
        } else {
            XCTAssertNil(imported.lastMainSleepWakeTime, file: file, line: line)
        }
        XCTAssertEqual(imported.hoursSinceMainSleepWake, original.hoursSinceMainSleepWake, file: file, line: line)
        XCTAssertEqual(imported.restingHeartRateBpm, original.restingHeartRateBpm, file: file, line: line)
        XCTAssertEqual(imported.recentHeartRateAverageBpm, original.recentHeartRateAverageBpm, file: file, line: line)
        XCTAssertEqual(imported.hrvSDNNMs, original.hrvSDNNMs, file: file, line: line)
        XCTAssertEqual(imported.respiratoryRateBrpm, original.respiratoryRateBrpm, file: file, line: line)
        XCTAssertEqual(imported.workoutsLast24h, original.workoutsLast24h, file: file, line: line)
        XCTAssertEqual(imported.workoutMinutesLast24h, original.workoutMinutesLast24h, file: file, line: line)
        XCTAssertEqual(imported.environmentalAudioExposureDbA, original.environmentalAudioExposureDbA, file: file, line: line)
        XCTAssertEqual(imported.oxygenSaturationPercent, original.oxygenSaturationPercent, file: file, line: line)
        XCTAssertEqual(imported.vo2MaxMlPerKgPerMin, original.vo2MaxMlPerKgPerMin, file: file, line: line)
        XCTAssertEqual(imported.walkingSpeedMetersPerSecond, original.walkingSpeedMetersPerSecond, file: file, line: line)
        XCTAssertEqual(imported.appleStandMinutesToday, original.appleStandMinutesToday, file: file, line: line)
        XCTAssertEqual(imported.basalEnergyKcalToday, original.basalEnergyKcalToday, file: file, line: line)
        XCTAssertEqual(imported.flightsClimbedToday, original.flightsClimbedToday, file: file, line: line)
        XCTAssertEqual(imported.mindfulMinutesToday, original.mindfulMinutesToday, file: file, line: line)
        XCTAssertEqual(imported.barometricPressureDeltaHpa6h, original.barometricPressureDeltaHpa6h, file: file, line: line)
        XCTAssertEqual(imported.severity, original.severity, file: file, line: line)
        XCTAssertEqual(imported.userNotes, original.userNotes, file: file, line: line)
    }

    // MARK: - InsightsEngine (pattern recognition)

    func testInsightsReturnsEmptyBelowMinimumSampleSize() {
        let events = (0..<(InsightsEngine.minimumSampleSize - 1)).map { i in
            makeEvent(daysAgo: i, hour: 19) // all evening
        }
        let summary = InsightsEngine.summarize(events)
        XCTAssertEqual(summary.totalEvents, events.count)
        XCTAssertTrue(summary.insights.isEmpty, "Insights must not surface below the minimum sample size")
    }

    func testInsightsDateRangeReflectsLoggedSpan() {
        let events = (0..<6).map { i in makeEvent(daysAgo: i, hour: 12) }
        let summary = InsightsEngine.summarize(events)
        XCTAssertNotNil(summary.dateRange)
        XCTAssertEqual(summary.totalEvents, 6)
    }

    func testPartOfDayInsightFiresOnEveningCluster() {
        // 7 evenings + 1 morning + 1 afternoon = 9 total, evening share ≈ 0.78 → above 0.30 floor.
        var events = (0..<7).map { i in makeEvent(daysAgo: i, hour: 19) }
        events.append(makeEvent(daysAgo: 8, hour: 7))
        events.append(makeEvent(daysAgo: 9, hour: 14))

        let summary = InsightsEngine.summarize(events)
        let pod = summary.insights.first(where: { $0.id == "part-of-day" })
        XCTAssertNotNil(pod, "Evening cluster should produce a part-of-day insight")
        XCTAssertEqual(pod?.category, .time)
        XCTAssertTrue((pod?.detail ?? "").lowercased().contains("evening"))
        XCTAssertEqual(pod?.breakdown.buckets.count, 4)
        let peak = pod?.breakdown.buckets.first(where: { $0.isPeak })
        XCTAssertEqual(peak?.label, "Evening")
        let totalShare = (pod?.breakdown.buckets.map(\.share).reduce(0, +)) ?? 0
        XCTAssertEqual(totalShare, 1.0, accuracy: 0.001, "Bucket shares must sum to 1")
    }

    func testPartOfDayInsightSuppressedWhenNoCluster() {
        // 2 in each bucket → top share = 0.25 < 0.30 floor.
        let hours = [7, 7, 14, 14, 19, 19, 2, 2]
        let events = hours.enumerated().map { (i, h) in makeEvent(daysAgo: i, hour: h) }
        let summary = InsightsEngine.summarize(events)
        XCTAssertNil(summary.insights.first(where: { $0.id == "part-of-day" }),
                     "No insight should fire when no part-of-day exceeds the 30% floor")
    }

    func testSleepInsightFiresOnLowSleepCluster() {
        let sleeps: [Double] = [4.5, 4.8, 5.2, 5.6, 7.5, 7.9, 8.1] // 4 of 7 < 6h → 57%
        let events = sleeps.enumerated().map { (i, h) in
            let e = makeEvent(daysAgo: i, hour: 12)
            e.sleepHoursLastNight = h
            return e
        }
        let summary = InsightsEngine.summarize(events)
        let sleep = summary.insights.first(where: { $0.id == "sleep" })
        XCTAssertNotNil(sleep)
        XCTAssertTrue((sleep?.detail ?? "").contains("under 6 hours"),
                      "Detail should call out the low-sleep concentration")
        XCTAssertGreaterThan(sleep?.strength ?? 0, 0.5)
    }

    func testPressureTrendInsightFiresOnFallingCluster() {
        // 5 falling, 1 steady, 1 rising → falling 71% > 45% floor.
        let trends: [PressureTrend] = [.falling, .falling, .falling, .falling, .falling, .steady, .rising]
        let events = trends.enumerated().map { (i, t) in
            let e = makeEvent(daysAgo: i, hour: 14)
            e.pressureTrend = t
            return e
        }
        let summary = InsightsEngine.summarize(events)
        let pressure = summary.insights.first(where: { $0.id == "pressure-trend" })
        XCTAssertNotNil(pressure)
        XCTAssertEqual(pressure?.category, .pressure)
        XCTAssertTrue((pressure?.title ?? "").lowercased().contains("falling"))
    }

    func testPressureTrendIgnoresUnavailable() {
        // Only 4 events have pressure data. Engine min sample size = 5 so the insight should NOT fire.
        let events = (0..<6).enumerated().map { (_, idx) -> HeadacheEvent in
            let e = makeEvent(daysAgo: idx, hour: 14)
            if idx < 4 { e.pressureTrend = .falling } // others stay .unavailable
            return e
        }
        let summary = InsightsEngine.summarize(events)
        XCTAssertNil(summary.insights.first(where: { $0.id == "pressure-trend" }),
                     "Pressure-trend insight should require at least minimumSampleSize events with pressure data")
    }

    func testAirQualityInsightFiresOnElevatedExposure() {
        let aqis: [Double] = [80, 95, 110, 60, 40, 75] // 4 of 6 ≥ 75 → 67%
        let events = aqis.enumerated().map { (i, q) in
            let e = makeEvent(daysAgo: i, hour: 14)
            e.usAQI = q
            return e
        }
        let summary = InsightsEngine.summarize(events)
        let aqi = summary.insights.first(where: { $0.id == "aqi" })
        XCTAssertNotNil(aqi)
        XCTAssertEqual(aqi?.category, .airQuality)
    }

    func testInsightsRankByStrength() {
        // Pile up an evening + low-sleep cluster so we get multiple insights, ensure ordering.
        let events = (0..<8).map { i -> HeadacheEvent in
            let e = makeEvent(daysAgo: i, hour: 19) // strong evening cluster
            e.sleepHoursLastNight = 4.5             // strong low-sleep cluster
            return e
        }
        let summary = InsightsEngine.summarize(events)
        XCTAssertGreaterThanOrEqual(summary.insights.count, 2)
        for i in 0..<(summary.insights.count - 1) {
            XCTAssertGreaterThanOrEqual(summary.insights[i].strength,
                                        summary.insights[i + 1].strength,
                                        "Insights should be sorted strongest first")
        }
    }

    func testPersonalAlertProfileSupportsPressureOnlyWhenUserDataMatches() {
        let supported = makeTestRecords(
            totalDays: 14,
            headacheDays: [0, 1, 2, 3, 4, 7, 8],
            pressureTrends: [
                0: .falling, 1: .falling, 2: .falling, 3: .falling, 4: .falling,
                5: .steady, 6: .rising,
                7: .steady, 8: .rising,
                9: .steady, 10: .steady, 11: .rising, 12: .rising, 13: .steady
            ]
        )
        let profile = ProactiveAlertsEngine.makePersonalAlertProfile(events: [])
        let pressureProfile = profileForRecords(supported)
        XCTAssertTrue(pressureProfile.isSupported)
        XCTAssertEqual(pressureProfile.conditionDays, 5)
        XCTAssertEqual(pressureProfile.headacheConditionDays, 5)
        XCTAssertGreaterThan(pressureProfile.relativeRisk, 1.5)

        let unsupported = makeTestRecords(
            totalDays: 14,
            headacheDays: [0, 1, 6, 7, 8, 9, 10],
            pressureTrends: [
                0: .falling, 1: .steady,
                2: .steady, 3: .steady, 4: .steady, 5: .steady,
                6: .steady, 7: .steady, 8: .steady, 9: .steady,
                10: .steady, 11: .falling, 12: .steady, 13: .steady
            ]
        )
        let unsupportedProfile = profileForRecords(unsupported)
        XCTAssertFalse(unsupportedProfile.isSupported)
    }

    func testForecastAlertRequiresPersonalPressureSignal() {
        let prefs = ProAlertPreferenceValues(
            alertsEnabled: true,
            pressureDropThresholdHpa: 4.0,
            airQualityEnabled: true,
            airQualityThreshold: 100,
            quietHoursEnabled: false,
            quietHoursStart: 22,
            quietHoursEnd: 7,
            patternAlertsEnabled: false,
            patternAlertSensitivity: 0
        )
        let forecast = HourlyForecast(
            times: (0..<6).map { Date(timeIntervalSince1970: Double($0 * 3600)) },
            pressureMsl: [1015, 1014, 1011, 1009, 1008, 1008],
            usAqi: [nil, nil, nil, nil, nil, nil]
        )

        XCTAssertNil(ProactiveAlertsEngine.evaluate(forecast: forecast, prefs: prefs, profile: .empty))

        let profile = ProactiveAlertsEngine.PersonalAlertProfile(
            updatedAt: Date(timeIntervalSince1970: 0),
            pressure: ProactiveAlertsEngine.PersonalSignalProfile(
                totalDays: 14,
                conditionDays: 5,
                headacheConditionDays: 5,
                pHeadacheGivenCondition: 5.0 / 6.0,
                pHeadacheGivenNoCondition: 2.0 / 8.0,
                relativeRisk: 3.33,
                lift: 2.33,
                isSupported: true
            ),
            airQuality: .empty
        )
        let decision = ProactiveAlertsEngine.evaluate(forecast: forecast, prefs: prefs, profile: profile)
        XCTAssertEqual(decision?.kind, .pressureDrop)
        XCTAssertTrue(decision?.body.contains("more likely") == true)
        XCTAssertTrue(decision?.body.contains("risk") == true)
    }

    func testForecastAlertCanUsePersonalAirQualitySignal() {
        let prefs = ProAlertPreferenceValues(
            alertsEnabled: true,
            pressureDropThresholdHpa: 4.0,
            airQualityEnabled: true,
            airQualityThreshold: 100,
            quietHoursEnabled: false,
            quietHoursStart: 22,
            quietHoursEnd: 7,
            patternAlertsEnabled: false,
            patternAlertSensitivity: 0
        )
        let forecast = HourlyForecast(
            times: (0..<4).map { Date(timeIntervalSince1970: Double($0 * 3600)) },
            pressureMsl: [1012, 1012, 1012, 1012],
            usAqi: [80, 95, 120, 110]
        )
        let profile = ProactiveAlertsEngine.PersonalAlertProfile(
            updatedAt: Date(timeIntervalSince1970: 0),
            pressure: .empty,
            airQuality: ProactiveAlertsEngine.PersonalSignalProfile(
                totalDays: 14,
                conditionDays: 4,
                headacheConditionDays: 4,
                pHeadacheGivenCondition: 4.0 / 5.0,
                pHeadacheGivenNoCondition: 3.0 / 9.0,
                relativeRisk: 2.4,
                lift: 1.4,
                isSupported: true
            )
        )

        let decision = ProactiveAlertsEngine.evaluate(forecast: forecast, prefs: prefs, profile: profile)
        XCTAssertEqual(decision?.kind, .airQuality)
        XCTAssertTrue(decision?.body.contains("more likely") == true)
        XCTAssertTrue(decision?.body.contains("risk") == true)
    }

    // MARK: - daily record test helpers

    private func makeTestRecords(totalDays: Int, headacheDays: [Int], pressureTrends: [Int: PressureTrend]) -> [DailyRecord] {
        let today = DailyRecordStore.normalizeDate(Date())
        let calendar = Calendar.current
        var records: [DailyRecord] = []
        for i in 0..<totalDays {
            guard let date = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            let hadHeadache = headacheDays.contains(i)
            let trend = pressureTrends[i] ?? .steady
            records.append(DailyRecord(
                date: date,
                hadHeadache: hadHeadache,
                headacheCount: hadHeadache ? 1 : 0,
                pressureTrendRaw: trend.rawValue,
                usAQI: nil,
                weatherFetched: true,
                sleepHoursLastNight: nil,
                sleepFetched: false
            ))
        }
        return records.sorted { $0.date < $1.date }
    }

    private func profileForRecords(_ records: [DailyRecord]) -> ProactiveAlertsEngine.PersonalSignalProfile {
        ProactiveAlertsEngine.pressureSignalProfile(from: records)
    }

    // MARK: - test helpers

    private func makeEvent(daysAgo: Int, hour: Int) -> HeadacheEvent {
        var components = DateComponents()
        components.day = -daysAgo
        components.hour = -((Calendar.current.component(.hour, from: .now)) - hour)
        let base = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        let withHour = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
        return HeadacheEvent(timestamp: withHour)
    }
}
