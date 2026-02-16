import XCTest
@testable import GameContent

final class ContentValidatorTests: XCTestCase {
    func testBootstrapContentHasNoValidationErrors() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentURL = root.appendingPathComponent("Content/bootstrap")

        let bundle = try ContentLoader().loadBundle(from: contentURL)
        let errors = ContentValidator().validate(bundle: bundle)

        XCTAssertTrue(errors.isEmpty, "Expected no validation errors, got: \(errors)")
    }

    func testMissingEnemyReferenceIsDetected() {
        let bundle = GameContentBundle(
            items: [ItemDef(id: "ore_iron", name: "Iron Ore", kind: .raw)],
            recipes: [],
            turrets: [],
            enemies: [],
            waves: [WaveDef(index: 1, spawnBudget: 4, composition: [EnemyGroup(enemyID: "ghost", count: 1, delayTicks: 0)])],
            techNodes: [],
            board: .starter
        )

        let errors = ContentValidator().validate(bundle: bundle)
        XCTAssertTrue(errors.contains(.missingReference(owner: "wave:1", reference: "ghost")))
    }

    func testInvalidBoardIsDetected() {
        let bundle = GameContentBundle(
            items: [],
            recipes: [],
            turrets: [],
            enemies: [],
            waves: [],
            techNodes: [],
            board: BoardDef(
                width: 10,
                height: 6,
                basePosition: BoardPointDef(x: 20, y: 3),
                spawnEdgeX: 12,
                spawnYMin: 4,
                spawnYMax: 3
            )
        )

        let errors = ContentValidator().validate(bundle: bundle)
        XCTAssertTrue(errors.contains(.invalidBoard(reason: "base position is out of bounds")))
        XCTAssertTrue(errors.contains(.invalidBoard(reason: "spawnEdgeX is out of bounds")))
        XCTAssertTrue(errors.contains(.invalidBoard(reason: "spawn Y range is invalid")))
    }
}
