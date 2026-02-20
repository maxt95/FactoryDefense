import XCTest
@testable import GameSimulation

final class BottleneckSystemTests: XCTestCase {

    // MARK: - Helpers

    private func makeMinimalWorld(
        tick: UInt64 = 0,
        phase: RunPhase = .playing
    ) -> WorldState {
        let board = BoardState(
            width: 20,
            height: 20,
            basePosition: GridPosition(x: 10, y: 10),
            spawnEdgeX: 19,
            spawnYMin: 0,
            spawnYMax: 19,
            blockedCells: [],
            restrictedCells: [],
            ramps: []
        )
        var entities = EntityStore()
        let hqID = entities.spawnStructure(.hq, at: GridPosition(x: 10, y: 10), health: 1000, maxHealth: 1000)

        return WorldState(
            tick: tick,
            board: board,
            entities: entities,
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(phase: phase, hqEntityID: hqID),
            combat: CombatState(
                basePosition: GridPosition(x: 10, y: 10),
                spawnEdgeX: 19,
                spawnYMin: 0,
                spawnYMax: 19
            )
        )
    }

    private func runBottleneckSystem(
        state: inout WorldState,
        ticks: Int = 1,
        system: BottleneckSystem = BottleneckSystem()
    ) -> [SimEvent] {
        var allEvents: [SimEvent] = []
        for _ in 0..<ticks {
            var tickEvents: [SimEvent] = []
            let context = SystemContext(
                tickDurationSeconds: 0.05,
                commands: [],
                emitEvent: { tickEvents.append($0) }
            )
            system.update(state: &state, context: context)
            state.tick += 1
            allEvents.append(contentsOf: tickEvents)
        }
        return allEvents
    }

    // MARK: - Signal Detection Tests

    func testAmmoDryFireActivatesDuringWaveWithDryFires() {
        var world = makeMinimalWorld()
        world.threat.isWaveActive = true
        // Set previous dry fire count and then increment to simulate delta
        world.bottleneck.previousDryFireEvents = 0
        world.threat.telemetry.dryFireEvents = 1

        let system = BottleneckSystem(activationThresholdTicks: 1)
        let events = runBottleneckSystem(state: &world, ticks: 1, system: system)

        XCTAssertTrue(world.bottleneck.activeSignals.contains(where: { $0.kind == .ammoDryFire }))
        XCTAssertTrue(events.contains(where: { $0.kind == .bottleneckActivated }))
    }

    func testInputStarvedForSmelterMissingOre() {
        var world = makeMinimalWorld()
        let smelterID = world.entities.spawnStructure(.smelter, at: GridPosition(x: 5, y: 5))
        world.economy.pinnedRecipeByStructure[smelterID] = "smelt_iron"
        // No active recipe means inputs missing

        let system = BottleneckSystem(activationThresholdTicks: 1)
        let _ = runBottleneckSystem(state: &world, ticks: 1, system: system)

        XCTAssertTrue(world.bottleneck.activeSignals.contains(where: {
            $0.kind == .inputStarved && $0.entityID == smelterID
        }))
    }

    func testOutputBlockedWhenBufferFull() {
        var world = makeMinimalWorld()
        let minerID = world.entities.spawnStructure(.miner, at: GridPosition(x: 5, y: 5))
        world.economy.structureOutputBuffers[minerID] = ["ore_iron": 8]

        let system = BottleneckSystem(activationThresholdTicks: 1)
        let _ = runBottleneckSystem(state: &world, ticks: 1, system: system)

        XCTAssertTrue(world.bottleneck.activeSignals.contains(where: {
            $0.kind == .outputBlocked && $0.entityID == minerID
        }))
    }

    func testPowerShortageWhenDemandExceedsSupply() {
        var world = makeMinimalWorld()
        world.economy.powerAvailable = 5
        world.economy.powerDemand = 10

        let system = BottleneckSystem(activationThresholdTicks: 1)
        let _ = runBottleneckSystem(state: &world, ticks: 1, system: system)

        XCTAssertTrue(world.bottleneck.activeSignals.contains(where: { $0.kind == .powerShortage }))
    }

