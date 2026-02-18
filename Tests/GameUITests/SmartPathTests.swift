import XCTest
@testable import GameUI
@testable import GameSimulation

final class SmartPathTests: XCTestCase {
    let planner = GameplayDragDrawPlanner()

    // MARK: - Straight Drag

    func testStraightEastDragProducesCorrectDirections() {
        let sequence = [
            GridPosition(x: 2, y: 2),
            GridPosition(x: 3, y: 2),
            GridPosition(x: 4, y: 2),
            GridPosition(x: 5, y: 2),
            GridPosition(x: 6, y: 2),
            GridPosition(x: 7, y: 2)
        ]
        let cells = planner.smartPath(cellSequence: sequence)

        XCTAssertEqual(cells.count, 6)
        for cell in cells {
            XCTAssertEqual(cell.inputDirection, .west)
            XCTAssertEqual(cell.outputDirection, .east)
            XCTAssertFalse(cell.isCorner)
        }
    }

    func testStraightNorthDragProducesCorrectDirections() {
        let sequence = [
            GridPosition(x: 5, y: 5),
            GridPosition(x: 5, y: 4),
            GridPosition(x: 5, y: 3),
            GridPosition(x: 5, y: 2)
        ]
        let cells = planner.smartPath(cellSequence: sequence)

        XCTAssertEqual(cells.count, 4)
        for cell in cells {
            XCTAssertEqual(cell.inputDirection, .south)
            XCTAssertEqual(cell.outputDirection, .north)
            XCTAssertFalse(cell.isCorner)
        }
    }

    // MARK: - L-Shaped Drag (Corner)

    func testLShapedDragInsertCorner() {
        // Drag east 3 tiles, then north 2 tiles
        let sequence = [
            GridPosition(x: 2, y: 5),
            GridPosition(x: 3, y: 5),
            GridPosition(x: 4, y: 5),
            GridPosition(x: 4, y: 4),
            GridPosition(x: 4, y: 3)
        ]
        let cells = planner.smartPath(cellSequence: sequence)

        XCTAssertEqual(cells.count, 5)

        // First two: east-facing straight
        XCTAssertEqual(cells[0].inputDirection, .west)
        XCTAssertEqual(cells[0].outputDirection, .east)
        XCTAssertFalse(cells[0].isCorner)

        XCTAssertEqual(cells[1].inputDirection, .west)
        XCTAssertEqual(cells[1].outputDirection, .east)
        XCTAssertFalse(cells[1].isCorner)

        // Corner at (4,5): input from west, output north
        XCTAssertEqual(cells[2].position, GridPosition(x: 4, y: 5))
        XCTAssertEqual(cells[2].inputDirection, .west)
        XCTAssertEqual(cells[2].outputDirection, .north)
        XCTAssertTrue(cells[2].isCorner)

        // Last two: north-facing straight
        XCTAssertEqual(cells[3].inputDirection, .south)
        XCTAssertEqual(cells[3].outputDirection, .north)
        XCTAssertFalse(cells[3].isCorner)

        XCTAssertEqual(cells[4].inputDirection, .south)
        XCTAssertEqual(cells[4].outputDirection, .north)
        XCTAssertFalse(cells[4].isCorner)
    }

    // MARK: - Rubber-Band Backtrack

    func testBacktrackTruncatesPath() {
        // Drag east 3, then back west 1
        let sequence = [
            GridPosition(x: 2, y: 2),
            GridPosition(x: 3, y: 2),
            GridPosition(x: 4, y: 2),
            GridPosition(x: 3, y: 2) // backtrack
        ]
        let cells = planner.smartPath(cellSequence: sequence)

        // Should truncate back to (3,2)
        XCTAssertEqual(cells.count, 2)
        XCTAssertEqual(cells.last?.position, GridPosition(x: 3, y: 2))
    }

    func testUTurnCausesRubberBand() {
        // Drag east then immediately west
        let sequence = [
            GridPosition(x: 5, y: 5),
            GridPosition(x: 6, y: 5),
            GridPosition(x: 7, y: 5),
            GridPosition(x: 6, y: 5),
            GridPosition(x: 5, y: 5)
        ]
        let cells = planner.smartPath(cellSequence: sequence)

        // Should rubber-band all the way back to just the start
        XCTAssertEqual(cells.count, 1)
        XCTAssertEqual(cells[0].position, GridPosition(x: 5, y: 5))
    }

    // MARK: - Consecutive Duplicates

