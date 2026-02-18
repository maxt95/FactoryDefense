import CryptoKit
import XCTest
@testable import GameSimulation

final class GoldenReplayTests: XCTestCase {
    func testGoldenReplayFingerprintV1() throws {
        let engine = SimulationEngine(
            worldState: .bootstrap(),
            systems: [
                CommandSystem(),
                EconomySystem(),
                WaveSystem(),
                EnemyMovementSystem(),
                CombatSystem(turretRange: 12, projectileDamage: 18),
                ProjectileSystem()
            ]
        )

        let player = PlayerID(1)
        let scriptedCommands = [
            PlayerCommand(tick: 1, actor: player, payload: .triggerWave),
            PlayerCommand(
                tick: 5,
                actor: player,
                payload: .placeStructure(BuildRequest(structure: .wall, position: GridPosition(x: 6, y: 1)))
            ),
            PlayerCommand(
                tick: 6,
                actor: player,
                payload: .placeStructure(BuildRequest(structure: .turretMount, position: GridPosition(x: 6, y: 1)))
            ),
            PlayerCommand(
                tick: 30,
                actor: player,
                payload: .placeStructure(BuildRequest(structure: .ammoModule, position: GridPosition(x: 3, y: 1)))
            ),
            PlayerCommand(
                tick: 50,
                actor: player,
                payload: .placeStructure(BuildRequest(structure: .wall, position: GridPosition(x: 2, y: 1)))
            ),
            PlayerCommand(
                tick: 51,
                actor: player,
                payload: .placeStructure(BuildRequest(structure: .wall, position: GridPosition(x: 2, y: 2)))
            ),
            PlayerCommand(
                tick: 52,
                actor: player,
                payload: .placeStructure(BuildRequest(structure: .wall, position: GridPosition(x: 2, y: 3)))
            )
        ]

        scriptedCommands.forEach(engine.enqueue)
        _ = engine.run(ticks: 1_200)

        let snapshot = engine.makeSnapshot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(snapshot)

        let digest = SHA256.hash(data: data)
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined()

        let expected = "1b252d876a760edaae1793227cfd7417a3359a0ab5f00857a22b57a056d1ee28"
        XCTAssertEqual(fingerprint, expected)
    }
}
