import XCTest
@testable import GameSimulation

final class EconomyThroughputTests: XCTestCase {
    func testRecipeTimingRequiresFullDurationBeforeOutput() {
        var entities = EntityStore()
        _ = entities.spawnStructure(.powerPlant, at: GridPosition(x: 0, y: 0))
        _ = entities.spawnStructure(.smelter, at: GridPosition(x: 1, y: 0))

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(inventories: ["ore_iron": 2]),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(worldState: world, systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])])
        _ = engine.run(ticks: 39)
        XCTAssertEqual(engine.worldState.economy.inventories["plate_iron", default: 0], 0)

        _ = engine.step()
        XCTAssertEqual(engine.worldState.economy.inventories["plate_iron", default: 0], 1)
    }

    func testMissingProductionChainsAreProducedByRecipeSystem() {
        XCTAssertGreaterThanOrEqual(
            producedAmount(structure: .assembler, inventory: ["plate_iron": 2], outputItemID: "gear", ticks: 30),
            1
        )
        XCTAssertGreaterThanOrEqual(
            producedAmount(structure: .assembler, inventory: ["plate_steel": 1, "gear": 1], outputItemID: "wall_kit", ticks: 24),
            1
        )
        XCTAssertGreaterThanOrEqual(
            producedAmount(
                structure: .assembler,
                inventory: ["plate_steel": 1, "circuit": 1, "gear": 1],
                outputItemID: "turret_core",
                ticks: 50
            ),
            1
        )
        XCTAssertGreaterThanOrEqual(
            producedAmount(
                structure: .ammoModule,
                inventory: ["power_cell": 1, "circuit": 1],
                outputItemID: "ammo_plasma",
                ticks: 60
            ),
            2
        )
    }

    private func producedAmount(
        structure: StructureType,
        inventory: [String: Int],
        outputItemID: String,
        ticks: Int
    ) -> Int {
        var entities = EntityStore()
        _ = entities.spawnStructure(.powerPlant, at: GridPosition(x: 0, y: 0))
        _ = entities.spawnStructure(structure, at: GridPosition(x: 1, y: 0))

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(inventories: inventory),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(worldState: world, systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])])
        _ = engine.run(ticks: ticks)
        return engine.worldState.economy.inventories[outputItemID, default: 0]
    }
}
