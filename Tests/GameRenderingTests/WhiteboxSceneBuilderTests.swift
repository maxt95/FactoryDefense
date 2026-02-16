import XCTest
@testable import GameRendering
@testable import GameSimulation

final class WhiteboxSceneBuilderTests: XCTestCase {
    func testBootstrapWorldProducesStableWhiteboxCounts() {
        let world = WorldState.bootstrap()
        let scene = WhiteboxSceneBuilder().build(from: world)

        XCTAssertEqual(scene.summary.boardCellCount, 6144)
        XCTAssertEqual(scene.summary.blockedCellCount, 0)
        XCTAssertEqual(scene.summary.restrictedCellCount, 9)
        XCTAssertEqual(scene.summary.rampCount, 3)
        XCTAssertEqual(scene.summary.structureCount, 1)
        XCTAssertEqual(scene.summary.enemyCount, 0)
        XCTAssertEqual(scene.summary.projectileCount, 0)
        XCTAssertEqual(scene.structures.count, 1)
        XCTAssertEqual(scene.entities.count, 0)
    }

    func testStructureMarkersIncludeTypeAndFootprint() {
        let world = WorldState.bootstrap()
        let scene = WhiteboxSceneBuilder().build(from: world)

        let hqMarkers = scene.structures.filter { $0.typeRaw == WhiteboxStructureTypeID.hq.rawValue }
        XCTAssertEqual(hqMarkers.count, 1)
        XCTAssertTrue(hqMarkers.allSatisfy { $0.footprintWidth == 2 && $0.footprintHeight == 2 })

        guard let hq = scene.structures.first(where: { $0.typeRaw == WhiteboxStructureTypeID.hq.rawValue }) else {
            return XCTFail("Expected HQ structure marker")
        }
        XCTAssertEqual(hq.anchorX, 40)
        XCTAssertEqual(hq.anchorY, 32)
        XCTAssertEqual(hq.footprintWidth, 2)
        XCTAssertEqual(hq.footprintHeight, 2)
    }
}
