import XCTest
@testable import GamePlatform
@testable import GameSimulation

@MainActor
final class RuntimeControllerTests: XCTestCase {
    func testRuntimeTickLoopIsDeterministicForMatchingCommandStreams() {
        let first = GameRuntimeController(initialWorld: .bootstrap())
        let second = GameRuntimeController(initialWorld: .bootstrap())

        first.triggerWave()
        second.triggerWave()

        for tick in 0..<60 {
            if tick == 4 {
                first.placeStructure(.conveyor, at: GridPosition(x: 7, y: 4))
                second.placeStructure(.conveyor, at: GridPosition(x: 7, y: 4))
            }

            if tick == 8 {
                first.placeStructure(.wall, at: GridPosition(x: 10, y: 3))
                second.placeStructure(.wall, at: GridPosition(x: 10, y: 3))
            }

            _ = first.advanceTick()
            _ = second.advanceTick()
        }

        XCTAssertEqual(first.snapshot(), second.snapshot())
    }

    func testInputMapperProducesPlaceCommand() {
        let mapper = DefaultInputMapper()
        let event = InputEvent(
            timestamp: 1,
            device: .mouse,
            gesture: .placeStructure(type: .turretMount, position: GridPosition(x: 3, y: 2))
        )

        let command = mapper.map(event: event, tick: 10, actor: PlayerID(7))
        guard case .placeStructure(let request)? = command?.payload else {
            return XCTFail("Expected placeStructure command")
        }

        XCTAssertEqual(request.structure, .turretMount)
        XCTAssertEqual(request.position, GridPosition(x: 3, y: 2))
        XCTAssertEqual(command?.tick, 10)
        XCTAssertEqual(command?.actor, PlayerID(7))
    }

    func testTapGridUsesDefaultStructureWhenConfigured() {
        let mapper = DefaultInputMapper(defaultStructureOnTap: .wall)
        let event = InputEvent(
            timestamp: 1,
            device: .touch,
            gesture: .tapGrid(position: GridPosition(x: 5, y: 5))
        )

        let command = mapper.map(event: event, tick: 12, actor: PlayerID(1))
        guard case .placeStructure(let request)? = command?.payload else {
            return XCTFail("Expected tapGrid to map to placeStructure")
        }

        XCTAssertEqual(request.structure, .wall)
        XCTAssertEqual(request.position, GridPosition(x: 5, y: 5))
    }

    func testRunSummaryIsPublishedOnGameOver() {
        let runtime = GameRuntimeController(initialWorld: makeImmediateGameOverWorld())

        runtime.placeStructure(.wall, at: GridPosition(x: 3, y: 3))
        let events = runtime.advanceTick()

        XCTAssertTrue(events.contains(where: { $0.kind == .structurePlaced }))
        XCTAssertTrue(events.contains(where: { $0.kind == .gameOver }))

        guard let summary = runtime.runSummary else {
            return XCTFail("Expected run summary after game over")
        }

        XCTAssertEqual(summary.finalTick, 0)
        XCTAssertEqual(summary.wavesSurvived, 0)
        XCTAssertEqual(summary.enemiesDestroyed, 0)
        XCTAssertEqual(summary.structuresBuilt, 1)
        XCTAssertEqual(summary.ammoSpent, 0)
    }

    func testPlaceConveyorCommandUsesDirection() {
        let world = makeCommandHelperWorld()
        let runtime = GameRuntimeController(initialWorld: world)
        let target = GridPosition(x: 5, y: 5)

        runtime.placeConveyor(at: target, direction: .south)
        _ = runtime.advanceTick()

        let placedID = runtime.latestEvents.first(where: { $0.kind == .structurePlaced })?.entity
        let placed = placedID.flatMap { runtime.world.entities.entity(id: $0) }
        XCTAssertEqual(placed?.structureType, .conveyor)
        XCTAssertEqual(placed?.rotation, .south)
    }

