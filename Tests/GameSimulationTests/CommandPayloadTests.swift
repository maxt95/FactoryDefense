import XCTest
@testable import GameSimulation

final class CommandPayloadTests: XCTestCase {
    func testCommandPayloadRoundTripSupportsNewCases() throws {
        let payloads: [CommandPayload] = [
            .placeStructure(
                BuildRequest(
                    structure: .splitter,
                    position: GridPosition(x: 4, y: 9),
                    rotation: .west
                )
            ),
            .removeStructure(entityID: 99),
            .placeConveyor(position: GridPosition(x: 7, y: 3), direction: .south),
            .configureConveyorIO(entityID: 7, inputDirection: .north, outputDirection: .east),
            .rotateBuilding(entityID: 42),
            .pinRecipe(entityID: 5, recipeID: "smelt_iron"),
            .extract,
            .triggerWave
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for payload in payloads {
            let data = try encoder.encode(payload)
            let decoded = try decoder.decode(CommandPayload.self, from: data)
            XCTAssertEqual(decoded, payload)
        }
    }

    func testSortTokenIncludesRotationAndNewCommandKinds() {
        let placeNorth = CommandPayload.placeStructure(
            BuildRequest(
                structure: .conveyor,
                position: GridPosition(x: 2, y: 3),
                rotation: .north
            )
        )
        let placeEast = CommandPayload.placeStructure(
            BuildRequest(
                structure: .conveyor,
                position: GridPosition(x: 2, y: 3),
                rotation: .east
            )
        )

        XCTAssertNotEqual(placeNorth.sortToken, placeEast.sortToken)
        XCTAssertEqual(CommandPayload.removeStructure(entityID: 7).sortToken, "remove:7")
        XCTAssertEqual(
            CommandPayload.configureConveyorIO(entityID: 7, inputDirection: .north, outputDirection: .east).sortToken,
            "conveyorIO:7:north:east"
        )
        XCTAssertEqual(CommandPayload.rotateBuilding(entityID: 7).sortToken, "rotate:7")
        XCTAssertEqual(CommandPayload.pinRecipe(entityID: 7, recipeID: "a").sortToken, "pin:7:a")
    }
}
