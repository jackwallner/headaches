import SwiftData
import SwiftUI
import WidgetKit

private struct LogHeadacheProvider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, lastLoggedAt: nil) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, lastLoggedAt: Self.lastLoggedDate()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: .now, lastLoggedAt: Self.lastLoggedDate())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }

    private static func lastLoggedDate() -> Date? {
        let context = ModelContext(HeadacheModelStore.sharedModelContainer)
        var descriptor = FetchDescriptor<HeadacheEvent>(
            sortBy: [SortDescriptor(\HeadacheEvent.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.timestamp
    }

    struct Entry: TimelineEntry {
        let date: Date
        let lastLoggedAt: Date?
    }
}

private struct LogHeadacheWidgetContent: View {
    let entry: LogHeadacheProvider.Entry

    var body: some View {
        Button(intent: LogHeadacheIntent()) {
            VStack(spacing: 6) {
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                Text("Log headache")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if let lastLoggedAt = entry.lastLoggedAt {
                    Text("Last: \(lastLoggedAt, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
        }
        .buttonStyle(.plain)
    }
}

struct LogHeadacheWidget: Widget {
    let kind = "com.jackwallner.headachelogger.logwidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LogHeadacheProvider()) { entry in
            LogHeadacheWidgetContent(entry: entry)
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