    func testMinerNoOreForExhaustedPatch() {
        var world = makeMinimalWorld()
        let minerID = world.entities.spawnStructure(.miner, at: GridPosition(x: 5, y: 5))
        world.entities.updateBoundPatchID(minerID, to: 1)
        world.orePatches = [
            OrePatch(id: 1, oreType: "ore_iron", richness: .normal, position: GridPosition(x: 5, y: 5), totalOre: 100, remainingOre: 0)
        ]

        let system = BottleneckSystem(activationThresholdTicks: 1)
        let _ = runBottleneckSystem(state: &world, ticks: 1, system: system)

        XCTAssertTrue(world.bottleneck.activeSignals.contains(where: {
            $0.kind == .minerNoOre && $0.entityID == minerID
        }))
    }

    func testConveyorStallWhenPayloadAtMaxProgress() {
        var world = makeMinimalWorld()
        let conveyorID = world.entities.spawnStructure(.conveyor, at: GridPosition(x: 5, y: 5))
        world.economy.conveyorPayloadByEntity[conveyorID] = ConveyorPayload(itemID: "ore_iron", progressTicks: 5)

        let system = BottleneckSystem(activationThresholdTicks: 1)
        let _ = runBottleneckSystem(state: &world, ticks: 1, system: system)

        XCTAssertTrue(world.bottleneck.activeSignals.contains(where: {
            $0.kind == .conveyorStall && $0.entityID == conveyorID
        }))
    }

    func testWallNetworkUnderfedWhenAmmoLow() {
        var world = makeMinimalWorld()
        let wallID = world.entities.spawnStructure(.wall, at: GridPosition(x: 8, y: 8))
        _ = world.entities.spawnStructure(
            .turretMount,
            at: GridPosition(x: 8, y: 8),
            hostWallID: wallID
        )
        world.combat.wallNetworks[1] = WallNetworkState(
            id: 1,
            wallEntityIDs: [wallID],
            ammoPoolByItemID: ["ammo_light": 1],
            capacity: 100
        )
        world.combat.wallNetworkByWallEntityID[wallID] = 1

        let system = BottleneckSystem(activationThresholdTicks: 1)
        let _ = runBottleneckSystem(state: &world, ticks: 1, system: system)

        XCTAssertTrue(world.bottleneck.activeSignals.contains(where: { $0.kind == .wallNetworkUnderfed }))
    }

    func testSurgeBacklogHighDuringActiveWave() {
        var world = makeMinimalWorld()
        world.threat.isWaveActive = true
        world.threat.telemetry.queuedSpawnBacklog = 15

        let system = BottleneckSystem(activationThresholdTicks: 1, spawnBacklogThreshold: 10)
        let _ = runBottleneckSystem(state: &world, ticks: 1, system: system)

        XCTAssertTrue(world.bottleneck.activeSignals.contains(where: { $0.kind == .surgeBacklogHigh }))
    }

    // MARK: - Priority & Grouping Tests

    func testHighestPrioritySignalIsFirst() {
        var world = makeMinimalWorld()
        world.threat.isWaveActive = true
        // Set up power shortage (priority 3) and ammo dry fire (priority 0)
        world.economy.powerAvailable = 5
        world.economy.powerDemand = 10
        world.bottleneck.previousDryFireEvents = 0
        world.threat.telemetry.dryFireEvents = 2

        let system = BottleneckSystem(activationThresholdTicks: 1)
        let _ = runBottleneckSystem(state: &world, ticks: 1, system: system)

        XCTAssertGreaterThanOrEqual(world.bottleneck.activeSignals.count, 2)
        XCTAssertEqual(world.bottleneck.activeSignals.first?.kind, .ammoDryFire)
    }

