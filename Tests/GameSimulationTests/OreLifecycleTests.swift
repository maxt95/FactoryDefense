import XCTest
@testable import GameSimulation

final class OreLifecycleTests: XCTestCase {
    func testBootstrapInitializesOreLifecycleState() {
        let world = WorldState.bootstrap(difficulty: .normal, seed: 21)

        XCTAssertEqual(world.oreLifecycle.ringStates[0], .revealed)
        XCTAssertEqual(world.oreLifecycle.ringStates[1], .locked)
        XCTAssertEqual(world.oreLifecycle.ringStates[2], .locked)
        XCTAssertEqual(world.oreLifecycle.ringStates[3], .locked)
        XCTAssertEqual(world.oreLifecycle.nextPatchID, (world.orePatches.map(\.id).max() ?? 0) + 1)
    }

    func testStartOreSurveyCommandDeductsCostsAndStartsSurvey() {
        var entities = EntityStore()
        let researchCenterID = entities.spawnStructure(.researchCenter, at: GridPosition(x: 10, y: 10))

        let world = WorldState(
            tick: 0,
            entities: entities,
            oreLifecycle: OreLifecycleState(
                ringStates: [0: .revealed, 1: .locked, 2: .locked, 3: .locked],
                nextPatchID: 50
            ),
            economy: EconomyState(
                structureInputBuffers: [researchCenterID: ["gear": 12]]
            ),
            threat: ThreatState(),
            run: RunState(phase: .playing, difficulty: .normal, seed: 77)
        )
        let engine = SimulationEngine(worldState: world, systems: [CommandSystem()])
        engine.enqueue(
            PlayerCommand(
                tick: 0,
                actor: PlayerID(1),
                payload: .startOreSurvey(nodeID: "geology_survey_1", researchCenterID: researchCenterID)
            )
        )

        let events = engine.step()

        XCTAssertEqual(engine.worldState.oreLifecycle.ringStates[1], .surveying)
        XCTAssertEqual(engine.worldState.oreLifecycle.surveyEndTickByRing[1], 360)
        XCTAssertEqual(engine.worldState.economy.structureInputBuffers[researchCenterID, default: [:]]["gear", default: 0], 0)
        XCTAssertTrue(events.contains(where: { $0.kind == .ringSurveyStarted && $0.value == 1 && $0.entity == researchCenterID }))
    }

    func testSurveyCompletionRevealsRingAndSpawnsDeterministicPatches() {
        var first = WorldState.bootstrap(difficulty: .normal, seed: 91)
        first.oreLifecycle.ringStates[1] = .surveying
        first.oreLifecycle.surveyEndTickByRing[1] = 0
        let second = first

        let firstEngine = SimulationEngine(worldState: first, systems: [OreLifecycleSystem()])
        let secondEngine = SimulationEngine(worldState: second, systems: [OreLifecycleSystem()])

        let firstEvents = firstEngine.step()
        _ = secondEngine.step()

        XCTAssertEqual(firstEngine.worldState.oreLifecycle.ringStates[1], .revealed)
        XCTAssertTrue(firstEvents.contains(where: { $0.kind == .ringRevealed && $0.value == 1 }))

        let firstRingOne = firstEngine.worldState.orePatches.filter { $0.revealRing == 1 }.sorted(by: { $0.id < $1.id })
        let secondRingOne = secondEngine.worldState.orePatches.filter { $0.revealRing == 1 }.sorted(by: { $0.id < $1.id })
        XCTAssertFalse(firstRingOne.isEmpty)
        XCTAssertEqual(firstRingOne, secondRingOne)
        XCTAssertTrue(firstRingOne.allSatisfy(\.isRevealed))
    }

