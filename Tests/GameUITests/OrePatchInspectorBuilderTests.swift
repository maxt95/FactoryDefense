import XCTest
@testable import GameUI
@testable import GameSimulation

final class OrePatchInspectorBuilderTests: XCTestCase {
    func testBuilderProducesStageOnlyDepositRowsForActiveUnboundPatch() {
        let model = OrePatchInspectorBuilder().build(
            patchID: 11,
            in: makeWorld(
                patch: OrePatch(
                    id: 11,
                    oreType: "ore_copper",
                    richness: .rich,
                    position: GridPosition(x: 4, y: 6),
                    totalOre: 650,
                    remainingOre: 300
                )
            )
        )
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.title, "Copper Ore")
        XCTAssertEqual(model?.subtitle, "Ore Deposit")

        XCTAssertEqual(value(for: "Type", in: model), "Copper Ore")
        XCTAssertEqual(value(for: "Richness", in: model), "Rich")
        XCTAssertEqual(value(for: "Stage", in: model), "Partial")
        XCTAssertEqual(value(for: "Miner", in: model), "Unbound")
        XCTAssertEqual(value(for: "State", in: model), "Active")

        let labels = Set(model?.sections.flatMap(\.rows).map(\.label) ?? [])
        XCTAssertFalse(labels.contains("Remaining Ore"))
        XCTAssertFalse(labels.contains("Total Ore"))
    }

    func testBuilderShowsBoundMinerAndExhaustedState() {
        let model = OrePatchInspectorBuilder().build(
            patchID: 29,
            in: makeWorld(
                patch: OrePatch(
                    id: 29,
                    oreType: "ore_coal",
                    richness: .poor,
                    position: GridPosition(x: 9, y: 2),
                    totalOre: 150,
                    remainingOre: 0,
                    boundMinerID: 42
                )
            )
        )
        XCTAssertNotNil(model)
        XCTAssertEqual(value(for: "Type", in: model), "Coal")
        XCTAssertEqual(value(for: "Stage", in: model), "Exhausted")
        XCTAssertEqual(value(for: "Miner", in: model), "#42")
        XCTAssertEqual(value(for: "State", in: model), "Exhausted")
    }

    private func makeWorld(patch: OrePatch) -> WorldState {
        WorldState(
            tick: 0,
            entities: EntityStore(),
            orePatches: [patch],
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState()
        )
    }

    private func value(for label: String, in model: OrePatchInspectorViewModel?) -> String? {
        model?
            .sections
            .flatMap(\.rows)
            .first(where: { $0.label == label })?
            .value
    }
}
