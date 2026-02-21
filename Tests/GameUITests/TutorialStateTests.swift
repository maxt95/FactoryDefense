import XCTest
@testable import GameUI
import GameSimulation

final class TutorialStateTests: XCTestCase {
    @MainActor
    func testOreTutorialSpotlightUsesRegionAroundNearestPatch() throws {
        let controller = TutorialStateController()
        let world = WorldState.bootstrap()
        guard let step = TutorialSequence.defaultTutorial.steps.first(where: { $0.id == "ore_patches" }) else {
            return XCTFail("Missing ore_patches step in tutorial sequence")
        }

        let nearest = world.orePatches.min { lhs, rhs in
            let base = world.board.basePosition
            let distA = abs(lhs.position.x - base.x) + abs(lhs.position.y - base.y)
            let distB = abs(rhs.position.x - base.x) + abs(rhs.position.y - base.y)
            return distA < distB
        }
        guard let nearest else {
            return XCTFail("Expected at least one ore patch")
        }

        let target = controller.resolvedSpotlight(for: step, world: world)
        guard case .gridRegion(let origin, let width, let height) = target else {
            return XCTFail("Expected ore spotlight to resolve to grid region")
        }

        XCTAssertTrue(width >= 1 && width <= 3)
        XCTAssertTrue(height >= 1 && height <= 3)
        XCTAssertGreaterThanOrEqual(origin.x, 0)
        XCTAssertGreaterThanOrEqual(origin.y, 0)
        XCTAssertLessThan(origin.x + width, world.board.width + 1)
        XCTAssertLessThan(origin.y + height, world.board.height + 1)
        XCTAssertGreaterThanOrEqual(nearest.position.x, origin.x)
        XCTAssertGreaterThanOrEqual(nearest.position.y, origin.y)
        XCTAssertLessThan(nearest.position.x, origin.x + width)
        XCTAssertLessThan(nearest.position.y, origin.y + height)
    }

    @MainActor
    func testPlaceMinerTutorialSpotlightUsesSingleGridCell() throws {
        let controller = TutorialStateController()
        let world = WorldState.bootstrap()
        guard let step = TutorialSequence.defaultTutorial.steps.first(where: { $0.id == "place_miner" }) else {
            return XCTFail("Missing place_miner step in tutorial sequence")
        }

        let target = controller.resolvedSpotlight(for: step, world: world)
        guard case .gridPosition(let position) = target else {
            return XCTFail("Expected place_miner spotlight to resolve to grid position")
        }

        let nearest = world.orePatches.min { lhs, rhs in
            let base = world.board.basePosition
            let distA = abs(lhs.position.x - base.x) + abs(lhs.position.y - base.y)
            let distB = abs(rhs.position.x - base.x) + abs(rhs.position.y - base.y)
            return distA < distB
        }
        guard let nearest else {
            return XCTFail("Expected at least one ore patch")
        }
        let manhattan = abs(position.x - nearest.position.x) + abs(position.y - nearest.position.y)
        XCTAssertEqual(manhattan, 1, "Miner placement spotlight should be adjacent to the nearest patch, not on it")

        let placement = PlacementValidator().canPlace(
            .miner,
            at: position,
            targetPatchID: nearest.id,
            in: world
        )
        XCTAssertEqual(placement, .ok)
    }
}
