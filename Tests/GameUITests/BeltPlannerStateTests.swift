import XCTest
@testable import GameUI
@testable import GameSimulation

final class BeltPlannerStateTests: XCTestCase {
    func testHFirstPathHorizontalThenVertical() {
        let cells = BeltPlannerState.manhattanPath(
            from: GridPosition(x: 2, y: 2),
            to: GridPosition(x: 8, y: 6),
            variant: .hFirst
        )

        // 7 horizontal (2→8) + 4 vertical (2→6), corner shared = 6+4+1 = 11
        let positions = cells.map(\.position)
        XCTAssertEqual(positions.first, GridPosition(x: 2, y: 2))
        XCTAssertEqual(positions.last, GridPosition(x: 8, y: 6))

        // All positions should be unique
        XCTAssertEqual(Set(positions).count, positions.count)

        // Should have at least one corner where direction changes
        let corners = cells.filter(\.isCorner)
        XCTAssertFalse(corners.isEmpty, "H-first path with both dx and dy should have a corner")
    }

    func testVFirstPathVerticalThenHorizontal() {
        let cells = BeltPlannerState.manhattanPath(
            from: GridPosition(x: 2, y: 2),
            to: GridPosition(x: 8, y: 6),
            variant: .vFirst
        )

        let positions = cells.map(\.position)
        XCTAssertEqual(positions.first, GridPosition(x: 2, y: 2))
        XCTAssertEqual(positions.last, GridPosition(x: 8, y: 6))

        XCTAssertEqual(Set(positions).count, positions.count)

        let corners = cells.filter(\.isCorner)
        XCTAssertFalse(corners.isEmpty, "V-first path with both dx and dy should have a corner")
    }

    func testSameStartAndEndProducesSingleCell() {
        let cells = BeltPlannerState.manhattanPath(
            from: GridPosition(x: 5, y: 5),
            to: GridPosition(x: 5, y: 5),
            variant: .hFirst
        )

        XCTAssertEqual(cells.count, 1)
        XCTAssertEqual(cells[0].position, GridPosition(x: 5, y: 5))
    }

    func testHorizontalOnlyPathHasNoCorners() {
        let cells = BeltPlannerState.manhattanPath(
            from: GridPosition(x: 2, y: 5),
            to: GridPosition(x: 8, y: 5),
            variant: .hFirst
        )

        XCTAssertEqual(cells.count, 7) // 2,3,4,5,6,7,8
        for cell in cells {
            XCTAssertFalse(cell.isCorner)
            XCTAssertEqual(cell.inputDirection, .west)
            XCTAssertEqual(cell.outputDirection, .east)
        }
    }

    func testVerticalOnlyPathHasNoCorners() {
        let cells = BeltPlannerState.manhattanPath(
            from: GridPosition(x: 5, y: 2),
            to: GridPosition(x: 5, y: 6),
            variant: .vFirst
        )

        XCTAssertEqual(cells.count, 5) // 2,3,4,5,6
        for cell in cells {
            XCTAssertFalse(cell.isCorner)
            XCTAssertEqual(cell.inputDirection, .north)
            XCTAssertEqual(cell.outputDirection, .south)
        }
    }

    func testCycleVariant() {
        var planner = BeltPlannerState()
        XCTAssertEqual(planner.selectedVariant, .hFirst)

        planner.cycleVariant()
        XCTAssertEqual(planner.selectedVariant, .vFirst)

        planner.cycleVariant()
        XCTAssertEqual(planner.selectedVariant, .hFirst)
    }

    func testSetStartActivatesPlanner() {
        var planner = BeltPlannerState()
        XCTAssertFalse(planner.isActive)

        planner.setStart(GridPosition(x: 2, y: 2))
        XCTAssertTrue(planner.isActive)
        XCTAssertNotNil(planner.startPin)
        XCTAssertNil(planner.endPin)
    }

    func testSetEndComputesPath() {
        var planner = BeltPlannerState()
        planner.setStart(GridPosition(x: 2, y: 2))
        planner.setEnd(GridPosition(x: 6, y: 2))

        XCTAssertFalse(planner.previewPath.isEmpty)
        XCTAssertEqual(planner.previewPath.first?.position, GridPosition(x: 2, y: 2))
        XCTAssertEqual(planner.previewPath.last?.position, GridPosition(x: 6, y: 2))
    }

    func testConfirmReturnsPathAndResets() {
        var planner = BeltPlannerState()
        planner.setStart(GridPosition(x: 2, y: 2))
        planner.setEnd(GridPosition(x: 6, y: 2))

        let path = planner.confirm()
        XCTAssertFalse(path.isEmpty)
        XCTAssertFalse(planner.isActive)
        XCTAssertNil(planner.startPin)
        XCTAssertNil(planner.endPin)
        XCTAssertTrue(planner.previewPath.isEmpty)
    }

    func testResetClearsEverything() {
        var planner = BeltPlannerState()
        planner.setStart(GridPosition(x: 2, y: 2))
        planner.setEnd(GridPosition(x: 6, y: 2))
        planner.reset()

        XCTAssertFalse(planner.isActive)
        XCTAssertNil(planner.startPin)
        XCTAssertNil(planner.endPin)
        XCTAssertTrue(planner.previewPath.isEmpty)
    }
}
