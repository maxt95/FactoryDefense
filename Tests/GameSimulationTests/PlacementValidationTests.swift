import XCTest
@testable import GameSimulation

final class PlacementValidationTests: XCTestCase {
    func testValidPlacementSucceedsAndSpawnsStructure() {
        let position = GridPosition(x: 48, y: 32)
        let validator = PlacementValidator()
        var world = WorldState.bootstrap()
        world.economy.inventories["wall_kit"] = 10

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

    func testTurretMountWithoutWallIsRejected() {
        let validator = PlacementValidator()
        let world = WorldState.bootstrap()

        XCTAssertEqual(
            validator.canPlace(.turretMount, at: GridPosition(x: 0, y: 0), in: world),
            .invalidTurretMountPlacement
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

    func testTwoByTwoPlacementTouchingRestrictedCellIsRejected() {
        let board = BoardState(
            width: 6,
            height: 6,
            basePosition: GridPosition(x: 0, y: 0),
            spawnEdgeX: 5,
            spawnYMin: 0,
            spawnYMax: 0,
            blockedCells: [],
            restrictedCells: [GridPosition(x: 1, y: 1)],
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
                basePosition: GridPosition(x: 0, y: 0),
                spawnEdgeX: 5,
                spawnYMin: 0,
                spawnYMax: 0
            )
        )
        let validator = PlacementValidator()

        XCTAssertEqual(
            validator.canPlace(.hq, at: GridPosition(x: 2, y: 2), in: world),
            .restrictedZone
        )
    }

    func testTwoByTwoPlacementTouchingOccupiedCellIsRejected() {
        let board = BoardState(
            width: 6,
            height: 6,
            basePosition: GridPosition(x: 0, y: 0),
            spawnEdgeX: 5,
            spawnYMin: 0,
            spawnYMax: 0,
            blockedCells: [],
            restrictedCells: [],
            ramps: []
        )
        var entities = EntityStore()
        _ = entities.spawnStructure(.wall, at: GridPosition(x: 1, y: 1))
        let world = WorldState(
            tick: 0,
            board: board,
            entities: entities,
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(),
            combat: CombatState(
                basePosition: GridPosition(x: 0, y: 0),
                spawnEdgeX: 5,
                spawnYMin: 0,
                spawnYMax: 0
            )
        )
        let validator = PlacementValidator()

        XCTAssertEqual(
            validator.canPlace(.hq, at: GridPosition(x: 2, y: 2), in: world),
            .occupied
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

    func testTurretMountRequiresHostWallInCorridorScenario() {
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
            validator.canPlace(.turretMount, at: GridPosition(x: 2, y: 3), in: world),
            .invalidTurretMountPlacement
        )
    }

    func testNearEdgePlacementTriggersExpansionAndSucceeds() {
        var world = WorldState.bootstrap()
        world.economy.inventories["wall_kit"] = 10
        let position = GridPosition(x: world.board.width - 2, y: world.board.basePosition.y)
        let initialWidth = world.board.width
        let initialHeight = world.board.height
        let initialBase = world.board.basePosition

        let engine = SimulationEngine(worldState: world)
        engine.enqueue(
            PlayerCommand(
                tick: 0,
                actor: PlayerID(1),
                payload: .placeStructure(BuildRequest(structure: .wall, position: position))
            )
        )

        _ = engine.step()

        XCTAssertEqual(engine.worldState.board.width, initialWidth + 16)
        XCTAssertEqual(engine.worldState.board.height, initialHeight)
        XCTAssertEqual(engine.worldState.board.basePosition, initialBase)
        XCTAssertTrue(
            engine.worldState.entities.structures(of: .wall).contains(where: { entity in
                entity.position.x == position.x && entity.position.y == position.y
            })
        )
    }

    func testPlacementRejectionAtBoardCapWhenExpansionIsRequired() {
        let board = BoardState(
            width: BoardGrowthPolicy.maxWidth,
            height: BoardGrowthPolicy.maxHeight,
            basePosition: GridPosition(x: 40, y: 32),
            spawnEdgeX: 56,
            spawnYMin: 27,
            spawnYMax: 36,
            blockedCells: [],
            restrictedCells: [GridPosition(x: 40, y: 32)],
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
                basePosition: board.basePosition,
                spawnEdgeX: board.spawnEdgeX,
                spawnYMin: board.spawnYMin,
                spawnYMax: board.spawnYMax
            )
        )

        let engine = SimulationEngine(worldState: world, systems: [CommandSystem()])
        engine.enqueue(
            PlayerCommand(
                tick: 0,
                actor: PlayerID(1),
                payload: .placeStructure(BuildRequest(structure: .wall, position: GridPosition(x: 511, y: 128)))
            )
        )

        let events = engine.step()

        XCTAssertTrue(events.contains(where: {
            $0.kind == .placementRejected && $0.value == PlacementResult.outOfBounds.rawValue
        }))
        XCTAssertTrue(engine.worldState.entities.structures(of: .wall).isEmpty)
        XCTAssertEqual(engine.worldState.board.width, BoardGrowthPolicy.maxWidth)
        XCTAssertEqual(engine.worldState.board.height, BoardGrowthPolicy.maxHeight)
    }

    func testLeftTopExpansionShiftsWorldAndPreservesPath() {
        var world = WorldState.bootstrap()
        world.economy.inventories["wall_kit"] = 10
        let originalBase = world.board.basePosition
        let originalSpawnEdgeX = world.board.spawnEdgeX
        let originalSpawnYMin = world.board.spawnYMin
        let originalSpawnYMax = world.board.spawnYMax

        let engine = SimulationEngine(worldState: world)
        engine.enqueue(
            PlayerCommand(
                tick: 0,
                actor: PlayerID(1),
                payload: .placeStructure(BuildRequest(structure: .wall, position: GridPosition(x: 0, y: 0)))
            )
        )

        _ = engine.step()
        let finalWorld = engine.worldState

        XCTAssertEqual(finalWorld.board.width, 112)
        XCTAssertEqual(finalWorld.board.height, 80)
        XCTAssertEqual(finalWorld.board.basePosition, originalBase.translated(byX: 16, byY: 16))
        XCTAssertEqual(finalWorld.board.spawnEdgeX, originalSpawnEdgeX + 16)
        XCTAssertEqual(finalWorld.board.spawnYMin, originalSpawnYMin + 16)
        XCTAssertEqual(finalWorld.board.spawnYMax, originalSpawnYMax + 16)
        XCTAssertTrue(
            finalWorld.entities.structures(of: .wall).contains(where: { entity in
                entity.position.x == 16 && entity.position.y == 16
            })
        )

        let validator = PlacementValidator()
        let map = validator.navigationMap(for: finalWorld)
        guard let spawn = finalWorld.board.spawnPositions().first else {
            XCTFail("Expected at least one spawn position")
            return
        }
        let path = Pathfinder().findPath(on: map, from: spawn, to: finalWorld.board.basePosition)
        XCTAssertNotNil(path)
    }

    func testMinerPlacementRequiresAdjacentUnboundPatch() {
        let board = BoardState(
            width: 12,
            height: 12,
            basePosition: GridPosition(x: 0, y: 0),
            spawnEdgeX: 11,
            spawnYMin: 0,
            spawnYMax: 0,
            blockedCells: [],
            restrictedCells: [GridPosition(x: 4, y: 4)],
            ramps: []
        )
        let world = WorldState(
            tick: 0,
            board: board,
            entities: EntityStore(),
            orePatches: [
                OrePatch(
                    id: 7,
                    oreType: "ore_iron",
                    richness: .normal,
                    position: GridPosition(x: 4, y: 4),
                    totalOre: 500,
                    remainingOre: 500
                )
            ],
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(),
            combat: CombatState(basePosition: GridPosition(x: 0, y: 0), spawnEdgeX: 11, spawnYMin: 0, spawnYMax: 0)
        )

        let validator = PlacementValidator()
        XCTAssertEqual(
            validator.canPlace(.miner, at: GridPosition(x: 5, y: 4), in: world),
            .ok
        )
        XCTAssertEqual(
            validator.canPlace(.miner, at: GridPosition(x: 8, y: 8), in: world),
            .invalidMinerPlacement
        )
    }

    func testMinerPlacementRejectsOccupiedPatchBindingTarget() {
        let board = BoardState(
            width: 12,
            height: 12,
            basePosition: GridPosition(x: 0, y: 0),
            spawnEdgeX: 11,
            spawnYMin: 0,
            spawnYMax: 0,
            blockedCells: [],
            restrictedCells: [GridPosition(x: 4, y: 4)],
            ramps: []
        )
        let world = WorldState(
            tick: 0,
            board: board,
            entities: EntityStore(),
            orePatches: [
                OrePatch(
                    id: 8,
                    oreType: "ore_copper",
                    richness: .normal,
                    position: GridPosition(x: 4, y: 4),
                    totalOre: 400,
                    remainingOre: 400,
                    boundMinerID: 99
                )
            ],
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(),
            combat: CombatState(basePosition: GridPosition(x: 0, y: 0), spawnEdgeX: 11, spawnYMin: 0, spawnYMax: 0)
        )

        let validator = PlacementValidator()
        XCTAssertEqual(
            validator.canPlace(.miner, at: GridPosition(x: 5, y: 4), targetPatchID: 8, in: world),
            .invalidMinerPlacement
        )
    }
}
