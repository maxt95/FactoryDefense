import XCTest
@testable import GameSimulation

final class SimulationDeterminismTests: XCTestCase {
    func testSameCommandsProduceIdenticalSnapshots() {
        let first = SimulationEngine(worldState: .bootstrap())
        let second = SimulationEngine(worldState: .bootstrap())

        let commands = [
            PlayerCommand(tick: 1, actor: PlayerID(1), payload: .triggerWave),
            PlayerCommand(tick: 5, actor: PlayerID(1), payload: .placeStructure(BuildRequest(structure: .wall, position: GridPosition(x: 1, y: 1)))),
            PlayerCommand(tick: 8, actor: PlayerID(2), payload: .placeStructure(BuildRequest(structure: .turretMount, position: GridPosition(x: 2, y: 1)))),
            PlayerCommand(tick: 400, actor: PlayerID(1), payload: .placeStructure(BuildRequest(structure: .conveyor, position: GridPosition(x: 3, y: 1))))
        ]

        commands.forEach(first.enqueue)
        commands.forEach(second.enqueue)

        _ = first.run(ticks: 500)
        _ = second.run(ticks: 500)

        XCTAssertEqual(first.makeSnapshot(), second.makeSnapshot())
    }
}
