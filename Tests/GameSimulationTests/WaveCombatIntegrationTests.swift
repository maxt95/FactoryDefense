import XCTest
@testable import GameSimulation

final class WaveCombatIntegrationTests: XCTestCase {
    func testWaveSpawnsEnemiesAndTurretsFireProjectiles() {
        var world = WorldState.bootstrap()
        world.economy.inventories["ammo_light"] = 400
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
                CombatSystem(turretRange: 14, projectileDamage: 30),
                ProjectileSystem()
            ]
        )

        let events = engine.run(ticks: 220)

        XCTAssertTrue(events.contains(where: { $0.kind == .enemySpawned }))
        XCTAssertTrue(events.contains(where: { $0.kind == .projectileFired }))
        XCTAssertTrue(events.contains(where: { $0.kind == .enemyDestroyed }))
        XCTAssertGreaterThan(engine.worldState.economy.currency, 0)
    }

    func testEnemyReachingBaseDamagesIntegrity() {
        var entities = EntityStore()
        let enemyID = entities.spawnEnemy(at: GridPosition(x: 1, y: 0), health: 10)

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(baseIntegrity: 8),
            combat: CombatState(
                enemies: [
                    enemyID: EnemyRuntime(
                        id: enemyID,
                        archetype: .scout,
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
        XCTAssertEqual(engine.worldState.run.baseIntegrity, 6)
        XCTAssertTrue(engine.worldState.combat.enemies.isEmpty)
    }
}
