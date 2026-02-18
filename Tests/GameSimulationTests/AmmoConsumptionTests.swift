import XCTest
@testable import GameSimulation

final class AmmoConsumptionTests: XCTestCase {
    func testTurretsFailToFireWithoutAmmo() {
        var entities = EntityStore()
        let hqID = entities.spawnStructure(.hq, at: GridPosition(x: 5, y: 5), health: 10, maxHealth: 10)
        _ = entities.spawnStructure(.turretMount, at: GridPosition(x: 0, y: 0))
        let enemyID = entities.spawnEnemy(at: GridPosition(x: 2, y: 0), health: 20)

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(inventories: ["ammo_light": 0]),
            threat: ThreatState(
                waveIndex: 1,
                nextWaveTick: 999,
                waveIntervalTicks: 400,
                waveDurationTicks: 200,
                waveEndsAtTick: 200,
                isWaveActive: true,
                milestoneEvery: 5,
                lastMilestoneWave: 0
            ),
            run: RunState(phase: .playing, hqEntityID: hqID),
            combat: CombatState(
                enemies: [
                    enemyID: EnemyRuntime(
                        id: enemyID,
                        archetype: .droneScout,
                        moveEveryTicks: 1,
                        baseDamage: 1,
                        rewardCurrency: 1
                    )
                ],
                basePosition: GridPosition(x: 0, y: 0),
                spawnEdgeX: 6,
                spawnYMin: 0,
                spawnYMax: 6
            )
        )

        let engine = SimulationEngine(worldState: world, systems: [CombatSystem()])
        let events = engine.step()

        XCTAssertTrue(events.contains(where: { $0.kind == .notEnoughAmmo }))
        XCTAssertEqual(engine.worldState.hqHealth, 10)
    }
}
