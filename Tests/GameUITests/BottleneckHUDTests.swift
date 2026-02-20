import XCTest
@testable import GameSimulation
@testable import GameUI

final class BottleneckHUDTests: XCTestCase {

    // MARK: - Helpers

    private func makeSignals(_ kinds: [BottleneckSignalKind]) -> [BottleneckSignal] {
        kinds.enumerated().map { index, kind in
            BottleneckSignal(
                kind: kind,
                scope: kind == .powerShortage || kind == .ammoDryFire || kind == .surgeBacklogHigh
                    ? .global
                    : .structure(index + 100),
                severity: .warn,
                firstTick: 0,
                lastTick: 10,
                entityID: index + 100
            )
        }
    }

    private func makeMinimalWorld(
        signals: [BottleneckSignal] = [],
        hqHealth: Int = 1000
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
        let hqID = entities.spawnStructure(.hq, at: GridPosition(x: 10, y: 10), health: hqHealth, maxHealth: 1000)

        return WorldState(
            tick: 100,
            board: board,
            entities: entities,
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(phase: .playing, hqEntityID: hqID),
            combat: CombatState(
                basePosition: GridPosition(x: 10, y: 10),
                spawnEdgeX: 19,
                spawnYMin: 0,
                spawnYMax: 19
            ),
            bottleneck: BottleneckState(activeSignals: signals)
        )
    }

    // MARK: - Tests

    func testGroupedAlertsLimitedToFour() {
        let signals = makeSignals([
            .ammoDryFire, .inputStarved, .outputBlocked,
            .powerShortage, .minerNoOre, .conveyorStall
        ])

        let alerts = HUDViewModel.buildGroupedAlerts(from: signals)
        XCTAssertLessThanOrEqual(alerts.count, 4, "Grouped alerts must be capped at 4")
    }

    func testWarningBannerDerivedFromHighestPrioritySignal() {
        // Signals must be in priority order (ammoDryFire=0 < powerShortage=3) as BottleneckSystem sorts them
        let signals = makeSignals([.ammoDryFire, .powerShortage])
        let world = makeMinimalWorld(signals: signals)

        let viewModel = HUDViewModel.build(from: world)

        // ammoDryFire has priority 0 (highest), should be the warning
        XCTAssertEqual(viewModel.warning, .ammoDryFire)
    }

    func testInspectorShowsBottleneckStatusForAffectedEntity() {
        var world = makeMinimalWorld()
        let smelterID = world.entities.spawnStructure(.smelter, at: GridPosition(x: 5, y: 5))
        world.economy.pinnedRecipeByStructure[smelterID] = "smelt_iron"

        let signal = BottleneckSignal(
            kind: .inputStarved,
            scope: .structure(smelterID),
            severity: .warn,
            firstTick: 80,
            lastTick: 100,
            entityID: smelterID,
            detail: "Smelt Iron missing inputs"
        )
        world.bottleneck.activeSignals = [signal]

        let builder = ObjectInspectorBuilder()
        let model = builder.build(entityID: smelterID, in: world)

        XCTAssertNotNil(model)
        let operationSection = model?.sections.first(where: { $0.title == "Operation" })
        XCTAssertNotNil(operationSection)

        let statusRow = operationSection?.rows.first(where: { $0.id == "bottleneck-status" })
        XCTAssertNotNil(statusRow, "Should show bottleneck status row")
        XCTAssertEqual(statusRow?.value, "Input starved")

        let detailRow = operationSection?.rows.first(where: { $0.id == "bottleneck-detail" })
        XCTAssertNotNil(detailRow, "Should show bottleneck detail row")
        XCTAssertTrue(detailRow?.value.contains("Smelt Iron missing inputs") ?? false)
    }
}
