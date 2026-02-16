import XCTest
@testable import GameSimulation

final class PlacementValidationTests: XCTestCase {
    func testValidPlacementSucceedsAndSpawnsStructure() {
        let position = GridPosition(x: 8, y: 4)
        let validator = PlacementValidator()
        let world = WorldState.bootstrap()

        XCTAssertEqual(validator.canPlace(.wall, at: position, in: world), .ok)

        let engine = SimulationEngine(worldState: world)
        engine.enqueue(
            PlayerCommand(
                tick: 0,
                actor: PlayerID(1),
                payload: .placeStructure(BuildRequest(structure: .wall, position: position))
            )
        )

        _ = engine.step()

        XCTAssertTrue(
            engine.worldState.entities.structures(of: .wall).contains(where: { entity in
                entity.position.x == position.x && entity.position.y == position.y
            })
        )
    }

    func testOutOfBoundsPlacementIsRejected() {
        let validator = PlacementValidator()
        let world = WorldState.bootstrap()

        XCTAssertEqual(
            validator.canPlace(.wall, at: GridPosition(x: -1, y: 3), in: world),
            .outOfBounds
        )
    }

    func testRestrictedPlacementIsRejected() {
        let validator = PlacementValidator()
        let world = WorldState.bootstrap()

        XCTAssertEqual(
            validator.canPlace(.wall, at: world.board.basePosition, in: world),
            .restrictedZone
        )
    }

    func testPlacementThatSealsCriticalPathIsRejected() {
        let blocked = (0..<5).flatMap { x in
            (0..<5).compactMap { y -> GridPosition? in
                if y == 2 { return nil }
                return GridPosition(x: x, y: y)
            }
        }

        let board = BoardState(
            width: 5,
            height: 5,
            basePosition: GridPosition(x: 0, y: 2),
            spawnEdgeX: 4,
            spawnYMin: 2,
            spawnYMax: 2,
            blockedCells: blocked,
            restrictedCells: [GridPosition(x: 0, y: 2)],
            ramps: []
        )

        let world = WorldState(
            tick: 0,
            board: board,
            entities: EntityStore(),
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(),
            combat: CombatState(
                basePosition: GridPosition(x: 0, y: 2),
                spawnEdgeX: 4,
                spawnYMin: 2,
                spawnYMax: 2
            )
        )

        let validator = PlacementValidator()
        XCTAssertEqual(
            validator.canPlace(.wall, at: GridPosition(x: 2, y: 2), in: world),
            .blocksCriticalPath
        )
    }
}
