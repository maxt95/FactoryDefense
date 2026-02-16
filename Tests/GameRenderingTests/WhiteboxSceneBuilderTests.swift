import XCTest
@testable import GameRendering
@testable import GameSimulation

final class WhiteboxSceneBuilderTests: XCTestCase {
    func testBootstrapWorldProducesStableWhiteboxCounts() {
        let world = WorldState.bootstrap()
        let scene = WhiteboxSceneBuilder().build(from: world)

        XCTAssertEqual(scene.summary.boardCellCount, 280)
        XCTAssertEqual(scene.summary.blockedCellCount, 0)
        XCTAssertEqual(scene.summary.restrictedCellCount, 5)
        XCTAssertEqual(scene.summary.rampCount, 3)
        XCTAssertEqual(scene.summary.structureCount, 6)
        XCTAssertEqual(scene.summary.enemyCount, 0)
        XCTAssertEqual(scene.summary.projectileCount, 0)
    }
}
