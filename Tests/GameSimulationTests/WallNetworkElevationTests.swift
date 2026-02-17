import XCTest
@testable import GameSimulation

final class WallNetworkElevationTests: XCTestCase {
    func testWallNetworksConnectCardinalNeighborsAcrossElevation() {
        var entities = EntityStore()
        let wallA = entities.spawnStructure(.wall, at: GridPosition(x: 1, y: 1, z: 0))
        _ = entities.spawnStructure(.wall, at: GridPosition(x: 2, y: 1, z: 1))
        let wallC = entities.spawnStructure(.wall, at: GridPosition(x: 3, y: 1, z: 0))

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState()
        )

        let engine = SimulationEngine(
            worldState: world,
            systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])]
        )
        _ = engine.step()

        XCTAssertEqual(engine.worldState.combat.wallNetworks.count, 1)
        XCTAssertEqual(engine.worldState.combat.wallNetworkByWallEntityID[wallA], engine.worldState.combat.wallNetworkByWallEntityID[wallC])
    }

    func testMountedTurretsShareAmmoAcrossElevationConnectedWallNetwork() {
        var entities = EntityStore()
        let wallA = entities.spawnStructure(.wall, at: GridPosition(x: 1, y: 1, z: 0))
        _ = entities.spawnStructure(.wall, at: GridPosition(x: 2, y: 1, z: 1))
        let wallC = entities.spawnStructure(.wall, at: GridPosition(x: 3, y: 1, z: 0))

        let turretA = entities.spawnStructure(
            .turretMount,
            at: GridPosition(x: 1, y: 1, z: 0),
            hostWallID: wallA
        )
        let turretC = entities.spawnStructure(
            .turretMount,
            at: GridPosition(x: 3, y: 1, z: 0),
            hostWallID: wallC
        )

        let enemyA = entities.spawnEnemy(at: GridPosition(x: 1, y: 3, z: 0), health: 500)
        let enemyC = entities.spawnEnemy(at: GridPosition(x: 3, y: 3, z: 0), health: 500)

        let world = WorldState(
            tick: 0,
            entities: entities,
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(),
            combat: CombatState(
                enemies: [
                    enemyA: EnemyRuntime(
                        id: enemyA,
                        archetype: .droneScout,
                        moveEveryTicks: 10,
                        baseDamage: 1,
                        rewardCurrency: 1
                    ),
                    enemyC: EnemyRuntime(
                        id: enemyC,
                        archetype: .droneScout,
                        moveEveryTicks: 10,
                        baseDamage: 1,
                        rewardCurrency: 1
                    )
                ],
                basePosition: GridPosition(x: 0, y: 0),
                spawnEdgeX: 8,
                spawnYMin: 0,
                spawnYMax: 8
            )
        )

        let economyEngine = SimulationEngine(
            worldState: world,
            systems: [EconomySystem(minimumConstructionStock: [:], reserveProtectedRecipeIDs: [])]
        )
        _ = economyEngine.step()

        guard let networkID = economyEngine.worldState.combat.wallNetworkByWallEntityID[wallA] else {
            XCTFail("Missing network for wallA")
            return
        }
        XCTAssertEqual(networkID, economyEngine.worldState.combat.wallNetworkByWallEntityID[wallC])

        guard var network = economyEngine.worldState.combat.wallNetworks[networkID] else {
            XCTFail("Missing rebuilt network state")
            return
        }
        network.ammoPoolByItemID["ammo_light"] = 2
        economyEngine.worldState.combat.wallNetworks[networkID] = network

        let combatEngine = SimulationEngine(
            worldState: economyEngine.worldState,
            systems: [CombatSystem()]
        )
        let events = combatEngine.step()

        let ammoSpent = events
            .filter { $0.kind == .ammoSpent }
            .reduce(0) { $0 + ($1.value ?? 0) }
        XCTAssertEqual(ammoSpent, 2)
        XCTAssertFalse(events.contains(where: { $0.kind == .notEnoughAmmo }))

        let firingTurretIDs = Set(combatEngine.worldState.combat.projectiles.values.map(\.sourceTurretID))
        XCTAssertEqual(firingTurretIDs, Set([turretA, turretC]))
        XCTAssertEqual(combatEngine.worldState.combat.wallNetworks[networkID]?.ammoPoolByItemID["ammo_light"] ?? 0, 0)
    }
}