    func testConsecutiveDuplicatesAreSkipped() {
        let sequence = [
            GridPosition(x: 2, y: 2),
            GridPosition(x: 2, y: 2), // duplicate
            GridPosition(x: 3, y: 2),
            GridPosition(x: 3, y: 2), // duplicate
            GridPosition(x: 4, y: 2)
        ]
        let cells = planner.smartPath(cellSequence: sequence)

        XCTAssertEqual(cells.count, 3)
        XCTAssertEqual(cells[0].position, GridPosition(x: 2, y: 2))
        XCTAssertEqual(cells[1].position, GridPosition(x: 3, y: 2))
        XCTAssertEqual(cells[2].position, GridPosition(x: 4, y: 2))
    }

    // MARK: - Single Cell

    func testSingleCellPathDefaultsToEast() {
        let sequence = [GridPosition(x: 5, y: 5)]
        let cells = planner.smartPath(cellSequence: sequence)

        XCTAssertEqual(cells.count, 1)
        XCTAssertEqual(cells[0].inputDirection, .west)
        XCTAssertEqual(cells[0].outputDirection, .east)
    }

    // MARK: - Diagonal Interpolation

    func testDiagonalJumpIsInterpolatedToCardinalSteps() {
        // Fast mouse jump: (2,2) → (4,4) — diagonal, 2 cells apart
        let sequence = [
            GridPosition(x: 2, y: 2),
            GridPosition(x: 4, y: 4)
        ]
        let cells = planner.smartPath(cellSequence: sequence)

        // Should interpolate: no two consecutive cells should be diagonal
        for i in 1..<cells.count {
            let prev = cells[i - 1].position
            let curr = cells[i].position
            let manhattan = abs(curr.x - prev.x) + abs(curr.y - prev.y)
            XCTAssertEqual(manhattan, 1, "Cells \(prev) and \(curr) are not cardinally adjacent")
        }
    }

    func testDiagonalDipDuringEastDragStaysStraight() {
        // Dragging east, cursor briefly dips one row down then back:
        // (2,2) → (3,2) → (4,3) → (5,2) → (6,2)
        // The (4,3) is a diagonal from (3,2), caused by fast mouse movement.
        // After interpolation + rubber-band, the path should not have a
        // perpendicular spike.
        let sequence = [
            GridPosition(x: 2, y: 2),
            GridPosition(x: 3, y: 2),
            GridPosition(x: 4, y: 3), // diagonal jump
            GridPosition(x: 5, y: 2), // diagonal back
            GridPosition(x: 6, y: 2)
        ]
        let cells = planner.smartPath(cellSequence: sequence)

        // Every consecutive pair should be cardinally adjacent
        for i in 1..<cells.count {
            let prev = cells[i - 1].position
            let curr = cells[i].position
            let manhattan = abs(curr.x - prev.x) + abs(curr.y - prev.y)
            XCTAssertEqual(manhattan, 1, "Cells \(prev) and \(curr) are not cardinally adjacent")
        }
    }

    func testSingleStepDiagonalIsResolvedToTwoCardinalSteps() {
        // Jump from (3,2) to (4,3) — one step diagonal
        let sequence = [
            GridPosition(x: 3, y: 2),
            GridPosition(x: 4, y: 3)
        ]
        let cells = planner.smartPath(cellSequence: sequence)

        // Should have 3 cells: (3,2), intermediate, (4,3)
        XCTAssertEqual(cells.count, 3)
        for i in 1..<cells.count {
            let prev = cells[i - 1].position
            let curr = cells[i].position
            let manhattan = abs(curr.x - prev.x) + abs(curr.y - prev.y)
            XCTAssertEqual(manhattan, 1)
        }
    }

    func testLongDiagonalJumpIsFullyInterpolated() {
        // Jump from (2,2) to (5,5) — 3 steps diagonal
        let sequence = [
            GridPosition(x: 2, y: 2),
            GridPosition(x: 5, y: 5)
        ]
        let cells = planner.smartPath(cellSequence: sequence)

        // Should be 7 cells (3 east + 3 south + 1 start = 7, or similar)
        XCTAssertGreaterThanOrEqual(cells.count, 7)
        for i in 1..<cells.count {
            let prev = cells[i - 1].position
            let curr = cells[i].position
            let manhattan = abs(curr.x - prev.x) + abs(curr.y - prev.y)
            XCTAssertEqual(manhattan, 1, "Cells \(prev) and \(curr) are not cardinally adjacent")
        }
        XCTAssertEqual(cells.first?.position, GridPosition(x: 2, y: 2))
        XCTAssertEqual(cells.last?.position, GridPosition(x: 5, y: 5))
    }

    // MARK: - Zigzag Removal

