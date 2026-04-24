import SwiftUI
import WidgetKit

private struct LogHeadacheProvider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, showConfirmation: false) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, showConfirmation: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // C12: base the confirmation window on the **absolute tap time** (not widget render time)
        // and widen the window to 10s so delayed re-renders (system under load, off-screen widget,
        // queued reloadAllTimelines) still let the user see "Logged" at least briefly.
        // M11: follow up with `.after(revertDate)` so iOS rebuilds the timeline once the window
        // closes — prevents a rare stale-confirmation lockup after widget eviction.
        let windowSeconds: TimeInterval = 10
        let lastLogged = HeadacheAppGroup.userDefaults.double(forKey: HeadacheStorageKey.widgetLastLoggedAt.rawValue)

        if lastLogged > 0 {
            let tapDate = Date(timeIntervalSince1970: lastLogged)
            let revertDate = tapDate.addingTimeInterval(windowSeconds)
            if Date() < revertDate {
                let entries = [
                    Entry(date: tapDate, showConfirmation: true),
                    Entry(date: revertDate, showConfirmation: false),
                ]
                completion(Timeline(entries: entries, policy: .after(revertDate)))
                return
            }
        }
        completion(Timeline(entries: [Entry(date: .now, showConfirmation: false)], policy: .never))
    }

    struct Entry: TimelineEntry {
        let date: Date
        let showConfirmation: Bool
    }
}

private struct LogHeadacheWidgetContent: View {
    var showConfirmation: Bool

    var body: some View {
        if showConfirmation {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.green)
                Text("Logged")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
        } else {
            Button(intent: LogHeadacheIntent()) {
                VStack(spacing: 8) {
                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 32))
                        .symbolRenderingMode(.hierarchical)
                    Text("Log headache")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
            }
            .buttonStyle(.plain)
        }
    }
}

struct LogHeadacheWidget: Widget {
    let kind = "com.jackwallner.headachelogger.logwidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LogHeadacheProvider()) { entry in
            LogHeadacheWidgetContent(showConfirmation: entry.showConfirmation)
                .containerBackground(for: .widget) {
                    Color(red: 0.35, green: 0.12, blue: 0.16)
                }
        }
        .configurationDisplayName("Log headache")
        .description("One tap to log a headache.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct HeadacheLoggerWidgetBundle: WidgetBundle {
    var body: some Widget {
        LogHeadacheWidget()
    }
}
