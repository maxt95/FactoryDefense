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
            techNodes: []
        )

        let errors = ContentValidator().validate(bundle: bundle)
        XCTAssertTrue(errors.contains(.missingReference(owner: "wave:1", reference: "ghost")))
    }
}
