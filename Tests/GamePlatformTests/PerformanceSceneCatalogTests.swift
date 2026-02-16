import XCTest
@testable import GamePlatform

final class PerformanceSceneCatalogTests: XCTestCase {
    func testLoadsPerfSceneCatalog() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Content/perf/scenes.json")

        let scenes = try PerformanceSceneCatalog().load(from: url)
        XCTAssertEqual(scenes.count, 3)
        XCTAssertTrue(scenes.contains(where: { $0.id == "high_pressure_wave" }))
    }
}
