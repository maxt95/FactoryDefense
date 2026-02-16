import XCTest
@testable import GameSimulation

final class OrePresentationTests: XCTestCase {
    func testOreTypeDisplayNameAndColorMappings() {
        XCTAssertEqual(OrePresentation.displayName(for: "ore_iron"), "Iron Ore")
        XCTAssertEqual(OrePresentation.displayName(for: "ore_copper"), "Copper Ore")
        XCTAssertEqual(OrePresentation.displayName(for: "ore_coal"), "Coal")
        XCTAssertEqual(OrePresentation.displayName(for: "ore_uranium"), "Ore Uranium")

        let iron = OrePresentation.color(for: "ore_iron")
        XCTAssertEqual(iron.x, 0.7216, accuracy: 0.0001)
        XCTAssertEqual(iron.y, 0.4510, accuracy: 0.0001)
        XCTAssertEqual(iron.z, 0.2000, accuracy: 0.0001)

        let copper = OrePresentation.color(for: "ore_copper")
        XCTAssertEqual(copper.x, 0.1804, accuracy: 0.0001)
        XCTAssertEqual(copper.y, 0.5451, accuracy: 0.0001)
        XCTAssertEqual(copper.z, 0.4784, accuracy: 0.0001)

        let coal = OrePresentation.color(for: "ore_coal")
        XCTAssertEqual(coal.x, 0.2275, accuracy: 0.0001)
        XCTAssertEqual(coal.y, 0.2275, accuracy: 0.0001)
        XCTAssertEqual(coal.z, 0.2275, accuracy: 0.0001)

        let unknown = OrePresentation.color(for: "ore_uranium")
        XCTAssertEqual(unknown.x, 0.58, accuracy: 0.0001)
        XCTAssertEqual(unknown.y, 0.58, accuracy: 0.0001)
        XCTAssertEqual(unknown.z, 0.58, accuracy: 0.0001)
    }

    func testOrePatchVisualStageThresholds() {
        XCTAssertEqual(makePatch(totalOre: 100, remainingOre: 100).visualStage, .full)
        XCTAssertEqual(makePatch(totalOre: 100, remainingOre: 75).visualStage, .full)
        XCTAssertEqual(makePatch(totalOre: 100, remainingOre: 74).visualStage, .partial)
        XCTAssertEqual(makePatch(totalOre: 100, remainingOre: 40).visualStage, .partial)
        XCTAssertEqual(makePatch(totalOre: 100, remainingOre: 39).visualStage, .low)
        XCTAssertEqual(makePatch(totalOre: 100, remainingOre: 1).visualStage, .low)
        XCTAssertEqual(makePatch(totalOre: 100, remainingOre: 0).visualStage, .exhausted)
    }

    private func makePatch(totalOre: Int, remainingOre: Int) -> OrePatch {
        OrePatch(
            id: 1,
            oreType: "ore_iron",
            richness: .normal,
            position: GridPosition(x: 0, y: 0),
            totalOre: totalOre,
            remainingOre: remainingOre
        )
    }
}
