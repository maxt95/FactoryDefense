import XCTest
@testable import GameUI
@testable import GameSimulation

final class FlowBrushStateTests: XCTestCase {
    func testStrokeLifecycle() {
        var brush = FlowBrushState()
        XCTAssertFalse(brush.isActive)

        brush.beginStroke(at: GridPosition(x: 2, y: 2))
        XCTAssertTrue(brush.isActive)
        XCTAssertEqual(brush.strokeCells.count, 1)

        brush.extendStroke(to: GridPosition(x: 3, y: 2))
        brush.extendStroke(to: GridPosition(x: 4, y: 2))
        XCTAssertEqual(brush.strokeCells.count, 3)

        let changes = brush.finishStroke()
        XCTAssertFalse(brush.isActive)
        XCTAssertTrue(brush.strokeCells.isEmpty)
        XCTAssertEqual(changes.count, 3)
    }

    func testStrokeDirectionsMatchMovement() {
        var brush = FlowBrushState()
        brush.beginStroke(at: GridPosition(x: 2, y: 5))
        brush.extendStroke(to: GridPosition(x: 3, y: 5))
        brush.extendStroke(to: GridPosition(x: 4, y: 5))
        brush.extendStroke(to: GridPosition(x: 5, y: 5))

        let changes = brush.finishStroke()

        XCTAssertEqual(changes.count, 4)
        for change in changes {
            XCTAssertEqual(change.newInput, .west)
            XCTAssertEqual(change.newOutput, .east)
        }
    }

    func testWestwardStroke() {
        var brush = FlowBrushState()
        brush.beginStroke(at: GridPosition(x: 5, y: 5))
        brush.extendStroke(to: GridPosition(x: 4, y: 5))
        brush.extendStroke(to: GridPosition(x: 3, y: 5))

        let changes = brush.finishStroke()

        XCTAssertEqual(changes.count, 3)
        for change in changes {
            XCTAssertEqual(change.newInput, .east)
            XCTAssertEqual(change.newOutput, .west)
        }
    }

    func testRubberBandOnBacktrack() {
        var brush = FlowBrushState()
        brush.beginStroke(at: GridPosition(x: 2, y: 2))
        brush.extendStroke(to: GridPosition(x: 3, y: 2))
        brush.extendStroke(to: GridPosition(x: 4, y: 2))
        brush.extendStroke(to: GridPosition(x: 3, y: 2)) // backtrack

        XCTAssertEqual(brush.strokeCells.count, 2)
        XCTAssertEqual(brush.strokeCells.last, GridPosition(x: 3, y: 2))
    }

    func testCancelStrokeClearsState() {
        var brush = FlowBrushState()
        brush.beginStroke(at: GridPosition(x: 2, y: 2))
        brush.extendStroke(to: GridPosition(x: 3, y: 2))
        brush.cancelStroke()

        XCTAssertFalse(brush.isActive)
        XCTAssertTrue(brush.strokeCells.isEmpty)
        XCTAssertTrue(brush.proposedChanges.isEmpty)
    }

    func testSingleCellStrokeProducesNoChanges() {
        var brush = FlowBrushState()
        brush.beginStroke(at: GridPosition(x: 5, y: 5))

        let changes = brush.finishStroke()
        XCTAssertTrue(changes.isEmpty)
    }

    func testExtendWithoutBeginIsIgnored() {
        var brush = FlowBrushState()
        brush.extendStroke(to: GridPosition(x: 3, y: 3))
        XCTAssertFalse(brush.isActive)
        XCTAssertTrue(brush.strokeCells.isEmpty)
    }
}