    func testMultipleMinersGroupIntoSingleKind() {
        var world = makeMinimalWorld()
        _ = world.entities.spawnStructure(.miner, at: GridPosition(x: 3, y: 3))
        _ = world.entities.spawnStructure(.miner, at: GridPosition(x: 5, y: 5))
        // Both miners have no bound patch
        world.orePatches = []

        let system = BottleneckSystem(activationThresholdTicks: 1)
        let _ = runBottleneckSystem(state: &world, ticks: 1, system: system)

        let minerNoOreSignals = world.bottleneck.activeSignals.filter { $0.kind == .minerNoOre }
        XCTAssertEqual(minerNoOreSignals.count, 2)
    }

    // MARK: - Hysteresis Tests

    func testSignalDoesNotActivateBeforeThreshold() {
        var world = makeMinimalWorld()
        world.economy.powerAvailable = 5
        world.economy.powerDemand = 10

        // Default activationThresholdTicks = 6, run only 5 ticks
        let system = BottleneckSystem()
        let _ = runBottleneckSystem(state: &world, ticks: 5, system: system)

        XCTAssertTrue(world.bottleneck.activeSignals.isEmpty, "Signal should not activate before threshold")
    }

    func testSignalDoesNotDeactivateBeforeRecoveryThreshold() {
        var world = makeMinimalWorld()
        world.economy.powerAvailable = 5
        world.economy.powerDemand = 10

        let system = BottleneckSystem(activationThresholdTicks: 1, recoveryThresholdTicks: 10)
        // Activate the signal
        let _ = runBottleneckSystem(state: &world, ticks: 1, system: system)
        XCTAssertTrue(world.bottleneck.activeSignals.contains(where: { $0.kind == .powerShortage }))

        // Clear the condition
        world.economy.powerAvailable = 10
        world.economy.powerDemand = 5

        // Run 9 ticks — should still be active
        let _ = runBottleneckSystem(state: &world, ticks: 9, system: system)
        XCTAssertTrue(world.bottleneck.activeSignals.contains(where: { $0.kind == .powerShortage }),
                      "Signal should remain active before recovery threshold")
    }

    func testFlappingConditionDoesNotCauseFlicker() {
        var world = makeMinimalWorld()
        let system = BottleneckSystem(activationThresholdTicks: 3, recoveryThresholdTicks: 5)

        // Alternate power shortage on/off every tick — should never activate
        for i in 0..<20 {
            if i % 2 == 0 {
                world.economy.powerAvailable = 5
                world.economy.powerDemand = 10
            } else {
                world.economy.powerAvailable = 10
                world.economy.powerDemand = 5
            }
            let _ = runBottleneckSystem(state: &world, ticks: 1, system: system)
        }

        XCTAssertTrue(world.bottleneck.activeSignals.isEmpty,
                      "Flapping condition should never activate a signal")
    }

    // MARK: - Determinism & Serialization Tests

    func testBottleneckSignalsDeterministicAcrossReplays() {
        func runSession() -> WorldState {
            var world = makeMinimalWorld()
            world.economy.powerAvailable = 5
            world.economy.powerDemand = 10
            world.threat.isWaveActive = true
            world.bottleneck.previousDryFireEvents = 0
            world.threat.telemetry.dryFireEvents = 2

            let system = BottleneckSystem(activationThresholdTicks: 2)
            let _ = runBottleneckSystem(state: &world, ticks: 10, system: system)
            return world
        }

        let run1 = runSession()
        let run2 = runSession()

        XCTAssertEqual(run1.bottleneck, run2.bottleneck, "Bottleneck state must be deterministic")
    }

    func testSnapshotRoundTripPreservesBottleneckState() throws {
        var world = makeMinimalWorld()
        world.economy.powerAvailable = 5
        world.economy.powerDemand = 10

        let system = BottleneckSystem(activationThresholdTicks: 1)
        let _ = runBottleneckSystem(state: &world, ticks: 2, system: system)

        XCTAssertFalse(world.bottleneck.activeSignals.isEmpty, "Should have active signals")

        let snapshot = WorldSnapshot(world: world, queuedCommands: [:])
        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WorldSnapshot.self, from: data)

        XCTAssertEqual(decoded.world.bottleneck, world.bottleneck,
                       "Bottleneck state must survive JSON round-trip")
    }
}
