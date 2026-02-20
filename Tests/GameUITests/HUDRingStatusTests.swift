import XCTest
@testable import GameUI
@testable import GameSimulation

final class HUDRingStatusTests: XCTestCase {
    func testHUDBuildIncludesRingStatesAndVisibleCounts() {
        let world = WorldState(
            tick: 40,
            entities: EntityStore(),
            orePatches: [
                OrePatch(
                    id: 1,
                    oreType: "ore_iron",
                    richness: .normal,
                    position: GridPosition(x: 4, y: 4),
                    revealRing: 0,
                    isRevealed: true,
                    totalOre: 500,
                    remainingOre: 500
                ),
                OrePatch(
                    id: 2,
                    oreType: "ore_copper",
                    richness: .normal,
                    position: GridPosition(x: 12, y: 12),
                    revealRing: 1,
                    isRevealed: true,
                    totalOre: 400,
                    remainingOre: 400
                )
            ],
            oreLifecycle: OreLifecycleState(
                ringStates: [0: .revealed, 1: .surveying, 2: .locked, 3: .locked],
                surveyEndTickByRing: [1: 100],
                nextPatchID: 3
            ),
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(phase: .playing, difficulty: .normal, seed: 55)
        )

        let hud = HUDViewModel.build(from: world).snapshot
        let byRing = Dictionary(uniqueKeysWithValues: hud.oreRings.map { ($0.ringIndex, $0) })

        XCTAssertEqual(byRing[0]?.state, .revealed)
        XCTAssertEqual(byRing[0]?.visiblePatchCount, 1)
        XCTAssertEqual(byRing[1]?.state, .surveying)
        XCTAssertEqual(byRing[1]?.visiblePatchCount, 1)
        XCTAssertEqual(byRing[2]?.state, .locked)
    }

    func testSurveyRingCountdownUsesRemainingTicks() {
        let world = WorldState(
            tick: 135,
            entities: EntityStore(),
            orePatches: [],
            oreLifecycle: OreLifecycleState(
                ringStates: [0: .revealed, 1: .locked, 2: .surveying, 3: .locked],
                surveyEndTickByRing: [2: 180],
                nextPatchID: 1
            ),
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(phase: .playing, difficulty: .normal, seed: 1)
        )

        let hud = HUDViewModel.build(from: world).snapshot
        let ringTwo = hud.oreRings.first(where: { $0.ringIndex == 2 })
        XCTAssertEqual(ringTwo?.remainingSurveyTicks, 45)
    }
}
