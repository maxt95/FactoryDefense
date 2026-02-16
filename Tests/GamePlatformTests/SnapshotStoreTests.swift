import XCTest
@testable import GamePlatform
@testable import GameSimulation

final class SnapshotStoreTests: XCTestCase {
    func testSaveAndLoadSnapshotRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = FileSnapshotStore(directory: tempDir)

        let engine = SimulationEngine(worldState: .bootstrap())
        _ = engine.run(ticks: 50)
        let snapshot = engine.makeSnapshot()

        _ = try store.save(snapshot: snapshot, name: "round_trip")
        let loaded = try store.load(name: "round_trip")

        XCTAssertEqual(snapshot, loaded)
    }
}