    func testRotatePinAndRemoveCommandHelpers() {
        let world = makeCommandHelperWorld()
        let runtime = GameRuntimeController(initialWorld: world)

        let assemblerID = 2
        let wallID = 3

        runtime.rotateBuilding(entityID: assemblerID)
        _ = runtime.advanceTick()
        XCTAssertEqual(runtime.world.entities.entity(id: assemblerID)?.rotation, .east)

        runtime.pinRecipe(entityID: assemblerID, recipeID: "forge_gear")
        _ = runtime.advanceTick()
        XCTAssertEqual(runtime.world.economy.pinnedRecipeByStructure[assemblerID], "forge_gear")

        runtime.removeStructure(entityID: wallID)
        _ = runtime.advanceTick()
        XCTAssertNil(runtime.world.entities.entity(id: wallID))
    }

    func testPlaceStructurePathStopsWhenResourcesExhausted() {
        var world = makeCommandHelperWorld()
        world.economy.storageSharedPoolByEntity[1, default: [:]]["wall_kit"] = 2
        world.rebuildAggregatedInventory()
        let runtime = GameRuntimeController(initialWorld: world)

        runtime.placeStructurePath(
            .wall,
            along: [
                GridPosition(x: 1, y: 7),
                GridPosition(x: 2, y: 7),
                GridPosition(x: 3, y: 7),
                GridPosition(x: 4, y: 7)
            ]
        )
        _ = runtime.advanceTick()

        let placedWalls = runtime.latestEvents.filter { $0.kind == .structurePlaced }.count
        XCTAssertEqual(placedWalls, 2)
    }

    func testPlaceStructurePathSkipsInvalidCellsAndKeepsValidPlacements() {
        var world = makeCommandHelperWorld()
        for cost in StructureType.wall.buildCosts {
            world.economy.storageSharedPoolByEntity[1, default: [:]][cost.itemID] = 20
        }
        world.rebuildAggregatedInventory()
        let runtime = GameRuntimeController(initialWorld: world)

        runtime.placeStructurePath(
            .wall,
            along: [
                GridPosition(x: 0, y: 0), // occupied by HQ
                GridPosition(x: 1, y: 7),
                GridPosition(x: 2, y: 7)
            ]
        )
        _ = runtime.advanceTick()
        XCTAssertEqual(
            runtime.latestEvents.filter { $0.kind == .structurePlaced }.count,
            2
        )
        XCTAssertNotNil(runtime.world.entities.entity(id: 1)) // HQ still present
    }

    // MARK: - Conveyor Endpoint Snapping

    func testFirstCellSnapsInputToExistingConveyorAbove() {
        // Existing conveyor at (25,24) outputs south toward (25,25).
        // Drag path from (25,25) east to (27,25).
        // First cell (25,25) should snap input from west → north to connect.
        var world = makeConveyorSnappingWorld()
        let conveyorID = world.entities.spawnStructure(.conveyor, at: GridPosition(x: 25, y: 24), rotation: .south)
        world.economy.conveyorIOByEntity[conveyorID] = ConveyorIOConfig(
            inputDirection: .north,
            outputDirection: .south
        )
        world.rebuildAggregatedInventory()
        let runtime = GameRuntimeController(initialWorld: world)

        runtime.placeConveyorPath([
            ConveyorPlacementCell(position: GridPosition(x: 25, y: 25), inputDirection: .west, outputDirection: .east),
            ConveyorPlacementCell(position: GridPosition(x: 26, y: 25), inputDirection: .west, outputDirection: .east),
            ConveyorPlacementCell(position: GridPosition(x: 27, y: 25), inputDirection: .west, outputDirection: .east),
        ])
        _ = runtime.advanceTick()

        // Find the conveyor placed at (25,25) — its I/O should be snapped
        if let entity = runtime.world.entities.selectableEntity(at: GridPosition(x: 25, y: 25)) {
            let io = runtime.world.economy.conveyorIOByEntity[entity.id]
                ?? ConveyorIOConfig.default(for: entity.rotation)
            XCTAssertEqual(io.inputDirection, .north, "First cell input should snap to face the existing conveyor above")
            XCTAssertEqual(io.outputDirection, .east, "First cell output should still face east along the path")
        } else {
            XCTFail("Expected conveyor at (25,25)")
        }
    }

