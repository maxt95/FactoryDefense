import XCTest
@testable import GamePlatform
@testable import GameSimulation

final class SnapshotStoreTests: XCTestCase {
    func testSaveAndLoadSnapshotRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = FileSnapshotStore(directory: tempDir)

        let engine = SimulationEngine(worldState: .bootstrap())
        _ = engine.run(ticks: 50)
        let snapshot = engine.makeSnapshot()

        _ = try store.save(snapshot: snapshot, name: "round_trip")
        let loaded = try store.load(name: "round_trip")

        XCTAssertEqual(snapshot, loaded)
    }

    func testLoadRejectsLegacySnapshotWithoutSchemaVersion() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = FileSnapshotStore(directory: tempDir)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let legacyURL = tempDir.appendingPathComponent("legacy.json")
        let legacyPayload = """
        {
          "world": {
            "tick": 0,
            "board": {
              "width": 1,
              "height": 1,
              "terrain": [],
              "restrictedCells": [],
              "blockedCells": [],
              "basePosition": { "x": 0, "y": 0, "z": 0 },
              "spawnEdgeX": 0,
              "spawnYMin": 0,
              "spawnYMax": 0,
              "maxWidth": 128,
              "maxHeight": 128
            },
            "entities": { "entitiesByID": {}, "nextEntityID": 1 },
            "orePatches": [],
            "economy": {
              "inventories": {},
              "activeRecipeByStructure": {},
              "pinnedRecipeByStructure": {},
              "productionProgressByStructure": {},
              "fractionalProductionRemainders": {},
              "structureInputBuffers": {},
              "structureOutputBuffers": {},
              "conveyorPayloadByEntity": {},
              "powerAvailable": 0,
              "powerDemand": 0,
              "currency": 0,
              "telemetry": { "produced": {}, "consumed": {} }
            },
            "threat": {
              "waveIndex": 0,
              "nextWaveTick": 0,
              "waveIntervalTicks": 1,
              "waveDurationTicks": 1,
              "waveEndsAtTick": null,
              "isWaveActive": false,
              "waveGapBaseTicks": 1,
              "waveGapFloorTicks": 1,
              "waveGapCompressionTicks": 0,
              "gracePeriodTicks": 1,
              "graceEndsAtTick": 1,
              "trickleIntervalTicks": 1,
              "trickleMinCount": 1,
              "trickleMaxCount": 1,
              "nextTrickleTick": 0,
              "milestoneEvery": 5,
              "lastMilestoneWave": 0,
              "pendingSpawns": [],
              "deterministicRandomState": 1,
              "telemetry": {
                "spawnedEnemiesByWave": {},
                "queuedSpawnBacklog": 0,
                "structureDamageEvents": 0,
                "dryFireEvents": 0
              }
            },
            "run": {
              "phase": "gracePeriod",
              "difficulty": "normal",
              "seed": 0,
              "hqEntityID": null,
              "runStartedEmitted": false,
              "gracePeriodEndedEmitted": false,
              "gameOverEmitted": false
            },
            "combat": {
              "enemies": {},
              "projectiles": {},
              "lastFireTickByTurret": {},
              "basePosition": { "x": 0, "y": 0, "z": 0 },
              "spawnEdgeX": 0,
              "spawnYMin": 0,
              "spawnYMax": 0,
              "wallNetworkByWallEntityID": {},
              "wallNetworks": {},
              "wallNetworksDirty": false
            }
          },
          "queuedCommands": {}
        }
        """
        try legacyPayload.data(using: .utf8)?.write(to: legacyURL, options: [.atomic])

        XCTAssertThrowsError(try store.load(name: "legacy")) { error in
            guard case DecodingError.keyNotFound(let key, _) = error, key.stringValue == "schemaVersion" else {
                XCTFail("Expected missing schemaVersion decode error, got \(error)")
                return
            }
        }
    }
}
