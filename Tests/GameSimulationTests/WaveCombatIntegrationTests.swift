import XCTest
@testable import GameSimulation

final class WaveCombatIntegrationTests: XCTestCase {
    func testWaveSpawnsEnemiesAndTurretsFireProjectiles() {
        var world = WorldState.bootstrap()
        let turretID = world.entities.spawnStructure(.turretMount, at: GridPosition(x: 50, y: 32))
        world.economy.structureInputBuffers[turretID] = ["ammo_light": 400]
        world.rebuildAggregatedInventory()
        world.run.phase = .playing
        world.threat = ThreatState(
            waveIndex: 0,
            nextWaveTick: 0,
            waveIntervalTicks: 999,
            waveDurationTicks: 180,
            waveEndsAtTick: nil,
            isWaveActive: false,
            raidCooldownUntilTick: 999_999,
            milestoneEvery: 5,
            lastMilestoneWave: 0
        )

        let engine = SimulationEngine(
            worldState: world,
            systems: [
                WaveSystem(enableRaids: false),
                EnemyMovementSystem(),
                CombatSystem(turretRange: 200, projectileDamage: 30),
                ProjectileSystem()
            ]
        )

        let events = engine.run(ticks: 500)

        XCTAssertTrue(events.contains(where: { $0.kind == .enemySpawned }))
        XCTAssertTrue(events.contains(where: { $0.kind == .projectileFired }))
        XCTAssertTrue(events.contains(where: { $0.kind == .enemyDestroyed }))
        XCTAssertGreaterThan(engine.worldState.economy.currency, 0)
    }

    func testEnemyReachingBaseDamagesIntegrity() {
        let board = BoardState(
            width: 6,
            height: 6,
            basePosition: GridPosition(x: 0, y: 0),
            spawnEdgeX: 5,
            spawnYMin: 0,
            spawnYMax: 2,
            blockedCells: [],
            restrictedCells: [],
            ramps: []
        )
        var entities = EntityStore()
        let hqID = entities.spawnStructure(.hq, at: GridPosition(x: 1, y: 1), health: 8, maxHealth: 8)
        let enemyID = entities.spawnEnemy(at: GridPosition(x: 0, y: 0), health: 10)

        let world = WorldState(
            tick: 0,
            board: board,
            entities: entities,
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(phase: .playing, hqEntityID: hqID),
            combat: CombatState(
                enemies: [
                    enemyID: EnemyRuntime(
                        id: enemyID,
                        archetype: .droneScout,
                        moveEveryTicks: 1,
                        baseDamage: 2,
                        rewardCurrency: 1
                    )
                ],
                basePosition: GridPosition(x: 0, y: 0),
                spawnEdgeX: 3,
                spawnYMin: 0,
                spawnYMax: 2
            )
        )

        let engine = SimulationEngine(worldState: world, systems: [EnemyMovementSystem()])
        let events = engine.run(ticks: 2)

        XCTAssertTrue(events.contains(where: { $0.kind == .enemyReachedBase }))
        XCTAssertEqual(engine.worldState.hqHealth, 6)
        XCTAssertTrue(engine.worldState.combat.enemies.isEmpty)
    }

    func testHQZeroHealthEmitsGameOverAndHaltsSystems() {
        let board = BoardState(
            width: 6,
            height: 6,
            basePosition: GridPosition(x: 0, y: 0),
            spawnEdgeX: 5,
            spawnYMin: 0,
            spawnYMax: 2,
            blockedCells: [],
            restrictedCells: [],
            ramps: []
        )
        var entities = EntityStore()
        let hqID = entities.spawnStructure(.hq, at: GridPosition(x: 1, y: 1), health: 2, maxHealth: 2)
        let enemyID = entities.spawnEnemy(at: GridPosition(x: 0, y: 0), health: 10)

        let world = WorldState(
            tick: 0,
            board: board,
            entities: entities,
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(phase: .playing, hqEntityID: hqID),
            combat: CombatState(
                enemies: [
                    enemyID: EnemyRuntime(
                        id: enemyID,
                        archetype: .droneScout,
                        moveEveryTicks: 1,
                        baseDamage: 2,
                        rewardCurrency: 1
                    )
                ],
                basePosition: GridPosition(x: 0, y: 0),
                spawnEdgeX: 3,
                spawnYMin: 0,
                spawnYMax: 2
            )
        )

        let engine = SimulationEngine(worldState: world, systems: [EnemyMovementSystem()])
        let firstStepEvents = engine.step()
        let secondStepEvents = engine.step()

        XCTAssertTrue(firstStepEvents.contains(where: { $0.kind == .gameOver }))
        XCTAssertEqual(engine.worldState.run.phase, .gameOver)
        XCTAssertTrue(secondStepEvents.isEmpty)
    }
}
