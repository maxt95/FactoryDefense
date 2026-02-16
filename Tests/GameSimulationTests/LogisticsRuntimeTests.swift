import XCTest
@testable import GameSimulation

final class LogisticsRuntimeTests: XCTestCase {
    func testConveyorCarriesOutputToNeighborInputBuffer() {
        var entities = EntityStore()
        _ = entities.spawnStructure(.powerPlant, at: GridPosition(x: 0, y: 1))
        _ = entities.spawnStructure(.smelter, at: GridPosition(x: 0, y: 0))
        _ = entities.spawnStructure(.conveyor, at: GridPosition(x: 1, y: 0))
        let assemblerID = entities.spawnStructure(.assembler, at: GridPosition(x: 2, y: 0))

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(inventories: ["ore_iron": 2], structureInputBuffers: [assemblerID: [:]]),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(
            worldState: world,
            systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])]
        )

        _ = engine.run(ticks: 50)

        XCTAssertEqual(engine.worldState.economy.inventories["plate_iron", default: 0], 0)
        XCTAssertEqual(engine.worldState.economy.structureInputBuffers[assemblerID]?["plate_iron", default: 0], 1)
    }

    func testConnectedConveyorBackpressureBlocksOutputDrain() {
        var entities = EntityStore()
        _ = entities.spawnStructure(.powerPlant, at: GridPosition(x: 0, y: 1))
        let ammoModuleID = entities.spawnStructure(.ammoModule, at: GridPosition(x: 0, y: 0))
        let conveyorID = entities.spawnStructure(.conveyor, at: GridPosition(x: 1, y: 0))

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(inventories: ["plate_iron": 8]),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(
            worldState: world,
            systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])]
        )

        _ = engine.run(ticks: 200)

        XCTAssertEqual(engine.worldState.economy.inventories["ammo_light", default: 0], 0)
        XCTAssertEqual(engine.worldState.economy.structureOutputBuffers[ammoModuleID]?["ammo_light", default: 0], 7)
        XCTAssertEqual(engine.worldState.economy.conveyorPayloadByEntity[conveyorID]?.itemID, "ammo_light")
    }

    func testTurretConsumesLocalBufferAmmoBeforeGlobalInventory() {
        var entities = EntityStore()
        let turretID = entities.spawnStructure(.turretMount, at: GridPosition(x: 0, y: 0), turretDefID: "turret_mk1")
        let enemyID = entities.spawnEnemy(at: GridPosition(x: 2, y: 0), health: 100)

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(
                inventories: ["ammo_light": 1],
                structureInputBuffers: [turretID: ["ammo_light": 1]]
            ),
            threat: ThreatState(),
            run: RunState(),
            combat: CombatState(
                enemies: [
                    enemyID: EnemyRuntime(
                        id: enemyID,
                        archetype: .scout,
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

        XCTAssertTrue(events.contains(where: { $0.kind == .projectileFired }))
        XCTAssertEqual(engine.worldState.economy.inventories["ammo_light", default: 0], 1)
        XCTAssertEqual(engine.worldState.economy.structureInputBuffers[turretID]?["ammo_light", default: 0], 0)
    }
}
