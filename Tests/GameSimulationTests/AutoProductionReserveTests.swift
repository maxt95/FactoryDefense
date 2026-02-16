import XCTest
@testable import GameSimulation

final class AutoProductionReserveTests: XCTestCase {
    func testBootstrapAutoProductionKeepsConstructionStockAvailable() {
        let engine = SimulationEngine(worldState: .bootstrap(), systems: [EconomySystem()])
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
