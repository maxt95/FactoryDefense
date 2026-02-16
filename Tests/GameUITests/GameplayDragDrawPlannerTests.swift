import XCTest
@testable import GameUI
@testable import GameSimulation

final class GameplayDragDrawPlannerTests: XCTestCase {
    func testSupportsDragDrawOnlyForConveyorAndWall() {
        let planner = GameplayDragDrawPlanner()
        XCTAssertTrue(planner.supportsDragDraw(for: .conveyor))
        XCTAssertTrue(planner.supportsDragDraw(for: .wall))
        XCTAssertFalse(planner.supportsDragDraw(for: .miner))
    }

    func testDominantAxisPathSnapsHorizontalWhenXMagnitudeIsGreater() {
        let planner = GameplayDragDrawPlanner()
        let path = planner.dominantAxisPath(
            from: GridPosition(x: 1, y: 1),
            to: GridPosition(x: 5, y: 3)
        )

        XCTAssertEqual(
            path,
            [
                GridPosition(x: 1, y: 1),
                GridPosition(x: 2, y: 1),
                GridPosition(x: 3, y: 1),
                GridPosition(x: 4, y: 1),
                GridPosition(x: 5, y: 1)
            ]
        )
    }

    func testDominantAxisPathSnapsVerticalWhenYMagnitudeIsGreater() {
        let planner = GameplayDragDrawPlanner()
        let path = planner.dominantAxisPath(
            from: GridPosition(x: 4, y: 4),
            to: GridPosition(x: 2, y: -1)
        )

        XCTAssertEqual(
            path,
            [
                GridPosition(x: 4, y: 4),
                GridPosition(x: 4, y: 3),
                GridPosition(x: 4, y: 2),
                GridPosition(x: 4, y: 1),
                GridPosition(x: 4, y: 0),
                GridPosition(x: 4, y: -1)
            ]
        )
    }
}
