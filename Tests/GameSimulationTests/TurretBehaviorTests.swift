import XCTest
@testable import GameSimulation

final class TurretBehaviorTests: XCTestCase {
    func testTurretAmmoTypesAndDamageComeFromTurretDefinitions() {
        var entities = EntityStore()
        let mk1ID = entities.spawnStructure(.turretMount, at: GridPosition(x: 0, y: 0), turretDefID: "turret_mk1")
        let mk2ID = entities.spawnStructure(.turretMount, at: GridPosition(x: 0, y: 2), turretDefID: "turret_mk2")
        let plasmaID = entities.spawnStructure(.turretMount, at: GridPosition(x: 0, y: 4), turretDefID: "plasma_sentinel")
        let enemyID = entities.spawnEnemy(at: GridPosition(x: 3, y: 2), health: 10_000)

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(
                structureInputBuffers: [
                    mk1ID: ["ammo_light": 1],
                    mk2ID: ["ammo_heavy": 1],
                    plasmaID: ["ammo_plasma": 1]
                ]
            ),
            threat: ThreatState(),
            run: RunState(),
            combat: CombatState(
                enemies: [
                    enemyID: EnemyRuntime(
                        id: enemyID,
                        archetype: .droneScout,
                        moveEveryTicks: 10,
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

        XCTAssertEqual(engine.worldState.economy.structureInputBuffers[mk1ID]?["ammo_light", default: 0] ?? 0, 0)
        XCTAssertEqual(engine.worldState.economy.structureInputBuffers[mk2ID]?["ammo_heavy", default: 0] ?? 0, 0)
        XCTAssertEqual(engine.worldState.economy.structureInputBuffers[plasmaID]?["ammo_plasma", default: 0] ?? 0, 0)

        let ammoSpentItems = Set(events.compactMap { event in
            event.kind == .ammoSpent ? event.itemID : nil
        })
        XCTAssertEqual(ammoSpentItems, Set(["ammo_light", "ammo_heavy", "ammo_plasma"]))

        let damageByTurret = Dictionary(uniqueKeysWithValues: engine.worldState.combat.projectiles.values.map {
            ($0.sourceTurretID, $0.damage)
        })
        XCTAssertEqual(damageByTurret[mk1ID], 12)
        XCTAssertEqual(damageByTurret[mk2ID], 25)
        XCTAssertEqual(damageByTurret[plasmaID], 45)
    }

    func testTurretFireRatesControlShotCadence() {
        let gattlingShots = shotsFired(turretDefID: "gattling_tower", ammoItemID: "ammo_light", ticks: 30)
        let plasmaShots = shotsFired(turretDefID: "plasma_sentinel", ammoItemID: "ammo_plasma", ticks: 30)

        XCTAssertEqual(gattlingShots, 6)
        XCTAssertEqual(plasmaShots, 2)
        XCTAssertGreaterThan(gattlingShots, plasmaShots)
    }

    private func shotsFired(turretDefID: String, ammoItemID: String, ticks: Int) -> Int {
        var entities = EntityStore()
        let turretID = entities.spawnStructure(.turretMount, at: GridPosition(x: 0, y: 0), turretDefID: turretDefID)
        let enemyID = entities.spawnEnemy(at: GridPosition(x: 3, y: 0), health: 10_000)

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(structureInputBuffers: [turretID: [ammoItemID: 100]]),
            threat: ThreatState(),
            run: RunState(),
            combat: CombatState(
                enemies: [
                    enemyID: EnemyRuntime(
                        id: enemyID,
                        archetype: .droneScout,
                        moveEveryTicks: 10,
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
        let events = engine.run(ticks: ticks)
        return events.filter { $0.kind == .projectileFired }.count
    }
}
