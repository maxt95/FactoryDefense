import XCTest
@testable import GameSimulation

final class BuildCostEnforcementTests: XCTestCase {
    func testPlacementRejectedWhenResourcesAreInsufficient() {
        var world = WorldState.bootstrap()
        world.economy.inventories = [:]

        let engine = SimulationEngine(worldState: world, systems: [CommandSystem()])
        engine.enqueue(
            PlayerCommand(
                tick: 0,
                actor: PlayerID(1),
                payload: .placeStructure(BuildRequest(structure: .wall, position: GridPosition(x: 10, y: 10)))
            )
        )

        let events = engine.step()
        XCTAssertTrue(
            events.contains(where: {
                $0.kind == .placementRejected && $0.value == PlacementResult.insufficientResources.rawValue
            })
        )
        XCTAssertTrue(engine.worldState.entities.structures(of: .wall).isEmpty)
    }

    func testPlacementConsumesExactBuildCostOnce() {
        var world = WorldState.bootstrap()
        world.economy.inventories = ["turret_core": 1, "plate_steel": 2]

        let engine = SimulationEngine(worldState: world, systems: [CommandSystem()])
        engine.enqueue(
            PlayerCommand(
                tick: 0,
                actor: PlayerID(1),
                payload: .placeStructure(BuildRequest(structure: .turretMount, position: GridPosition(x: 10, y: 10)))
            )
        )

        _ = engine.step()

        XCTAssertEqual(engine.worldState.economy.inventories["turret_core", default: 0], 0)
        XCTAssertEqual(engine.worldState.economy.inventories["plate_steel", default: 0], 0)
        XCTAssertEqual(engine.worldState.entities.structures(of: .turretMount).count, 3)
    }
}