    func testLastCellSnapsOutputToExistingConveyorBelow() {
        // Existing conveyor at (27,26) expects input from north (input=north, output=south).
        // Drag path from (25,25) east to (27,25).
        // Last cell (27,25) should snap output from east → south to feed it.
        var world = makeConveyorSnappingWorld()
        let conveyorID = world.entities.spawnStructure(.conveyor, at: GridPosition(x: 27, y: 26), rotation: .south)
        world.economy.conveyorIOByEntity[conveyorID] = ConveyorIOConfig(
            inputDirection: .north,
            outputDirection: .south
        )
        world.rebuildAggregatedInventory()
        let runtime = GameRuntimeController(initialWorld: world)

        runtime.placeConveyorPath([
            ConveyorPlacementCell(position: GridPosition(x: 25, y: 25), inputDirection: .west, outputDirection: .east),
            ConveyorPlacementCell(position: GridPosition(x: 26, y: 25), inputDirection: .west, outputDirection: .east),
            ConveyorPlacementCell(position: GridPosition(x: 27, y: 25), inputDirection: .west, outputDirection: .east),
        ])
        _ = runtime.advanceTick()

        if let entity = runtime.world.entities.selectableEntity(at: GridPosition(x: 27, y: 25)) {
            let io = runtime.world.economy.conveyorIOByEntity[entity.id]
                ?? ConveyorIOConfig.default(for: entity.rotation)
            XCTAssertEqual(io.outputDirection, .south, "Last cell output should snap to face the existing conveyor below")
            XCTAssertEqual(io.inputDirection, .west, "Last cell input should still face west along the path")
        } else {
            XCTFail("Expected conveyor at (27,25)")
        }
    }

    func testEndpointDoesNotSnapWhenAlreadyConnected() {
        // Existing conveyor at (24,25) outputs east toward (25,25).
        // Drag path from (25,25) east to (27,25).
        // First cell (25,25) already has input=west which connects. No snap needed.
        var world = makeConveyorSnappingWorld()
        _ = world.entities.spawnStructure(.conveyor, at: GridPosition(x: 24, y: 25), rotation: .east)
        // Default I/O for east rotation: input=west, output=east — outputs east toward (25,25)
        world.rebuildAggregatedInventory()
        let runtime = GameRuntimeController(initialWorld: world)

        runtime.placeConveyorPath([
            ConveyorPlacementCell(position: GridPosition(x: 25, y: 25), inputDirection: .west, outputDirection: .east),
            ConveyorPlacementCell(position: GridPosition(x: 26, y: 25), inputDirection: .west, outputDirection: .east),
            ConveyorPlacementCell(position: GridPosition(x: 27, y: 25), inputDirection: .west, outputDirection: .east),
        ])
        _ = runtime.advanceTick()

        if let entity = runtime.world.entities.selectableEntity(at: GridPosition(x: 25, y: 25)) {
            let io = runtime.world.economy.conveyorIOByEntity[entity.id]
                ?? ConveyorIOConfig.default(for: entity.rotation)
            // Should stay as default — no corner created
            XCTAssertEqual(io.inputDirection, .west, "Input should remain west (already connected)")
            XCTAssertEqual(io.outputDirection, .east)
        } else {
            XCTFail("Expected conveyor at (25,25)")
        }
    }

