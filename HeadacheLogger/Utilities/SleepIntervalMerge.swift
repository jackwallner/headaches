import Foundation

/// Pure helpers to derive main sleep end (wake) time from overlapping sleep segments (no HealthKit dependency — testable).
enum SleepIntervalMerge: Sendable {
    struct Interval: Sendable, Equatable {
        let start: Date
        let end: Date

        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    /// Merges intervals that are within `mergeGap` seconds of each other (Apple often splits sleep into adjacent segments).
    static func merge(_ intervals: [Interval], mergeGap: TimeInterval) -> [Interval] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start < $1.start }
        var out: [Interval] = []
        for interval in sorted {
            guard let last = out.last else {
                out.append(interval)
                continue
            }
            if interval.start <= last.end.addingTimeInterval(mergeGap) {
                out[out.count - 1] = Interval(start: last.start, end: max(last.end, interval.end))
            } else {
                out.append(interval)
            }
        }
        return out
    }

    /// Time actually asleep: the union of the raw asleep segments. The 45-minute merge is only
    /// for finding the main block's wake time; summing it counted the awake gaps as sleep.
    static func asleepSeconds(_ intervals: [Interval]) -> TimeInterval {
        merge(intervals, mergeGap: 0).reduce(0) { $0 + $1.duration }
    }

    /// The night a sleep query covers: the previous day's 18:00 to min(date, that day's 12:00),
    /// so afternoon and evening queries don't fold naps into last night. Falls back to a 24 h
    /// look-back if the range would be inverted.
    static func nightWindow(before date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let previousEvening = calendar.date(
            bySettingHour: 18,
            minute: 0,
            second: 0,
            of: calendar.date(byAdding: .day, value: -1, to: date) ?? date.addingTimeInterval(-86_400)
        ) ?? date.addingTimeInterval(-86_400)
        let todayNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let end = min(date, todayNoon)
        let start = previousEvening < end ? previousEvening : date.addingTimeInterval(-86_400)
        return (start, end)
    }

    /// End time of the longest merged block (proxy for “main sleep” wake time).
    static func wakeTimeAfterLongestSleep(_ merged: [Interval]) -> Date? {
        merged.max(by: { $0.duration < $1.duration })?.end
    }
}
