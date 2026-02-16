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

        return WorldState(
            tick: 0,
            board: board,
            entities: entities,
            economy: EconomyState(inventories: ["wall_kit": 1]),
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
                raidCooldownUntilTick: 0,
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
        _ = entities.spawnStructure(.hq, at: GridPosition(x: 0, y: 0))
        _ = entities.spawnStructure(.assembler, at: GridPosition(x: 2, y: 2))
        _ = entities.spawnStructure(.wall, at: GridPosition(x: 4, y: 4))

        return WorldState(
            tick: 0,
            board: board,
            entities: entities,
            economy: EconomyState(inventories: ["plate_iron": 20]),
            threat: ThreatState(),
            run: RunState(phase: .playing, hqEntityID: 1),
            combat: CombatState(
                basePosition: GridPosition(x: 0, y: 0),
                spawnEdgeX: 7,
                spawnYMin: 0,
                spawnYMax: 2
            )
        )
    }
}
