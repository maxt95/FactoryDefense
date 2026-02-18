import XCTest
@testable import GameSimulation

final class EntitySelectionTests: XCTestCase {
    func testSelectableEntityFindsSingleCellTurretMount() {
        var store = EntityStore()
        let turretID = store.spawnStructure(.turretMount, at: GridPosition(x: 10, y: 10))

        let selected = store.selectableEntity(at: GridPosition(x: 10, y: 10))

        XCTAssertEqual(selected?.id, turretID)
        XCTAssertEqual(selected?.structureType, .turretMount)
    }

    func testSelectableEntityPrioritizesStructuresOverEnemiesOnSameCell() {
        var store = EntityStore()
        let wallID = store.spawnStructure(.wall, at: GridPosition(x: 4, y: 4))
        _ = store.spawnEnemy(at: GridPosition(x: 4, y: 4), health: 20)

        let selected = store.selectableEntity(at: GridPosition(x: 4, y: 4))

        XCTAssertEqual(selected?.id, wallID)
        XCTAssertEqual(selected?.category, .structure)
    }

    func testSelectableEntityPrioritizesTurretMountOverWallOnSameCell() {
        var store = EntityStore()
        let wallID = store.spawnStructure(.wall, at: GridPosition(x: 6, y: 6))
        let turretID = store.spawnStructure(
            .turretMount,
            at: GridPosition(x: 6, y: 6),
            hostWallID: wallID
        )

        let selected = store.selectableEntity(at: GridPosition(x: 6, y: 6))

        XCTAssertEqual(selected?.id, turretID)
        XCTAssertEqual(selected?.structureType, .turretMount)
    }

    func testSelectableEntitiesReturnsPriorityOrderedStackForSameCell() {
        var store = EntityStore()
        let wallID = store.spawnStructure(.wall, at: GridPosition(x: 8, y: 8))
        let turretID = store.spawnStructure(.turretMount, at: GridPosition(x: 8, y: 8), hostWallID: wallID)
        let enemyID = store.spawnEnemy(at: GridPosition(x: 8, y: 8), health: 20)
        let projectileID = store.spawnProjectile(at: GridPosition(x: 8, y: 8))

        let selected = store.selectableEntities(at: GridPosition(x: 8, y: 8)).map(\.id)

        XCTAssertEqual(selected, [turretID, wallID, enemyID, projectileID])
    }

    func testSelectableEntityFallsBackToEnemyThenProjectile() {
        var store = EntityStore()
        let enemyID = store.spawnEnemy(at: GridPosition(x: 5, y: 2), health: 30)
        let projectileID = store.spawnProjectile(at: GridPosition(x: 6, y: 2))

        let selectedEnemy = store.selectableEntity(at: GridPosition(x: 5, y: 2))
        let selectedProjectile = store.selectableEntity(at: GridPosition(x: 6, y: 2))

        XCTAssertEqual(selectedEnemy?.id, enemyID)
        XCTAssertEqual(selectedEnemy?.category, .enemy)
        XCTAssertEqual(selectedProjectile?.id, projectileID)
        XCTAssertEqual(selectedProjectile?.category, .projectile)
    }
}
