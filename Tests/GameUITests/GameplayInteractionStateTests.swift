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

    func testDragDrawStateLifecycle() {
        var interaction = GameplayInteractionState(mode: .build)
        let planner = GameplayDragDrawPlanner()

        interaction.beginDragDraw(at: GridPosition(x: 2, y: 3))
        interaction.updateDragDraw(at: GridPosition(x: 6, y: 5))
        XCTAssertTrue(interaction.isDragDrawActive)
        XCTAssertEqual(interaction.dragPreviewPath.count, 5)

        let path = interaction.finishDragDraw(using: planner)
        XCTAssertEqual(path.first, GridPosition(x: 2, y: 3))
        XCTAssertEqual(path.last, GridPosition(x: 6, y: 3))
        XCTAssertFalse(interaction.isDragDrawActive)
        XCTAssertTrue(interaction.dragPreviewPath.isEmpty)
    }

    func testPreviewAffordableCountUsesBuildCosts() {
        var interaction = GameplayInteractionState(mode: .build)
        interaction.beginDragDraw(at: GridPosition(x: 1, y: 1))
        interaction.updateDragDraw(at: GridPosition(x: 5, y: 1))

        let affordable = interaction.previewAffordableCount(
            for: .wall,
            inventory: ["wall_kit": 3]
        )
        XCTAssertEqual(affordable, 3)
    }
}
