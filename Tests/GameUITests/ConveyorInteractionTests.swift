import XCTest
@testable import GameUI
@testable import GameSimulation

final class ConveyorInteractionTests: XCTestCase {
    // MARK: - Mode Transitions

    func testEnterEditBeltsModeFromInteract() {
        var interaction = GameplayInteractionState()
        XCTAssertEqual(interaction.mode, .interact)

        interaction.enterEditBeltsMode()
        XCTAssertEqual(interaction.mode, .editBelts)
    }

    func testExitEditBeltsModeReturnsToInteract() {
        var interaction = GameplayInteractionState(mode: .editBelts)
        interaction.exitEditBeltsMode()
        XCTAssertEqual(interaction.mode, .interact)
    }

    func testEnterPlanBeltModeFromInteract() {
        var interaction = GameplayInteractionState()
        interaction.enterPlanBeltMode()
        XCTAssertEqual(interaction.mode, .planBelt)
    }

    func testExitPlanBeltModeReturnsToInteract() {
        var interaction = GameplayInteractionState(mode: .planBelt)
        interaction.exitPlanBeltMode()
        XCTAssertEqual(interaction.mode, .interact)
    }

    func testEnterEditBeltsClearsDragDraw() {
        var interaction = GameplayInteractionState(mode: .build)
        interaction.beginDragDraw(at: GridPosition(x: 2, y: 2))
        XCTAssertTrue(interaction.isDragDrawActive)

        interaction.enterEditBeltsMode()
        XCTAssertFalse(interaction.isDragDrawActive)
        XCTAssertEqual(interaction.mode, .editBelts)
    }

    func testExitBuildModeClearsQuickEditTarget() {
        var interaction = GameplayInteractionState(mode: .build)
        interaction.quickEditTarget = 42
        interaction.exitBuildMode()

        XCTAssertNil(interaction.quickEditTarget)
    }

    // MARK: - Conveyor Smart Drag

    func testAccumulateConveyorDragCellBuildsCellSequence() {
        var interaction = GameplayInteractionState(mode: .build)
        interaction.beginDragDraw(at: GridPosition(x: 2, y: 2))

        interaction.accumulateConveyorDragCell(GridPosition(x: 3, y: 2))
        interaction.accumulateConveyorDragCell(GridPosition(x: 4, y: 2))
        interaction.accumulateConveyorDragCell(GridPosition(x: 5, y: 2))

        XCTAssertEqual(interaction.dragCellSequence.count, 4) // start + 3 accumulated
        XCTAssertEqual(interaction.dragPreviewPath.count, 4)
        XCTAssertEqual(interaction.dragPreviewCells.count, 4)
    }

    func testAccumulateSkipsConsecutiveDuplicates() {
        var interaction = GameplayInteractionState(mode: .build)
        interaction.beginDragDraw(at: GridPosition(x: 2, y: 2))

        interaction.accumulateConveyorDragCell(GridPosition(x: 2, y: 2)) // duplicate of start
        interaction.accumulateConveyorDragCell(GridPosition(x: 3, y: 2))

        XCTAssertEqual(interaction.dragCellSequence.count, 2) // start + (3,2)
    }

    func testFinishConveyorDragDrawReturnsCellsAndClears() {
        var interaction = GameplayInteractionState(mode: .build)
        interaction.beginDragDraw(at: GridPosition(x: 2, y: 2))
        interaction.accumulateConveyorDragCell(GridPosition(x: 3, y: 2))
        interaction.accumulateConveyorDragCell(GridPosition(x: 4, y: 2))

        let cells = interaction.finishConveyorDragDraw()
        XCTAssertEqual(cells.count, 3)
        XCTAssertFalse(interaction.isDragDrawActive)
        XCTAssertTrue(interaction.dragPreviewPath.isEmpty)
        XCTAssertTrue(interaction.dragCellSequence.isEmpty)
    }

    // MARK: - Stay in Build Mode

    func testConveyorDragDrawDoesNotExitBuildMode() {
        var interaction = GameplayInteractionState(mode: .build)
        interaction.beginDragDraw(at: GridPosition(x: 2, y: 2))
        interaction.accumulateConveyorDragCell(GridPosition(x: 3, y: 2))
        _ = interaction.finishConveyorDragDraw()

        // Mode should NOT change — build mode stays
        XCTAssertEqual(interaction.mode, .build)
    }

    // MARK: - Quick Edit Target

    func testQuickEditTargetInitiallyNil() {
        let interaction = GameplayInteractionState()
        XCTAssertNil(interaction.quickEditTarget)
    }

    func testQuickEditTargetCanBeSet() {
        var interaction = GameplayInteractionState()
        interaction.quickEditTarget = 42
        XCTAssertEqual(interaction.quickEditTarget, 42)
    }

    // MARK: - New Modes in allCases

    func testAllCasesIncludesNewModes() {
        let allModes = GameplayInteractionMode.allCases
        XCTAssertTrue(allModes.contains(.editBelts))
        XCTAssertTrue(allModes.contains(.planBelt))
    }
}
