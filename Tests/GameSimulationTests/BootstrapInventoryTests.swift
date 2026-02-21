import XCTest
@testable import GameSimulation

final class BootstrapInventoryTests: XCTestCase {
    func testBootstrapStartingResourcesMatchDifficulty() {
        let easy = WorldState.bootstrap(difficulty: .easy, seed: 1).economy.inventories
        let normal = WorldState.bootstrap(difficulty: .normal, seed: 1).economy.inventories
        let hard = WorldState.bootstrap(difficulty: .hard, seed: 1).economy.inventories

        // Easy
        XCTAssertEqual(easy["ore_iron", default: 0], 70)
        XCTAssertEqual(easy["ore_copper", default: 0], 48)
        XCTAssertEqual(easy["ore_coal", default: 0], 24)
        XCTAssertEqual(easy["plate_iron", default: 0], 50)
        XCTAssertEqual(easy["plate_copper", default: 0], 25)
        XCTAssertEqual(easy["plate_steel", default: 0], 50)
        XCTAssertEqual(easy["gear", default: 0], 18)
        XCTAssertEqual(easy["circuit", default: 0], 18)
        XCTAssertEqual(easy["turret_core", default: 0], 8)
        XCTAssertEqual(easy["wall_kit", default: 0], 220)
        XCTAssertEqual(easy["ammo_light", default: 0], 60)

        // Normal
        XCTAssertEqual(normal["ore_iron", default: 0], 50)
        XCTAssertEqual(normal["ore_copper", default: 0], 32)
        XCTAssertEqual(normal["ore_coal", default: 0], 16)
        XCTAssertEqual(normal["plate_iron", default: 0], 40)
        XCTAssertEqual(normal["plate_copper", default: 0], 20)
        XCTAssertEqual(normal["plate_steel", default: 0], 40)
        XCTAssertEqual(normal["gear", default: 0], 14)
        XCTAssertEqual(normal["circuit", default: 0], 14)
        XCTAssertEqual(normal["turret_core", default: 0], 6)
        XCTAssertEqual(normal["wall_kit", default: 0], 180)
        XCTAssertEqual(normal["ammo_light", default: 0], 48)

        // Hard
        XCTAssertEqual(hard["ore_iron", default: 0], 32)
        XCTAssertEqual(hard["ore_copper", default: 0], 22)
        XCTAssertEqual(hard["ore_coal", default: 0], 12)
        XCTAssertEqual(hard["plate_iron", default: 0], 28)
        XCTAssertEqual(hard["plate_copper", default: 0], 14)
        XCTAssertEqual(hard["plate_steel", default: 0], 30)
        XCTAssertEqual(hard["gear", default: 0], 8)
        XCTAssertEqual(hard["circuit", default: 0], 8)
        XCTAssertEqual(hard["turret_core", default: 0], 5)
        XCTAssertEqual(hard["wall_kit", default: 0], 150)
        XCTAssertEqual(hard["ammo_light", default: 0], 24)
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
            systems: [WaveSystem()]
        )
        let events = engine.run(ticks: 600)

        XCTAssertFalse(events.contains(where: { $0.kind == .enemySpawned }))
        XCTAssertEqual(engine.worldState.run.phase, .gracePeriod)
    }
}