    func testPerpendicularSpikeRemovedDuringEastDrag() {
        // The --|-- bug: dragging east, cursor dips south one cell then back.
        // After interpolation this becomes a 2-cell perpendicular detour.
        // Input: (2,2) → (3,2) → (3,3) → (3,2) would rubber-band, but the
        // more realistic case is interpolation creating: ...(3,2)→(3,3)→(4,3)→(4,2)...
        // which is a zigzag spike. removeZigzags should collapse it.
        let sequence = [
            GridPosition(x: 2, y: 2),
            GridPosition(x: 3, y: 2),
            GridPosition(x: 3, y: 3), // perpendicular dip
            GridPosition(x: 4, y: 3), // continue east at wrong y
            GridPosition(x: 4, y: 2), // come back to correct y
            GridPosition(x: 5, y: 2),
            GridPosition(x: 6, y: 2)
        ]
        let cells = planner.smartPath(cellSequence: sequence)

        // The path should be a clean east run with no perpendicular spikes
        for cell in cells {
            XCTAssertFalse(cell.isCorner, "No corners expected in a straight run, got corner at \(cell.position)")
        }
        // All cells should be cardinally adjacent
        for i in 1..<cells.count {
            let prev = cells[i - 1].position
            let curr = cells[i].position
            let manhattan = abs(curr.x - prev.x) + abs(curr.y - prev.y)
            XCTAssertEqual(manhattan, 1, "Cells \(prev) and \(curr) are not cardinally adjacent")
        }
    }

    func testUTurnSpikeRemoved() {
        // A single cell jutting perpendicular then immediately returning:
        // (2,2) → (3,2) → (3,3) → (3,2) rubber-bands, but if it arrives
        // as interpolated positions: (3,2) → (3,3) → (3,2) that's a U-turn.
        let sequence = [
            GridPosition(x: 2, y: 2),
            GridPosition(x: 3, y: 2),
            GridPosition(x: 4, y: 2),
            GridPosition(x: 4, y: 3), // spike south
            GridPosition(x: 4, y: 2), // immediate return — rubber-band catches this
            GridPosition(x: 5, y: 2)
        ]
        let cells = planner.smartPath(cellSequence: sequence)

        // Should be a clean straight east path after rubber-band + zigzag removal
        for i in 1..<cells.count {
            let prev = cells[i - 1].position
            let curr = cells[i].position
            let manhattan = abs(curr.x - prev.x) + abs(curr.y - prev.y)
            XCTAssertEqual(manhattan, 1)
        }
    }

    func testTwoCellZigzagCollapsed() {
        // Explicit 2-cell zigzag: A(2,2) B(2,3) C(3,3) D(3,2) — A→D is 1 step east
        let sequence = [
            GridPosition(x: 1, y: 2),
            GridPosition(x: 2, y: 2),
            GridPosition(x: 2, y: 3), // detour south
            GridPosition(x: 3, y: 3), // detour east at wrong y
            GridPosition(x: 3, y: 2), // back to correct y
            GridPosition(x: 4, y: 2)
        ]
        let cells = planner.smartPath(cellSequence: sequence)

        // The 2-cell detour (2,3)→(3,3) should be collapsed
        let positions = cells.map(\.position)
        XCTAssertFalse(positions.contains(GridPosition(x: 2, y: 3)), "Zigzag cell (2,3) should be removed")
        XCTAssertFalse(positions.contains(GridPosition(x: 3, y: 3)), "Zigzag cell (3,3) should be removed")
    }

    // MARK: - Diagonal Rejection in accumulateConveyorDragCell

    func testAccumulateRejectsDiagonalInput() {
        var interaction = GameplayInteractionState(mode: .build)
        interaction.beginDragDraw(at: GridPosition(x: 2, y: 2))

        // Cardinal moves — accepted
        interaction.accumulateConveyorDragCell(GridPosition(x: 3, y: 2))
        XCTAssertEqual(interaction.dragCellSequence.count, 2)

        // Diagonal move — rejected
        interaction.accumulateConveyorDragCell(GridPosition(x: 4, y: 3))
        XCTAssertEqual(interaction.dragCellSequence.count, 2, "Diagonal input should be rejected")

        // Next cardinal move — accepted
        interaction.accumulateConveyorDragCell(GridPosition(x: 4, y: 2))
        XCTAssertEqual(interaction.dragCellSequence.count, 3)
    }

    func testAccumulateAcceptsCardinalGap() {
        // Fast mouse can skip cells along one axis — those should be accepted
        var interaction = GameplayInteractionState(mode: .build)
        interaction.beginDragDraw(at: GridPosition(x: 2, y: 2))

        // Jump 2 cells east (cardinal gap, not diagonal)
        interaction.accumulateConveyorDragCell(GridPosition(x: 4, y: 2))
        XCTAssertEqual(interaction.dragCellSequence.count, 2, "Cardinal gap should be accepted")
    }

    // MARK: - assignDirections

    func testAssignDirectionsEmptyReturnsEmpty() {
        let cells = GameplayDragDrawPlanner.assignDirections(to: [])
        XCTAssertTrue(cells.isEmpty)
    }
}
