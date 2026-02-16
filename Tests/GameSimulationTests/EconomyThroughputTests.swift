import XCTest
@testable import GameSimulation

final class EconomyThroughputTests: XCTestCase {
    func testLogisticsStructuresIncreaseThroughput() {
        var sparseEntities = EntityStore()
        _ = sparseEntities.spawnStructure(.powerPlant, at: GridPosition(x: 0, y: 0))
        _ = sparseEntities.spawnStructure(.miner, at: GridPosition(x: 1, y: 0))
        _ = sparseEntities.spawnStructure(.smelter, at: GridPosition(x: 2, y: 0))

        let sparseWorld = WorldState(
            tick: 0,
            entities: sparseEntities,
            economy: EconomyState(inventories: ["ore_iron": 20, "ore_copper": 20, "ore_coal": 10]),
            threat: ThreatState(),
            run: RunState()
        )

        var richEntities = sparseEntities
        _ = richEntities.spawnStructure(.conveyor, at: GridPosition(x: 2, y: 1))
        _ = richEntities.spawnStructure(.conveyor, at: GridPosition(x: 3, y: 1))
        _ = richEntities.spawnStructure(.storage, at: GridPosition(x: 3, y: 2))
        _ = richEntities.spawnStructure(.storage, at: GridPosition(x: 4, y: 2))

        let richWorld = WorldState(
            tick: 0,
            entities: richEntities,
            economy: EconomyState(inventories: ["ore_iron": 20, "ore_copper": 20, "ore_coal": 10]),
            threat: ThreatState(),
            run: RunState()
        )

        let sparseEngine = SimulationEngine(worldState: sparseWorld, systems: [EconomySystem()])
        let richEngine = SimulationEngine(worldState: richWorld, systems: [EconomySystem()])

        _ = sparseEngine.step()
        _ = richEngine.step()

        let sparseIron = sparseEngine.worldState.economy.inventories["plate_iron", default: 0]
        let richIron = richEngine.worldState.economy.inventories["plate_iron", default: 0]

        XCTAssertGreaterThanOrEqual(richIron, sparseIron)
    }
}
