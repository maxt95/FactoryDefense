import XCTest
@testable import GameUI
@testable import GameSimulation

final class GameplayInteractionStateTests: XCTestCase {
    func testSelectBuildEntryEntersBuildModeAndSelectsEntry() {
        var interaction = GameplayInteractionState()
        var buildMenu = BuildMenuViewModel.productionPreset

        interaction.selectBuildEntry("conveyor", in: &buildMenu)

        XCTAssertEqual(interaction.mode, .build)
        XCTAssertEqual(buildMenu.selectedEntryID, "conveyor")
    }

    func testSelectingSameEntryInBuildModeTogglesBackToInteract() {
        var interaction = GameplayInteractionState(mode: .build)
        var buildMenu = BuildMenuViewModel.productionPreset
        buildMenu.select(entryID: "wall")

        interaction.selectBuildEntry("wall", in: &buildMenu)

        XCTAssertEqual(interaction.mode, .interact)
        XCTAssertEqual(buildMenu.selectedEntryID, "wall")
    }

    func testCompletePlacementIfSuccessfulOnlyExitsOnOk() {
        var interaction = GameplayInteractionState(mode: .build)

        let failed = interaction.completePlacementIfSuccessful(.occupied)
        XCTAssertFalse(failed)
        XCTAssertEqual(interaction.mode, .build)

        let succeeded = interaction.completePlacementIfSuccessful(.ok)
        XCTAssertTrue(succeeded)
        XCTAssertEqual(interaction.mode, .interact)
    }

    func testDemolishConfirmationFlow() {
        var interaction = GameplayInteractionState()

        interaction.requestDemolish(entityID: 42)
        XCTAssertEqual(interaction.pendingDemolishEntityID, 42)

        XCTAssertEqual(interaction.confirmDemolish(), 42)
        XCTAssertNil(interaction.pendingDemolishEntityID)

        interaction.requestDemolish(entityID: 7)
        interaction.cancelDemolish()
        XCTAssertNil(interaction.pendingDemolishEntityID)
    }
}
