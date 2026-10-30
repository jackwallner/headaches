import PDFKit
import UIKit
import XCTest
@testable import OneTapHeadacheTracker

/// Guards for the P1 findings of the 2026-10-30 bug hunt: the milestone card that hid
/// itself, the Doctor PDF in Dark appearance, the sleep window and the sleep total.
@MainActor
final class OvernightFindingsTests: XCTestCase {

    // MARK: - Milestone card (F1)

    func testMilestoneCardStaysAfterItClaimsTheSession() {
        // The card's own claim is not "claimed elsewhere", so it stays on screen.
        XCTAssertEqual(
            HomeView.milestone(count: 10, isPro: false, sessionClaimedElsewhere: false, shown3: false, shown5: false, shown10: false),
            .tenLogs
        )
        XCTAssertNil(
            HomeView.milestone(count: 10, isPro: false, sessionClaimedElsewhere: true, shown3: false, shown5: false, shown10: false),
            "a trial offer that already fired still owns the session"
        )
        XCTAssertNil(HomeView.milestone(count: 10, isPro: true, sessionClaimedElsewhere: false, shown3: false, shown5: false, shown10: false))
    }

    func testRetiredTopMilestoneDoesNotBringBackALowerOne() {
        XCTAssertNil(HomeView.milestone(count: 12, isPro: false, sessionClaimedElsewhere: false, shown3: false, shown5: false, shown10: true))
        XCTAssertEqual(
            HomeView.milestone(count: 6, isPro: false, sessionClaimedElsewhere: false, shown3: true, shown5: false, shown10: false),
            .fiveLogs
        )
        XCTAssertNil(HomeView.milestone(count: 2, isPro: false, sessionClaimedElsewhere: false, shown3: false, shown5: false, shown10: false))
    }

    func testMilestoneCopyIsDescriptive() {
        for milestone in [HomeView.ProMilestone.threeLogs, .fiveLogs, .tenLogs] {
            XCTAssertFalse(milestone.detail.localizedCaseInsensitiveContains("trigger"), milestone.detail)
        }
    }

    func testHomeIsClearForTheRatingAskWithOnlySheetsBlocking() {
        XCTAssertTrue(ReviewPromptTracker.isHomeClear(
            hasCompletedOnboarding: true, homeIsUncovered: true, hasActiveSheet: false, pendingPaywallAfterTrialDismiss: false
        ))
        XCTAssertFalse(ReviewPromptTracker.isHomeClear(
            hasCompletedOnboarding: true, homeIsUncovered: true, hasActiveSheet: true, pendingPaywallAfterTrialDismiss: false
        ))
        XCTAssertFalse(ReviewPromptTracker.isHomeClear(
            hasCompletedOnboarding: true, homeIsUncovered: false, hasActiveSheet: false, pendingPaywallAfterTrialDismiss: false
        ))
    }

    // MARK: - Doctor PDF (F2)

    func testDoctorPDFTitleIsDarkInkInDarkAppearance() throws {
        let saved = UITraitCollection.current
        UITraitCollection.current = UITraitCollection(userInterfaceStyle: .dark)
        defer { UITraitCollection.current = saved }

        let events = (0..<6).map { HeadacheEvent(timestamp: Date().addingTimeInterval(Double(-$0) * 86_400)) }
        let url = try ExportService.exportDoctorPDF(events: events)
        defer { try? FileManager.default.removeItem(at: url) }

        let darkPixels = try darkPixelCount(pdf: url, in: CGRect(x: 36, y: 36, width: 220, height: 30))
        XCTAssertGreaterThan(darkPixels, 500, "title ink is not dark on the white page")
    }

    /// Renders page 1 onto white at 1 pt per pixel and counts pixels darker than mid-gray.
    private func darkPixelCount(pdf url: URL, in rect: CGRect) throws -> Int {
        let page = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        let width = Int(bounds.width), height = Int(bounds.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        page.draw(with: .mediaBox, to: context)

        // Visual proof: the rendered page lands next to the test run's temp files.
        if let image = context.makeImage() {
            let proof = FileManager.default.temporaryDirectory.appendingPathComponent("doctor-pdf-dark.png")
            let png = UIImage(cgImage: image).pngData()
            try? png?.write(to: proof)
            print("Doctor PDF proof: \(proof.path)")
            let attachment = XCTAttachment(image: UIImage(cgImage: image))
            attachment.name = "doctor-pdf-dark"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        // The bitmap's first row is the top of the page.
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let i = (y * width + x) * 4
                let luma = (Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) / 3
                if luma < 128 { count += 1 }
            }
        }
        return count
    }

