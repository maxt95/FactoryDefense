import XCTest
@testable import GameRendering
@testable import GameSimulation

final class WhiteboxSceneBuilderTests: XCTestCase {
    func testBootstrapWorldProducesStableWhiteboxCounts() {
        let world = WorldState.bootstrap()
        let scene = WhiteboxSceneBuilder().build(from: world)

        XCTAssertEqual(scene.summary.boardCellCount, 24576)
        XCTAssertEqual(scene.summary.blockedCellCount, 0)
        XCTAssertEqual(scene.summary.restrictedCellCount, 30)
        XCTAssertEqual(scene.summary.rampCount, 0)
        XCTAssertEqual(scene.summary.structureCount, 1)
        XCTAssertEqual(scene.summary.enemyCount, 0)
        XCTAssertEqual(scene.summary.projectileCount, 0)
        XCTAssertEqual(scene.structures.count, 1)
        XCTAssertEqual(scene.entities.count, world.orePatches.count)
    }

    func testStructureMarkersIncludeTypeAndFootprint() {
        let world = WorldState.bootstrap()
        let scene = WhiteboxSceneBuilder().build(from: world)

        let hqMarkers = scene.structures.filter { $0.typeRaw == WhiteboxStructureTypeID.hq.rawValue }
        XCTAssertEqual(hqMarkers.count, 1)
        XCTAssertTrue(hqMarkers.allSatisfy { $0.footprintWidth == 5 && $0.footprintHeight == 5 })

        guard let hq = scene.structures.first(where: { $0.typeRaw == WhiteboxStructureTypeID.hq.rawValue }) else {
            return XCTFail("Expected HQ structure marker")
        }
        XCTAssertEqual(hq.anchorX, 80)
        XCTAssertEqual(hq.anchorY, 64)
        XCTAssertEqual(hq.footprintWidth, 5)
        XCTAssertEqual(hq.footprintHeight, 5)
    }

    func testEntityMarkersIncludeSubtypeForEnemyAndProjectile() {
        var world = WorldState.bootstrap()

        let scoutID = world.entities.spawnEnemy(at: GridPosition(x: 10, y: 10), health: 20)
        world.combat.enemies[scoutID] = EnemyRuntime(
            id: scoutID,
            archetype: .droneScout,
            moveEveryTicks: 8,
            baseDamage: 8,
            rewardCurrency: 1
        )

        let raiderID = world.entities.spawnEnemy(at: GridPosition(x: 11, y: 10), health: 45)
        world.combat.enemies[raiderID] = EnemyRuntime(
            id: raiderID,
            archetype: .raider,
            moveEveryTicks: 6,
            baseDamage: 12,
            rewardCurrency: 3
        )

        let heavyTurretID = world.entities.spawnStructure(
            .turretMount,
            at: GridPosition(x: 20, y: 20),
            turretDefID: "turret_mk2"
        )
        let heavyProjectileID = world.entities.spawnProjectile(at: GridPosition(x: 20, y: 20))
        world.combat.projectiles[heavyProjectileID] = ProjectileRuntime(
            id: heavyProjectileID,
            sourceTurretID: heavyTurretID,
            targetEnemyID: scoutID,
            damage: 25,
            impactTick: world.tick + 2
        )

        let plasmaTurretID = world.entities.spawnStructure(
            .turretMount,
            at: GridPosition(x: 21, y: 20),
            turretDefID: "plasma_sentinel"
        )
        let plasmaProjectileID = world.entities.spawnProjectile(at: GridPosition(x: 21, y: 20))
        world.combat.projectiles[plasmaProjectileID] = ProjectileRuntime(
            id: plasmaProjectileID,
            sourceTurretID: plasmaTurretID,
            targetEnemyID: raiderID,
            damage: 45,
            impactTick: world.tick + 2
        )

        let scene = WhiteboxSceneBuilder().build(from: world)

        let scoutMarker = scene.entities.first { $0.id == Int64(scoutID) }
        XCTAssertEqual(scoutMarker?.category, WhiteboxEntityCategory.enemy.rawValue)
        XCTAssertEqual(scoutMarker?.subtypeRaw, WhiteboxEnemyTypeID.droneScout.rawValue)

        let raiderMarker = scene.entities.first { $0.id == Int64(raiderID) }
        XCTAssertEqual(raiderMarker?.category, WhiteboxEntityCategory.enemy.rawValue)
        XCTAssertEqual(raiderMarker?.subtypeRaw, WhiteboxEnemyTypeID.raider.rawValue)

        let heavyProjectileMarker = scene.entities.first { $0.id == Int64(heavyProjectileID) }
        XCTAssertEqual(heavyProjectileMarker?.category, WhiteboxEntityCategory.projectile.rawValue)
        XCTAssertEqual(heavyProjectileMarker?.subtypeRaw, WhiteboxProjectileTypeID.heavyBallistic.rawValue)

        let plasmaProjectileMarker = scene.entities.first { $0.id == Int64(plasmaProjectileID) }
        XCTAssertEqual(plasmaProjectileMarker?.category, WhiteboxEntityCategory.projectile.rawValue)
        XCTAssertEqual(plasmaProjectileMarker?.subtypeRaw, WhiteboxProjectileTypeID.plasma.rawValue)
    }

    func testOrePatchesBecomeDeterministicResourceMarkers() {
        let world = WorldState.bootstrap(seed: 42)
        let scene = WhiteboxSceneBuilder().build(from: world)

        let resourceMarkers = scene.entities.filter {
            $0.category == WhiteboxEntityCategory.resourceNode.rawValue
        }
        XCTAssertEqual(resourceMarkers.count, world.orePatches.count)

        let expectedPatches = world.orePatches.sorted { lhs, rhs in
            if lhs.position.x != rhs.position.x {
                return lhs.position.x < rhs.position.x
            }
            if lhs.position.y != rhs.position.y {
                return lhs.position.y < rhs.position.y
            }
            return lhs.id < rhs.id
        }

        for (marker, patch) in zip(resourceMarkers, expectedPatches) {
            XCTAssertEqual(marker.x, Int32(patch.position.x))
            XCTAssertEqual(marker.y, Int32(patch.position.y))
            XCTAssertEqual(marker.subtypeRaw, WhiteboxResourceTypeID(oreType: patch.oreType).rawValue)
        }
    }
}
