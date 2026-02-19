import XCTest
@testable import GameSimulation

final class EconomyThroughputTests: XCTestCase {
    func testRecipeTimingRequiresFullDurationBeforeOutput() {
        var entities = EntityStore()
        _ = entities.spawnStructure(.powerPlant, at: GridPosition(x: 0, y: 0))
        let smelterID = entities.spawnStructure(.smelter, at: GridPosition(x: 1, y: 0))

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(
                pinnedRecipeByStructure: [smelterID: "smelt_iron"],
                structureInputBuffers: [smelterID: ["ore_iron": 2]]
            ),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(worldState: world, systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])])
        _ = engine.run(ticks: 39)
        XCTAssertEqual(engine.worldState.economy.structureOutputBuffers[smelterID]?["plate_iron", default: 0] ?? 0, 0)

        _ = engine.step()
        XCTAssertEqual(engine.worldState.economy.structureOutputBuffers[smelterID]?["plate_iron", default: 0] ?? 0, 1)
    }

    func testMissingProductionChainsAreProducedByRecipeSystem() {
        XCTAssertGreaterThanOrEqual(
            producedAmount(
                structure: .assembler,
                recipeID: "forge_gear",
                inventory: ["plate_iron": 2],
                outputItemID: "gear",
                ticks: 30
            ),
            1
        )
        XCTAssertGreaterThanOrEqual(
            producedAmount(
                structure: .assembler,
                recipeID: "craft_wall_kit",
                inventory: ["plate_steel": 1, "gear": 1],
                outputItemID: "wall_kit",
                ticks: 24
            ),
            1
        )
        XCTAssertGreaterThanOrEqual(
            producedAmount(
                structure: .assembler,
                recipeID: "craft_turret_core",
                inventory: ["plate_steel": 1, "circuit": 1, "gear": 1],
                outputItemID: "turret_core",
                ticks: 50
            ),
            1
        )
        XCTAssertGreaterThanOrEqual(
            producedAmount(
                structure: .ammoModule,
                recipeID: "craft_ammo_plasma",
                inventory: ["power_cell": 1, "circuit": 1],
                outputItemID: "ammo_plasma",
                ticks: 60
            ),
            2
        )
    }

    private func producedAmount(
        structure: StructureType,
        recipeID: String,
        inventory: [String: Int],
        outputItemID: String,
        ticks: Int
    ) -> Int {
        var entities = EntityStore()
        _ = entities.spawnStructure(.powerPlant, at: GridPosition(x: 0, y: 0))
        let structureID = entities.spawnStructure(structure, at: GridPosition(x: 1, y: 0))

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(
                pinnedRecipeByStructure: [structureID: recipeID],
                structureInputBuffers: [structureID: inventory]
            ),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(worldState: world, systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])])
        _ = engine.run(ticks: ticks)
        return engine.worldState.economy.structureOutputBuffers[structureID]?[outputItemID, default: 0] ?? 0
    }

    func testPinnedRecipeDoesNotFallbackToOtherOutputs() {
        var entities = EntityStore()
        _ = entities.spawnStructure(.powerPlant, at: GridPosition(x: 0, y: 0))
        let assemblerID = entities.spawnStructure(.assembler, at: GridPosition(x: 1, y: 0))

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(
                pinnedRecipeByStructure: [assemblerID: "craft_wall_kit"],
                structureInputBuffers: [assemblerID: ["plate_iron": 10]]
            ),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(worldState: world, systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])])
        _ = engine.run(ticks: 300)

        XCTAssertEqual(engine.worldState.economy.structureOutputBuffers[assemblerID]?["gear", default: 0] ?? 0, 0)
        XCTAssertEqual(engine.worldState.economy.structureOutputBuffers[assemblerID]?["wall_kit", default: 0] ?? 0, 0)
    }
}
