import Foundation
import SwiftData

/// SwiftData store for One Tap Headache Tracker.
///
/// **Crash fix (TestFlight):** Do not use `ModelConfiguration`'s `groupContainer:` parameter when the app group
/// may be unavailable — SwiftData asserts in `discoverDirectory`. Resolve a concrete file URL instead: prefer
/// the App Group container when the entitlement is present, otherwise Application Support (same pattern as Vitals `DataService`).
enum HeadacheModelStore {
    static let appGroupID = "group.com.jackwallner.headachelogger"

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([HeadacheEvent.self])
        let url = storeURL

        if let container = makeContainer(schema: schema, url: url) {
            return container
        }

        // A failed migration or half-written file can leave the store unopenable.
        // The headache log exists nowhere else, so move it aside instead of deleting it.
        consoleError("HeadacheModelStore: ModelContainer failed, quarantining store and retrying", trace: ["url": url.path])
        quarantineStore(at: url)

        if let container = makeContainer(schema: schema, url: url) {
            return container
        }

        consoleError("HeadacheModelStore: falling back to in-memory store", trace: [:])
        let inMemory = ModelConfiguration("HeadacheLogger", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [inMemory])
        } catch {
            fatalError("HeadacheModelStore: ModelContainer could not initialize even in-memory: \(error)")
        }
    }()

    /// Renames the store and its SQLite sidecars to `<name>.corrupt-<uuid>` so a
    /// fresh store can open at `url`. Returns the quarantined copies.
    @discardableResult
    static func quarantineStore(at url: URL, fileManager: FileManager = .default) -> [URL] {
        let suffix = ".corrupt-\(UUID().uuidString)"
        let candidates = [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm"),
            url.appendingPathExtension("wal"),
            url.appendingPathExtension("shm")
        ]
        var moved: [URL] = []
        for file in candidates where fileManager.fileExists(atPath: file.path) {
            let destination = URL(fileURLWithPath: file.path + suffix)
            if (try? fileManager.moveItem(at: file, to: destination)) != nil {
                moved.append(destination)
            }
        }
        return moved
    }

    private static func makeContainer(schema: Schema, url: URL) -> ModelContainer? {
        let config = ModelConfiguration(
            "HeadacheLogger",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try? ModelContainer(for: schema, configurations: [config])
    }

    private static var storeURL: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("HeadacheLogger.store")
    }

    private static func consoleError(_ message: String, trace: [String: String]) {
        var parts = [message]
        if !trace.isEmpty {
            parts.append(trace.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        }
        #if DEBUG
        print(parts.joined(separator: " | "))
        #endif
    }
}
