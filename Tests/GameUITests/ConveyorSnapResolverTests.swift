import XCTest
@testable import GameUI
@testable import GameSimulation

final class ConveyorSnapResolverTests: XCTestCase {
    let resolver = ConveyorSnapResolver()

    func testNoNeighborsFallsBackToDefault() {
        let entities = EntityStore()
        let result = resolver.resolve(
            at: GridPosition(x: 5, y: 5),
            entities: entities,
            conveyorIO: [:],
            fallbackOutput: .east
        )
        XCTAssertEqual(result.inputDirection, .west)
        XCTAssertEqual(result.outputDirection, .east)
        XCTAssertFalse(result.hasConnection)
    }

    func testContinuesRunFromAdjacentConveyorOutput() {
        // Conveyor at (4,5) with output facing east (toward placement cell at (5,5))
        var entities = EntityStore()
        let neighborID = entities.spawnStructure(.conveyor, at: GridPosition(x: 4, y: 5), rotation: .east)
        let io: [EntityID: ConveyorIOConfig] = [
            neighborID: ConveyorIOConfig(inputDirection: .west, outputDirection: .east)
        ]

        let result = resolver.resolve(
            at: GridPosition(x: 5, y: 5),
            entities: entities,
            conveyorIO: io
        )

        // Should continue the run: input from west (facing the neighbor), output east
        XCTAssertEqual(result.inputDirection, .west)
        XCTAssertEqual(result.outputDirection, .east)
        XCTAssertTrue(result.hasConnection)
    }

    func testFeedsIntoAdjacentConveyorInput() {
        // Conveyor at (6,5) with input facing west (toward placement cell at (5,5))
        var entities = EntityStore()
        let neighborID = entities.spawnStructure(.conveyor, at: GridPosition(x: 6, y: 5), rotation: .east)
        let io: [EntityID: ConveyorIOConfig] = [
            neighborID: ConveyorIOConfig(inputDirection: .west, outputDirection: .east)
        ]

        let result = resolver.resolve(
            at: GridPosition(x: 5, y: 5),
            entities: entities,
            conveyorIO: io
        )

        // Should feed into the neighbor: output east (toward neighbor)
        XCTAssertEqual(result.outputDirection, .east)
        XCTAssertTrue(result.hasConnection)
    }

    func testSnapsToSplitterOutputPort() {
        // Splitter at (5,4) facing east → outputs left (north) and right (south)
        // Placement at (5,3) is north of splitter → splitter's left output faces north
        var entities = EntityStore()
        _ = entities.spawnStructure(.splitter, at: GridPosition(x: 5, y: 4), rotation: .east)

        let result = resolver.resolve(
            at: GridPosition(x: 5, y: 3),
            entities: entities,
            conveyorIO: [:]
        )

        // Adjacent to splitter's north output → belt input faces south (toward splitter)
        XCTAssertEqual(result.inputDirection, .south)
        XCTAssertEqual(result.outputDirection, .north)
        XCTAssertTrue(result.hasConnection)
    }

    func testSnapsToMergerInputPort() {
        // Merger at (5,4) facing east → inputs from left (north) and right (south)
        // Placement at (5,3) is north of merger → merger's left input faces north
        var entities = EntityStore()
        _ = entities.spawnStructure(.merger, at: GridPosition(x: 5, y: 4), rotation: .east)

        let result = resolver.resolve(
            at: GridPosition(x: 5, y: 3),
            entities: entities,
            conveyorIO: [:]
        )

        // Adjacent to merger's north input → belt output faces south (toward merger)
        XCTAssertEqual(result.outputDirection, .south)
        XCTAssertEqual(result.inputDirection, .north)
        XCTAssertTrue(result.hasConnection)
    }

    func testContinuingRunPreferredOverFeeding() {
        // Neighbor at (4,5) outputs east (toward us) — continue run
        // Neighbor at (6,5) inputs west (toward us) — feed into
        // Both qualify, but continuing a run has higher priority
        var entities = EntityStore()
        let westNeighborID = entities.spawnStructure(.conveyor, at: GridPosition(x: 4, y: 5), rotation: .east)
        let eastNeighborID = entities.spawnStructure(.conveyor, at: GridPosition(x: 6, y: 5), rotation: .east)
        let io: [EntityID: ConveyorIOConfig] = [
            westNeighborID: ConveyorIOConfig(inputDirection: .west, outputDirection: .east),
            eastNeighborID: ConveyorIOConfig(inputDirection: .west, outputDirection: .east)
        ]

        let result = resolver.resolve(
            at: GridPosition(x: 5, y: 5),
            entities: entities,
            conveyorIO: io
        )

        // Continue run from west neighbor (priority 10) beats feeding east neighbor (priority 8)
        XCTAssertEqual(result.inputDirection, .west)
        XCTAssertEqual(result.outputDirection, .east)
        XCTAssertTrue(result.hasConnection)
    }
}
