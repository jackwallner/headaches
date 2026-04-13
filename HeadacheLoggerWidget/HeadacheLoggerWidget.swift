import SwiftUI
import WidgetKit

private struct LogHeadacheProvider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, showConfirmation: false) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, showConfirmation: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let lastLogged = HeadacheAppGroup.userDefaults.double(forKey: HeadacheStorageKey.widgetLastLoggedAt.rawValue)
        let recentlyLogged = lastLogged > 0 && Date().timeIntervalSince1970 - lastLogged < 4

        if recentlyLogged {
            let now = Date()
            let revert = now.addingTimeInterval(4)
            let entries = [
                Entry(date: now, showConfirmation: true),
                Entry(date: revert, showConfirmation: false),
            ]
            completion(Timeline(entries: entries, policy: .never))
        } else {
            completion(Timeline(entries: [Entry(date: .now, showConfirmation: false)], policy: .never))
        }
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
