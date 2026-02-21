import XCTest
@testable import GameUI

final class TutorialTypesTests: XCTestCase {
    func testPowerIntroStepRequiresPowerPlantPlacement() {
        guard let step = TutorialSequence.defaultTutorial.steps.first(where: { $0.id == "power_intro" }) else {
            return XCTFail("Missing power_intro tutorial step")
        }

        guard case .uiElement(let anchorKey) = step.spotlight else {
            return XCTFail("power_intro should spotlight build menu")
        }
        XCTAssertEqual(anchorKey, "buildMenu")

        guard case .placeStructure(let structure) = step.completionCondition else {
            return XCTFail("power_intro should complete on placing power plant")
        }
        XCTAssertEqual(structure, .powerPlant)
    }
}