    func testFirstCellSnapsToAdjacentBuilding() {
        // Miner at (24,25) outputs in all directions including east toward (25,25).
        // Drag path from (25,25) going south to (25,27).
        // First cell (25,25) has default input=north. Miner is to the west.
        // Should snap input to west to receive from the miner.
        var world = makeConveyorSnappingWorld()
        _ = world.entities.spawnStructure(.miner, at: GridPosition(x: 24, y: 25))
        world.rebuildAggregatedInventory()
        let runtime = GameRuntimeController(initialWorld: world)

        runtime.placeConveyorPath([
            ConveyorPlacementCell(position: GridPosition(x: 25, y: 25), inputDirection: .north, outputDirection: .south),
            ConveyorPlacementCell(position: GridPosition(x: 25, y: 26), inputDirection: .north, outputDirection: .south),
            ConveyorPlacementCell(position: GridPosition(x: 25, y: 27), inputDirection: .north, outputDirection: .south),
        ])
        _ = runtime.advanceTick()

        if let entity = runtime.world.entities.selectableEntity(at: GridPosition(x: 25, y: 25)) {
            let io = runtime.world.economy.conveyorIOByEntity[entity.id]
                ?? ConveyorIOConfig.default(for: entity.rotation)
            XCTAssertEqual(io.inputDirection, .west, "First cell input should snap to face the miner to the west")
            XCTAssertEqual(io.outputDirection, .south, "Output should still face south along the path")
        } else {
            XCTFail("Expected conveyor at (25,25)")
        }
    }

    func testCornerConveyorIOIsCorrectAfterPlacement() {
        // Drag east 3 tiles then north 2 tiles — corner at (27,25).
        // The corner should have input=west, output=north (NOT south/east from sort reordering).
        let world = makeConveyorSnappingWorld()
        let runtime = GameRuntimeController(initialWorld: world)

        runtime.placeConveyorPath([
            ConveyorPlacementCell(position: GridPosition(x: 25, y: 25), inputDirection: .west, outputDirection: .east),
            ConveyorPlacementCell(position: GridPosition(x: 26, y: 25), inputDirection: .west, outputDirection: .east),
            ConveyorPlacementCell(position: GridPosition(x: 27, y: 25), inputDirection: .west, outputDirection: .north, isCorner: true),
            ConveyorPlacementCell(position: GridPosition(x: 27, y: 24), inputDirection: .south, outputDirection: .north),
            ConveyorPlacementCell(position: GridPosition(x: 27, y: 23), inputDirection: .south, outputDirection: .north),
        ])
        _ = runtime.advanceTick()

        // Verify the corner cell specifically
        if let corner = runtime.world.entities.selectableEntity(at: GridPosition(x: 27, y: 25)) {
            let io = runtime.world.economy.conveyorIOByEntity[corner.id]
                ?? ConveyorIOConfig.default(for: corner.rotation)
            XCTAssertEqual(io.inputDirection, .west, "Corner input should face the feeder to the west")
            XCTAssertEqual(io.outputDirection, .north, "Corner output should face the receiver to the north")
        } else {
            XCTFail("Expected conveyor at corner (27,25)")
        }

        // Verify a straight cell after the corner
        if let straight = runtime.world.entities.selectableEntity(at: GridPosition(x: 27, y: 24)) {
            let io = runtime.world.economy.conveyorIOByEntity[straight.id]
                ?? ConveyorIOConfig.default(for: straight.rotation)
            XCTAssertEqual(io.inputDirection, .south, "Post-corner cell input should face south")
            XCTAssertEqual(io.outputDirection, .north, "Post-corner cell output should face north")
        } else {
            XCTFail("Expected conveyor at (27,24)")
        }

        // Verify first straight cell
        if let first = runtime.world.entities.selectableEntity(at: GridPosition(x: 25, y: 25)) {
            let io = runtime.world.economy.conveyorIOByEntity[first.id]
                ?? ConveyorIOConfig.default(for: first.rotation)
            XCTAssertEqual(io.inputDirection, .west, "First cell input should face west")
            XCTAssertEqual(io.outputDirection, .east, "First cell output should face east")
        } else {
            XCTFail("Expected conveyor at (25,25)")
        }
    }