    func testMinerPlacementRejectsHiddenPatchTargets() {
        let board = BoardState(
            width: 20,
            height: 20,
            basePosition: GridPosition(x: 5, y: 5),
            spawnEdgeX: 19,
            spawnYMin: 0,
            spawnYMax: 0,
            blockedCells: [],
            restrictedCells: [GridPosition(x: 10, y: 10)],
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
                    position: GridPosition(x: 10, y: 10),
                    revealRing: 1,
                    isRevealed: false,
                    totalOre: 500,
                    remainingOre: 500
                )
            ],
            oreLifecycle: OreLifecycleState(
                ringStates: [0: .revealed, 1: .locked, 2: .locked, 3: .locked],
                nextPatchID: 8
            ),
            economy: EconomyState(storageSharedPoolByEntity: [1: ["plate_iron": 6, "gear": 3]]),
            threat: ThreatState(),
            run: RunState(phase: .playing, difficulty: .normal, seed: 11)
        )
        let engine = SimulationEngine(worldState: world, systems: [CommandSystem()])
        engine.enqueue(
            PlayerCommand(
                tick: 0,
                actor: PlayerID(1),
                payload: .placeStructure(
                    BuildRequest(
                        structure: .miner,
                        position: GridPosition(x: 11, y: 10),
                        targetPatchID: 7
                    )
                )
            )
        )

        let events = engine.step()

        XCTAssertTrue(events.contains(where: {
            $0.kind == .placementRejected && $0.value == PlacementResult.invalidMinerPlacement.rawValue
        }))
    }

    func testRenewalsProcessOncePerGapBoundary() {
        var world = WorldState.bootstrap(difficulty: .normal, seed: 123)
        world.oreLifecycle.ringStates[1] = .revealed
        world.threat.waveIndex = 3
        world.threat.isWaveActive = false
        world.oreLifecycle.lastRenewalWaveProcessed = 2

        guard !world.orePatches.isEmpty else {
            XCTFail("Expected bootstrap ore patches")
            return
        }
        world.orePatches[0].remainingOre = 0
        world.orePatches[0].exhaustedAtTick = world.tick
        world.orePatches[0].renewalProcessed = false

        let engine = SimulationEngine(worldState: world, systems: [OreLifecycleSystem()])
        let events = engine.step()

        XCTAssertEqual(engine.worldState.oreLifecycle.lastRenewalWaveProcessed, 3)
        XCTAssertTrue(engine.worldState.orePatches[0].renewalProcessed)
        XCTAssertTrue(events.contains(where: { $0.kind == .oreRenewalSpawned }))
    }

    func testRenewalPlacementAvoidsInvalidCellsAndRespectsSpacing() {
        var world = WorldState.bootstrap(difficulty: .normal, seed: 222)
        world.oreLifecycle.ringStates[1] = .revealed
        world.threat.waveIndex = 4
        world.threat.isWaveActive = false
        world.oreLifecycle.lastRenewalWaveProcessed = 3
        world.oreLifecycle.renewalQueue = [
            RenewalRequest(sourcePatchID: 999, oreType: "ore_iron", exhaustedAtTick: world.tick)
        ]

        _ = world.entities.spawnStructure(.wall, at: GridPosition(x: 10, y: 10))

        let preRestricted = Set(world.board.restrictedCells.map(normalized))
        let preBlocked = Set(world.board.blockedCells.map(normalized))
        let preOccupied = occupiedCells(in: world)
        let preActivePatches = world.orePatches
            .filter { !$0.isExhausted }
            .map { normalized($0.position) }
        let prePatchCount = world.orePatches.count

        let engine = SimulationEngine(worldState: world, systems: [OreLifecycleSystem()])
        let events = engine.step()

        let spawnedIDs = events.filter { $0.kind == .oreRenewalSpawned }.compactMap(\.value)
        XCTAssertFalse(spawnedIDs.isEmpty)
        guard let spawnedID = spawnedIDs.first,
              let patch = engine.worldState.orePatches.first(where: { $0.id == spawnedID }) else {
            XCTFail("Expected spawned renewal patch")
            return
        }

        let position = normalized(patch.position)
        XCTAssertEqual(engine.worldState.orePatches.count, prePatchCount + 1)
        XCTAssertFalse(preRestricted.contains(position))
        XCTAssertFalse(preBlocked.contains(position))
        XCTAssertFalse(preOccupied.contains(position))
        XCTAssertFalse(Set(preActivePatches).contains(position))

        let spacing = max(1, CanonicalBootstrapContent.bundle?.orePatches.renewal.minSpacing ?? 3)
        for existing in preActivePatches {
            XCTAssertGreaterThanOrEqual(chebyshevDistance(existing, position), spacing)
        }
    }

    func testHardSkipPolicyForcesSpawnAfterMaxSkips() {
        var world = WorldState.bootstrap(difficulty: .hard, seed: 6)
        world.oreLifecycle.ringStates[1] = .revealed
        world.threat.waveIndex = 4
        world.threat.isWaveActive = false
        world.oreLifecycle.lastRenewalWaveProcessed = 3
        world.oreLifecycle.renewalQueue = [
            RenewalRequest(sourcePatchID: 9_999, oreType: "ore_iron", exhaustedAtTick: 100, skipCount: 2)
        ]

        let engine = SimulationEngine(worldState: world, systems: [OreLifecycleSystem()])
        let events = engine.step()

        XCTAssertTrue(engine.worldState.oreLifecycle.renewalQueue.isEmpty)
        XCTAssertTrue(events.contains(where: { $0.kind == .oreRenewalSpawned }))
    }

    func testRenewalProcessingIsDeterministicForSameSeedAndQueue() {
        var first = WorldState.bootstrap(difficulty: .hard, seed: 81)
        first.oreLifecycle.ringStates[1] = .revealed
        first.threat.waveIndex = 5
        first.threat.isWaveActive = false
        first.oreLifecycle.lastRenewalWaveProcessed = 4
        first.oreLifecycle.renewalQueue = [
            RenewalRequest(sourcePatchID: 10_001, oreType: "ore_copper", exhaustedAtTick: 200, skipCount: 0)
        ]
        let second = first

        let firstEngine = SimulationEngine(worldState: first, systems: [OreLifecycleSystem()])
        let secondEngine = SimulationEngine(worldState: second, systems: [OreLifecycleSystem()])

        _ = firstEngine.step()
        _ = secondEngine.step()

        XCTAssertEqual(firstEngine.makeSnapshot(), secondEngine.makeSnapshot())
    }

    func testSurveyAndRenewalTimelinesAreDeterministicForSameCommandStream() {
        var world = WorldState.bootstrap(difficulty: .normal, seed: 5_150)
        world.oreLifecycle.ringStates[1] = .revealed
        world.oreLifecycle.ringStates[2] = .locked
        world.threat.waveIndex = 2
        world.threat.isWaveActive = false
        world.oreLifecycle.lastRenewalWaveProcessed = 1
        world.orePatches[0].remainingOre = 0
        world.orePatches[0].exhaustedAtTick = 0
        world.orePatches[0].renewalProcessed = false

        let researchCenterID = world.entities.spawnStructure(
            .researchCenter,
            at: GridPosition(x: world.board.basePosition.x + 4, y: world.board.basePosition.y)
        )
        world.economy.structureInputBuffers[researchCenterID] = ["plate_steel": 24]

        let command = PlayerCommand(
            tick: 0,
            actor: PlayerID(1),
            payload: .startOreSurvey(nodeID: "geology_survey_2", researchCenterID: researchCenterID)
        )
        let systems: [any SimulationSystem] = [CommandSystem(), OreLifecycleSystem()]
        let firstEngine = SimulationEngine(worldState: world, systems: systems)
        let secondEngine = SimulationEngine(worldState: world, systems: systems)
        firstEngine.enqueue(command)
        secondEngine.enqueue(command)

        var firstEvents: [SimEvent] = []
        var secondEvents: [SimEvent] = []
        for _ in 0..<481 {
            firstEvents += firstEngine.step()
            secondEvents += secondEngine.step()
        }

        XCTAssertEqual(firstEvents, secondEvents)
        XCTAssertEqual(firstEngine.makeSnapshot(), secondEngine.makeSnapshot())
        XCTAssertTrue(firstEvents.contains(where: { $0.kind == .oreRenewalSpawned }))
        XCTAssertTrue(firstEvents.contains(where: { $0.kind == .ringRevealed && $0.value == 2 }))
    }

    private func occupiedCells(in world: WorldState) -> Set<GridPosition> {
        var occupied: Set<GridPosition> = []
        for entity in world.entities.all where entity.category != .projectile {
            let position = normalized(entity.position)
            if entity.category == .structure, let structureType = entity.structureType {
                for cell in structureType.coveredCells(anchor: entity.position) {
                    occupied.insert(normalized(cell))
                }
            } else {
                occupied.insert(position)
            }
        }
        return occupied
    }

    private func normalized(_ position: GridPosition) -> GridPosition {
        GridPosition(x: position.x, y: position.y, z: 0)
    }

    private func chebyshevDistance(_ lhs: GridPosition, _ rhs: GridPosition) -> Int {
        max(abs(lhs.x - rhs.x), abs(lhs.y - rhs.y))
    }
}
