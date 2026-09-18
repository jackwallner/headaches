import XCTest
@testable import OneTapHeadacheTracker

/// An unopenable store is moved aside, never deleted: the headache log exists nowhere else.
final class StoreQuarantineTests: XCTestCase {
    func testUnreadableStoreIsMovedAsideNotDeleted() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = dir.appendingPathComponent("HeadacheLogger.store")
        let wal = URL(fileURLWithPath: store.path + "-wal")
        try Data("headaches".utf8).write(to: store)
        try Data("wal".utf8).write(to: wal)

        let moved = HeadacheModelStore.quarantineStore(at: store)

        XCTAssertEqual(moved.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: wal.path))
        let copy = try XCTUnwrap(moved.first { !$0.lastPathComponent.contains("-wal") })
        XCTAssertTrue(copy.lastPathComponent.hasPrefix("HeadacheLogger.store.corrupt-"))
        XCTAssertEqual(try Data(contentsOf: copy), Data("headaches".utf8))
    }

    func testMissingStoreQuarantinesNothing() {
        let store = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("HeadacheLogger.store")
        XCTAssertTrue(HeadacheModelStore.quarantineStore(at: store).isEmpty)
    }
}