    // MARK: - Sleep (F3, F4)

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    func testBackfillQueriesTheNightThatEndsOnTheRecordsDay() {
        let calendar = calendar()
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))!
        let window = SleepIntervalMerge.nightWindow(
            before: DailyRecordStore.sleepQueryDate(for: day, calendar: calendar),
            calendar: calendar
        )
        XCTAssertEqual(window.start, calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 18)))
        XCTAssertEqual(window.end, calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12)))
    }

    func testCaptureWindowStillEndsAtTheEvent() {
        let calendar = calendar()
        let event = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 8))!
        let window = SleepIntervalMerge.nightWindow(before: event, calendar: calendar)
        XCTAssertEqual(window.start, calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 18)))
        XCTAssertEqual(window.end, event)
    }

    func testStaleBackfilledSleepIsClearedOnce() {
        let record = DailyRecord(
            date: Date(), hadHeadache: false, headacheCount: 0,
            pressureTrendRaw: PressureTrend.unavailable.rawValue, usAQI: nil,
            weatherFetched: true, sleepHoursLastNight: 1.0, sleepFetched: true
        )
        let reset = DailyRecordStore.resettingStaleSleep([record], storedVersion: 0)
        XCTAssertNil(reset[0].sleepHoursLastNight)
        XCTAssertFalse(reset[0].sleepFetched)
        XCTAssertEqual(
            DailyRecordStore.resettingStaleSleep([record], storedVersion: DailyRecordStore.sleepBackfillVersion),
            [record]
        )
    }

    func testAsleepTotalExcludesAwakeGaps() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }
        // 23:00 to 07:00 with awake gaps of 5, 10 and 25 minutes: 440 minutes asleep.
        let segments = [
            SleepIntervalMerge.Interval(start: at(0), end: at(120)),
            SleepIntervalMerge.Interval(start: at(125), end: at(240)),
            SleepIntervalMerge.Interval(start: at(250), end: at(360)),
            SleepIntervalMerge.Interval(start: at(385), end: at(480)),
        ]
        XCTAssertEqual(SleepIntervalMerge.asleepSeconds(segments) / 60, 440, accuracy: 0.001)
        // Overlapping segments from two sources count once.
        let overlapping = segments + [SleepIntervalMerge.Interval(start: at(10), end: at(100))]
        XCTAssertEqual(SleepIntervalMerge.asleepSeconds(overlapping) / 60, 440, accuracy: 0.001)
        // The merge for the wake time still spans the whole night.
        let merged = SleepIntervalMerge.merge(segments, mergeGap: 45 * 60)
        XCTAssertEqual(SleepIntervalMerge.wakeTimeAfterLongestSleep(merged), at(480))
    }

    // MARK: - Cheap P2s (F9, F11)

    func testSleepTitleFollowsTheBand() {
        XCTAssertEqual(InsightsEngine.sleepBandTitle(label: "8h+", range: 8..<48), "Long sleep: 8h+")
        XCTAssertEqual(InsightsEngine.sleepBandTitle(label: "<5h", range: 0..<5), "Short sleep: <5h")
        XCTAssertEqual(InsightsEngine.sleepBandTitle(label: "7–8h", range: 7..<8), "Sleep: 7–8h")
    }

    func testHeatmapCountsEveryDayAcrossAMidnightDSTChange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Santiago")!
        // Chile springs forward at 00:00 on 6 September 2026.
        let first = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 15))!
        let events = (0..<27).map { HeadacheEvent(timestamp: calendar.date(byAdding: .day, value: $0, to: first)!) }
        let end = events.last!.timestamp
        let days = HeatmapData.build(from: events, days: 90, endingAt: end, calendar: calendar)
        XCTAssertEqual(days.count, 27)
        XCTAssertEqual(days.reduce(0) { $0 + $1.count }, 27)
        XCTAssertTrue(days.allSatisfy { calendar.startOfDay(for: $0.date) == $0.date })
    }

    func testCSVRoundTripKeepsNotes() {
        let notes = ["- nausea, then aura", "Felt \"foggy\" before it started", "+1 day after the move", "@work again", "plain"]
        let row = notes.map { ExportService.csv($0) }.joined(separator: ",")
        XCTAssertEqual(ImportService.parseCSVRow(row), notes)
    }

    func testMostCommonTimeIsStableOnTies() {
        // Events derive their part of day from the current calendar.
        let calendar = Calendar.current
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let hours = [8, 9, 19, 20, 14]
        let events = hours.enumerated().map { index, hour in
            HeadacheEvent(timestamp: calendar.date(byAdding: DateComponents(day: index * 2, hour: hour), to: base)!)
        }
        var titles = Set<String>()
        for _ in 0..<200 {
            let summary = InsightsEngine.summarize(events, calendar: calendar)
            titles.formUnion(summary.insights.map(\.title).filter { $0.hasPrefix("Most common time") })
        }
        XCTAssertLessThanOrEqual(titles.count, 1, "tied part of day flips: \(titles)")
    }
}
