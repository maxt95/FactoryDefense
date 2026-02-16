import XCTest
@testable import GamePlatform
@testable import GameSimulation

@MainActor
final class RuntimeControllerTests: XCTestCase {
    func testRuntimeTickLoopIsDeterministicForMatchingCommandStreams() {
        let first = GameRuntimeController(initialWorld: .bootstrap())
        let second = GameRuntimeController(initialWorld: .bootstrap())

        first.triggerWave()
        second.triggerWave()

        for tick in 0..<60 {
            if tick == 4 {
                first.placeStructure(.conveyor, at: GridPosition(x: 7, y: 4))
                second.placeStructure(.conveyor, at: GridPosition(x: 7, y: 4))
            }

            if tick == 8 {
                first.placeStructure(.wall, at: GridPosition(x: 10, y: 3))
                second.placeStructure(.wall, at: GridPosition(x: 10, y: 3))
            }

            _ = first.advanceTick()
            _ = second.advanceTick()
        }

        XCTAssertEqual(first.snapshot(), second.snapshot())
    }

    func testInputMapperProducesPlaceCommand() {
        let mapper = DefaultInputMapper()
        let event = InputEvent(
            timestamp: 1,
            device: .mouse,
            gesture: .placeStructure(type: .turretMount, position: GridPosition(x: 3, y: 2))
        )

        let command = mapper.map(event: event, tick: 10, actor: PlayerID(7))
        guard case .placeStructure(let request)? = command?.payload else {
            return XCTFail("Expected placeStructure command")
        }

        XCTAssertEqual(request.structure, .turretMount)
        XCTAssertEqual(request.position, GridPosition(x: 3, y: 2))
        XCTAssertEqual(command?.tick, 10)
        XCTAssertEqual(command?.actor, PlayerID(7))
    }

    func testTapGridUsesDefaultStructureWhenConfigured() {
        let mapper = DefaultInputMapper(defaultStructureOnTap: .wall)
        let event = InputEvent(
            timestamp: 1,
            device: .touch,
            gesture: .tapGrid(position: GridPosition(x: 5, y: 5))
        )

        let command = mapper.map(event: event, tick: 12, actor: PlayerID(1))
        guard case .placeStructure(let request)? = command?.payload else {
            return XCTFail("Expected tapGrid to map to placeStructure")
        }

        XCTAssertEqual(request.structure, .wall)
        XCTAssertEqual(request.position, GridPosition(x: 5, y: 5))
    }
}
