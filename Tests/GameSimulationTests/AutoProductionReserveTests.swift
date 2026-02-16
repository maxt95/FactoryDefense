import XCTest
@testable import GameSimulation

final class AutoProductionReserveTests: XCTestCase {
    func testAutoProductionDoesNotDropBelowConstructionReserve() {
        var entities = EntityStore()
        _ = entities.spawnStructure(.powerPlant, at: GridPosition(x: 0, y: 0))
        _ = entities.spawnStructure(.assembler, at: GridPosition(x: 1, y: 0))
        _ = entities.spawnStructure(.ammoModule, at: GridPosition(x: 2, y: 0))

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(
                inventories: EconomySystem.defaultMinimumConstructionStock.merging(
                    ["plate_steel": 10, "gear": 10, "circuit": 10, "ammo_light": 20]
                ) { _, new in new }
            ),
            threat: ThreatState(),
            run: RunState()
        )
        let engine = SimulationEngine(worldState: world, systems: [EconomySystem()])
        _ = engine.run(ticks: 600)

        for (itemID, minimum) in EconomySystem.defaultMinimumConstructionStock {
            XCTAssertGreaterThanOrEqual(
                engine.worldState.economy.inventories[itemID, default: 0],
                minimum,
                "Expected \(itemID) to remain above reserve floor."
            )
        }
    }
}
