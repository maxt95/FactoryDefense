import XCTest
@testable import GameSimulation
@testable import GameUI

@MainActor
final class PlacementFeedbackControllerTests: XCTestCase {
    func testConsumePlacementRejectedSetsOverrideResult() {
        let controller = PlacementFeedbackController()
        controller.consume(
            events: [
                SimEvent(
                    tick: 10,
                    kind: .placementRejected,
                    placementReason: .occupied
                )
            ],
            durationSeconds: 1
        )

        XCTAssertEqual(controller.overrideResult, .occupied)
        XCTAssertEqual(controller.displayedResult(current: .ok), .occupied)
    }

    func testOverrideClearsAfterDuration() async {
        let controller = PlacementFeedbackController()
        controller.consume(
            events: [
                SimEvent(
                    tick: 10,
                    kind: .placementRejected,
                    placementReason: .outOfBounds
                )
            ],
            durationSeconds: 0.05
        )
        XCTAssertEqual(controller.overrideResult, .outOfBounds)

        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertNil(controller.overrideResult)
    }
}
