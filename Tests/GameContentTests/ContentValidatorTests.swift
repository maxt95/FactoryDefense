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

    func testInvalidDifficultyAndHQAreDetected() {
        let bundle = GameContentBundle(
            items: [ItemDef(id: "ore_iron", name: "Iron Ore", kind: .raw)],
            recipes: [],
            turrets: [],
            enemies: [],
            waves: [],
            techNodes: [],
            board: .starter,
            hq: HQDef(
                id: "hq",
                displayName: "Headquarters",
                footprint: HQFootprintDef(width: 3, height: 2),
                health: 0,
                storageCapacity: 0,
                powerDraw: 0,
                startingResources: HQStartingResourcesDef(
                    easy: ["ghost_item": 1],
                    normal: [:],
                    hard: [:]
                )
            ),
            difficulty: DifficultyConfigDef(
                easy: DifficultyDef(
                    gracePeriodSeconds: 0,
                    interWaveGapBase: 10,
                    interWaveGapFloor: 20,
                    gapCompressionPerWave: -1,
                    trickleIntervalSeconds: 0,
                    trickleSize: [2, 1],
                    waveBudgetMultiplier: 0
                ),
                normal: DifficultyDef(
                    gracePeriodSeconds: 1,
                    interWaveGapBase: 1,
                    interWaveGapFloor: 1,
                    gapCompressionPerWave: 0,
                    trickleIntervalSeconds: 1,
                    trickleSize: [1, 1],
                    waveBudgetMultiplier: 1
                ),
                hard: DifficultyDef(
                    gracePeriodSeconds: 1,
                    interWaveGapBase: 1,
                    interWaveGapFloor: 1,
                    gapCompressionPerWave: 0,
                    trickleIntervalSeconds: 1,
                    trickleSize: [1, 1],
                    waveBudgetMultiplier: 1
                )
            )
        )

        let errors = ContentValidator().validate(bundle: bundle)
        XCTAssertTrue(errors.contains(.invalidHQ(reason: "hq health must be positive")))
        XCTAssertTrue(errors.contains(.invalidDifficulty(reason: "easy: gracePeriodSeconds must be positive")))
    }
}
