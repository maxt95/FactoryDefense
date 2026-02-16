import XCTest
@testable import GameRendering
@testable import GameSimulation

final class WhiteboxSceneBuilderTests: XCTestCase {
    func testBootstrapWorldProducesStableWhiteboxCounts() {
        let world = WorldState.bootstrap()
        let scene = WhiteboxSceneBuilder().build(from: world)

        XCTAssertEqual(scene.summary.boardCellCount, 6144)
        XCTAssertEqual(scene.summary.blockedCellCount, 0)
        XCTAssertEqual(scene.summary.restrictedCellCount, 5)
        XCTAssertEqual(scene.summary.rampCount, 3)
        XCTAssertEqual(scene.summary.structureCount, 6)
        XCTAssertEqual(scene.summary.enemyCount, 0)
        XCTAssertEqual(scene.summary.projectileCount, 0)
        XCTAssertEqual(scene.structures.count, 6)
        XCTAssertEqual(scene.entities.count, 0)
    }

    func testStructureMarkersIncludeTypeAndFootprint() {
        let world = WorldState.bootstrap()
        let scene = WhiteboxSceneBuilder().build(from: world)

        let turretMarkers = scene.structures.filter { $0.typeRaw == WhiteboxStructureTypeID.turretMount.rawValue }
        XCTAssertEqual(turretMarkers.count, 2)
        XCTAssertTrue(turretMarkers.allSatisfy { $0.footprintWidth == 2 && $0.footprintHeight == 2 })

        guard let powerPlant = scene.structures.first(where: { $0.typeRaw == WhiteboxStructureTypeID.powerPlant.rawValue }) else {
            return XCTFail("Expected power plant structure marker")
        }
        XCTAssertEqual(powerPlant.anchorX, 39)
        XCTAssertEqual(powerPlant.anchorY, 30)
        XCTAssertEqual(powerPlant.footprintWidth, 2)
        XCTAssertEqual(powerPlant.footprintHeight, 2)
    }
}
