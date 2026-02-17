import XCTest
@testable import GameSimulation

final class BootstrapInventoryTests: XCTestCase {
    func testBootstrapStartingResourcesMatchDifficulty() {
        let easy = WorldState.bootstrap(difficulty: .easy, seed: 1).economy.inventories
        let normal = WorldState.bootstrap(difficulty: .normal, seed: 1).economy.inventories
        let hard = WorldState.bootstrap(difficulty: .hard, seed: 1).economy.inventories

        XCTAssertEqual(easy["ore_iron", default: 0], 30)
        XCTAssertEqual(easy["plate_iron", default: 0], 18)
        XCTAssertEqual(easy["plate_copper", default: 0], 8)
        XCTAssertEqual(easy["plate_steel", default: 0], 10)
        XCTAssertEqual(easy["gear", default: 0], 5)
        XCTAssertEqual(easy["circuit", default: 0], 5)
        XCTAssertEqual(easy["turret_core", default: 0], 4)
        XCTAssertEqual(easy["wall_kit", default: 0], 80)
        XCTAssertEqual(easy["ammo_light", default: 0], 24)

        XCTAssertEqual(normal["ore_iron", default: 0], 20)
        XCTAssertEqual(normal["plate_iron", default: 0], 14)
        XCTAssertEqual(normal["plate_copper", default: 0], 6)
        XCTAssertEqual(normal["plate_steel", default: 0], 8)
        XCTAssertEqual(normal["gear", default: 0], 4)
        XCTAssertEqual(normal["circuit", default: 0], 4)
        XCTAssertEqual(normal["turret_core", default: 0], 4)
        XCTAssertEqual(normal["wall_kit", default: 0], 80)
        XCTAssertEqual(normal["ammo_light", default: 0], 16)

        XCTAssertEqual(hard["ore_iron", default: 0], 12)
        XCTAssertEqual(hard["plate_iron", default: 0], 10)
        XCTAssertEqual(hard["plate_copper", default: 0], 4)
        XCTAssertEqual(hard["plate_steel", default: 0], 8)
        XCTAssertEqual(hard["gear", default: 0], 3)
        XCTAssertEqual(hard["circuit", default: 0], 2)
        XCTAssertEqual(hard["turret_core", default: 0], 4)
        XCTAssertEqual(hard["wall_kit", default: 0], 80)
        XCTAssertEqual(hard["ammo_light", default: 0], 8)
    }

    func testBootstrapStartsWithHQOnlyAndGracePhase() {
        let world = WorldState.bootstrap(difficulty: .normal, seed: 7)

        XCTAssertEqual(world.entities.structures(of: .hq).count, 1)
        XCTAssertEqual(world.entities.all.filter { $0.category == .structure && $0.structureType != .hq }.count, 0)
        XCTAssertEqual(world.run.phase, .gracePeriod)
        XCTAssertEqual(world.threat.graceEndsAtTick, 2_400)
        XCTAssertEqual(world.threat.waveGapBaseTicks, 1_800)
    }

    func testBootstrapSeedDeterminismForRing0Patches() {
        let first = WorldState.bootstrap(difficulty: .normal, seed: 99)
        let second = WorldState.bootstrap(difficulty: .normal, seed: 99)
        let third = WorldState.bootstrap(difficulty: .normal, seed: 100)

        XCTAssertEqual(first.orePatches, second.orePatches)
        XCTAssertNotEqual(first.orePatches, third.orePatches)
    }

    func testNoEnemiesSpawnDuringGracePeriod() {
        let engine = SimulationEngine(
            worldState: .bootstrap(difficulty: .hard, seed: 11),
            systems: [WaveSystem(enableRaids: false)]
        )
        let events = engine.run(ticks: 600)

        XCTAssertFalse(events.contains(where: { $0.kind == .enemySpawned }))
        XCTAssertEqual(engine.worldState.run.phase, .gracePeriod)
    }
}
