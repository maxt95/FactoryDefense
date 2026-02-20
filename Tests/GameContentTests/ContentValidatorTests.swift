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

    func testInvalidOrePatchConfigIsDetected() {
        let bundle = GameContentBundle(
            items: [ItemDef(id: "ore_iron", name: "Iron Ore", kind: .raw)],
            recipes: [],
            turrets: [],
            enemies: [],
            waves: [],
            techNodes: [],
            board: .starter,
            orePatches: OrePatchesConfigDef(
                rings: [
                    OreRingDef(
                        index: 1,
                        minDistance: 10,
                        maxDistance: 5,
                        patchCount: OreRingPatchCountDef(easy: 1, normal: 1, hard: 1),
                        richnessWeights: OreRingRichnessWeightsDef(poor: 0.0, normal: 0.0, rich: 0.0)
                    )
                ],
                oreTypes: [
                    OreTypeDef(
                        oreType: "ore_missing",
                        rarityWeight: 0,
                        amounts: OreTypeAmountsDef(poor: 0, normal: 0, rich: 0)
                    )
                ],
                surveySecondsByRing: OreSurveySecondsByRingDef(
                    easy: [0],
                    normal: [0],
                    hard: [0]
                ),
                renewal: OreRenewalConfigDef(
                    minSpacing: 0,
                    minDistanceFromBase: 0,
                    maxActivePatches: 0,
                    batchCap: OreRenewalBatchCapDef(easy: 0, normal: 0, hard: 0),
                    hardSkipPercent: 120,
                    hardMaxConsecutiveSkips: -1,
                    edgeBiasPower: 0
                )
            )
        )

        let errors = ContentValidator().validate(bundle: bundle)
        XCTAssertTrue(errors.contains(.invalidOrePatches(reason: "ore rings must start at index 0")))
        XCTAssertTrue(errors.contains(.invalidOrePatches(reason: "ring 1: minDistance cannot exceed maxDistance")))
        XCTAssertTrue(errors.contains(.invalidOrePatches(reason: "easy: surveySecondsByRing must include ring indices 0...1")))
        XCTAssertTrue(errors.contains(.invalidOrePatches(reason: "renewal.minSpacing must be positive")))
        XCTAssertTrue(errors.contains(.invalidOrePatches(reason: "renewal.hardSkipPercent must be within 0...100")))
    }

    func testOrePatchValidatorCatchesRingOverlapAndSurveyValues() {
        let bundle = GameContentBundle(
            items: [
                ItemDef(id: "ore_iron", name: "Iron Ore", kind: .raw),
                ItemDef(id: "ore_copper", name: "Copper Ore", kind: .raw)
            ],
            recipes: [],
            turrets: [],
            enemies: [],
            waves: [],
            techNodes: [],
            board: .starter,
            orePatches: OrePatchesConfigDef(
                rings: [
                    OreRingDef(
                        index: 0,
                        minDistance: 0,
                        maxDistance: 6,
                        patchCount: OreRingPatchCountDef(easy: 1, normal: 1, hard: 1),
                        richnessWeights: OreRingRichnessWeightsDef(poor: 0.5, normal: 0.4, rich: 0.1)
                    ),
                    OreRingDef(
                        index: 1,
                        minDistance: 6,
                        maxDistance: 10,
                        patchCount: OreRingPatchCountDef(easy: 1, normal: 1, hard: 1),
                        richnessWeights: OreRingRichnessWeightsDef(poor: 0.0, normal: 0.0, rich: 0.0)
                    )
                ],
                oreTypes: [
                    OreTypeDef(
                        oreType: "ore_iron",
                        rarityWeight: 1,
                        amounts: OreTypeAmountsDef(poor: 100, normal: 150, rich: 200)
                    ),
                    OreTypeDef(
                        oreType: "ore_copper",
                        rarityWeight: 1,
                        amounts: OreTypeAmountsDef(poor: 100, normal: 150, rich: 200)
                    )
                ],
                surveySecondsByRing: OreSurveySecondsByRingDef(
                    easy: [0, -1],
                    normal: [0],
                    hard: [0, 1]
                ),
                renewal: OreRenewalConfigDef(
                    minSpacing: 3,
                    minDistanceFromBase: 0,
                    maxActivePatches: 10,
                    batchCap: OreRenewalBatchCapDef(easy: 1, normal: 1, hard: 1),
                    hardSkipPercent: 10,
                    hardMaxConsecutiveSkips: 1,
                    edgeBiasPower: 1.0
                )
            )
        )

        let errors = ContentValidator().validate(bundle: bundle)
        XCTAssertTrue(errors.contains(.invalidOrePatches(reason: "ring 1: distance range overlaps ring 0")))
        XCTAssertTrue(errors.contains(.invalidOrePatches(reason: "ring 1: richness weights must sum to > 0")))
        XCTAssertTrue(errors.contains(.invalidOrePatches(reason: "easy: surveySecondsByRing[1] cannot be negative")))
        XCTAssertTrue(errors.contains(.invalidOrePatches(reason: "normal: surveySecondsByRing must include ring indices 0...1")))
    }
}