    private func makeConveyorSnappingWorld() -> WorldState {
        // Large board so placement positions don't trigger expansion
        let board = BoardState(
            width: 50,
            height: 50,
            basePosition: GridPosition(x: 0, y: 0),
            spawnEdgeX: 49,
            spawnYMin: 0,
            spawnYMax: 2,
            blockedCells: [],
            restrictedCells: [],
            ramps: []
        )

        var entities = EntityStore()
        let hqID = entities.spawnStructure(.hq, at: GridPosition(x: 1, y: 1))

        var world = WorldState(
            tick: 0,
            board: board,
            entities: entities,
            economy: EconomyState(storageSharedPoolByEntity: [hqID: ["plate_iron": 50]]),
            threat: ThreatState(),
            run: RunState(phase: .playing, hqEntityID: hqID),
            combat: CombatState(
                basePosition: GridPosition(x: 0, y: 0),
                spawnEdgeX: 49,
                spawnYMin: 0,
                spawnYMax: 2
            )
        )
        world.rebuildAggregatedInventory()
        return world
    }

    private func makeImmediateGameOverWorld() -> WorldState {
        let board = BoardState(
            width: 8,
            height: 8,
            basePosition: GridPosition(x: 0, y: 0),
            spawnEdgeX: 7,
            spawnYMin: 0,
            spawnYMax: 2,
            blockedCells: [],
            restrictedCells: [],
            ramps: []
        )

        var entities = EntityStore()
        let hqID = entities.spawnStructure(.hq, at: GridPosition(x: 1, y: 1), health: 2, maxHealth: 2)
        let enemyID = entities.spawnEnemy(at: GridPosition(x: 0, y: 0), health: 10)

        var world = WorldState(
            tick: 0,
            board: board,
            entities: entities,
            economy: EconomyState(storageSharedPoolByEntity: [hqID: ["wall_kit": 1]]),
            threat: ThreatState(
                waveIndex: 0,
                nextWaveTick: 9_999,
                waveIntervalTicks: 9_999,
                waveDurationTicks: 180,
                waveEndsAtTick: nil,
                isWaveActive: false,
                waveGapBaseTicks: 9_999,
                waveGapFloorTicks: 9_999,
                waveGapCompressionTicks: 0,
                gracePeriodTicks: 0,
                graceEndsAtTick: 0,
                trickleIntervalTicks: 9_999,
                trickleMinCount: 1,
                trickleMaxCount: 1,
                nextTrickleTick: 9_999,
                milestoneEvery: 5,
                lastMilestoneWave: 0
            ),
            run: RunState(phase: .playing, hqEntityID: hqID),
            combat: CombatState(
                enemies: [
                    enemyID: EnemyRuntime(
                        id: enemyID,
                        archetype: .droneScout,
                        moveEveryTicks: 1,
                        baseDamage: 2,
                        rewardCurrency: 1
                    )
                ],
                basePosition: GridPosition(x: 0, y: 0),
                spawnEdgeX: 7,
                spawnYMin: 0,
                spawnYMax: 2
            )
        )
        world.rebuildAggregatedInventory()
        return world
    }

    private func makeCommandHelperWorld() -> WorldState {
        let board = BoardState(
            width: 8,
            height: 8,
            basePosition: GridPosition(x: 0, y: 0),
            spawnEdgeX: 7,
            spawnYMin: 0,
            spawnYMax: 2,
            blockedCells: [],
            restrictedCells: [],
            ramps: []
        )

        var entities = EntityStore()
        let hqID = entities.spawnStructure(.hq, at: GridPosition(x: 0, y: 0))
        _ = entities.spawnStructure(.assembler, at: GridPosition(x: 2, y: 2))
        _ = entities.spawnStructure(.wall, at: GridPosition(x: 4, y: 4))

        var world = WorldState(
            tick: 0,
            board: board,
            entities: entities,
            economy: EconomyState(storageSharedPoolByEntity: [hqID: ["plate_iron": 20]]),
            threat: ThreatState(),
            run: RunState(phase: .playing, hqEntityID: hqID),
            combat: CombatState(
                basePosition: GridPosition(x: 0, y: 0),
                spawnEdgeX: 7,
                spawnYMin: 0,
                spawnYMax: 2
            )
        )
        world.rebuildAggregatedInventory()
        return world
    }
}
