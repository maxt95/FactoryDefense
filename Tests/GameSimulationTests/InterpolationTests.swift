import XCTest
@testable import GameSimulation

final class InterpolationTests: XCTestCase {
    func testInterpolatedFrameAlphaProducesBlendedValues() {
        let engine = SimulationEngine(worldState: .bootstrap())
        _ = engine.step()

        let frame = engine.interpolatedFrame(alpha: 0.5)
        XCTAssertEqual(frame.alpha, 0.5, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(frame.blendedBaseIntegrity, 0)
        XCTAssertGreaterThanOrEqual(frame.blendedCurrency, 0)
    }
}
