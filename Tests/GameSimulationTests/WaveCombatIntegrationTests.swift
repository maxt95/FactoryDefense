import XCTest
@testable import GameSimulation

final class WaveCombatIntegrationTests: XCTestCase {
    func testEnemiesPreferFunnelingThroughNearbyGap() {
        let board = BoardState(
            width: 15,
            height: 11,
            basePosition: GridPosition(x: 7, y: 5),
            spawnEdgeX: 14,
            spawnYMin: 0,
            spawnYMax: 10,
            blockedCells: [],
            restrictedCells: [],
            ramps: []
        )
        var entities = EntityStore()
        let wallPositions = [
            GridPosition(x: 6, y: 4),
            GridPosition(x: 7, y: 4),
            GridPosition(x: 8, y: 4),
            GridPosition(x: 6, y: 5),
            GridPosition(x: 6, y: 6),
            GridPosition(x: 7, y: 6),
            GridPosition(x: 8, y: 6)
        ]
        let wallIDs = wallPositions.map { entities.spawnStructure(.wall, at: $0) }
        let enemyID = entities.spawnEnemy(at: GridPosition(x: 10, y: 5), health: 20)

        let world = WorldState(
            tick: 0,
            board: board,
            entities: entities,
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(phase: .playing),
            combat: CombatState(
                enemies: [
                    enemyID: EnemyRuntime(
                        id: enemyID,
                        archetype: .droneScout,
                        moveEveryTicks: 1,
                        baseDamage: 2,
                        rewardCurrency: 1
                    )
                ],
                basePosition: GridPosition(x: 7, y: 5),
                spawnEdgeX: 14,
                spawnYMin: 0,
                spawnYMax: 10
            )
        )

        let engine = SimulationEngine(worldState: world, systems: [EnemyMovementSystem()])
        let events = engine.run(ticks: 6)

        XCTAssertTrue(events.contains(where: { $0.kind == .enemyReachedBase }))
        XCTAssertFalse(
            events.contains(where: {
                guard $0.kind == .structureDamaged, let entityID = $0.entity else { return false }
                return wallIDs.contains(entityID)
            })
        )
    }

    func testEnemiesBreakNearbyWallWhenGapDetourIsLong() {
        let board = BoardState(
            width: 15,
            height: 11,
            basePosition: GridPosition(x: 7, y: 5),
            spawnEdgeX: 14,
            spawnYMin: 0,
            spawnYMax: 10,
            blockedCells: [],
            restrictedCells: [],
            ramps: []
        )
        var entities = EntityStore()
        let wallPositions = [
            GridPosition(x: 6, y: 4),
            GridPosition(x: 7, y: 4),
            GridPosition(x: 8, y: 4),
            GridPosition(x: 6, y: 5),
            GridPosition(x: 6, y: 6),
            GridPosition(x: 7, y: 6),
            GridPosition(x: 8, y: 6)
        ]
        let wallIDs = wallPositions.map { entities.spawnStructure(.wall, at: $0) }
        let enemyID = entities.spawnEnemy(at: GridPosition(x: 0, y: 5), health: 20)

        let world = WorldState(
            tick: 0,
            board: board,
            entities: entities,
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(phase: .playing),
            combat: CombatState(
                enemies: [
                    enemyID: EnemyRuntime(
                        id: enemyID,
                        archetype: .droneScout,
                        moveEveryTicks: 1,
                        baseDamage: 2,
                        rewardCurrency: 1
                    )
                ],
                basePosition: GridPosition(x: 7, y: 5),
                spawnEdgeX: 14,
                spawnYMin: 0,
                spawnYMax: 10
            )
        )

        let engine = SimulationEngine(worldState: world, systems: [EnemyMovementSystem()])
        let events = engine.run(ticks: 8)

        XCTAssertTrue(
            events.contains(where: {
                guard $0.kind == .structureDamaged, let entityID = $0.entity else { return false }
                return wallIDs.contains(entityID)
            })
        )
        XCTAssertFalse(events.contains(where: { $0.kind == .enemyReachedBase }))
    }

    func testEnemiesAttackNearestStructureWhenBaseIsFullySealed() {
        let board = BoardState(
            width: 7,
            height: 7,
            basePosition: GridPosition(x: 3, y: 3),
            spawnEdgeX: 6,
            spawnYMin: 0,
            spawnYMax: 6,
            blockedCells: [],
            restrictedCells: [],
            ramps: []
        )
        var entities = EntityStore()
        let wallPositions = [
            GridPosition(x: 2, y: 2),
            GridPosition(x: 3, y: 2),
            GridPosition(x: 4, y: 2),
            GridPosition(x: 2, y: 3),
            GridPosition(x: 4, y: 3),
            GridPosition(x: 2, y: 4),
            GridPosition(x: 3, y: 4),
            GridPosition(x: 4, y: 4)
        ]
        let wallIDs = wallPositions.map { entities.spawnStructure(.wall, at: $0) }
        let enemyID = entities.spawnEnemy(at: GridPosition(x: 0, y: 3), health: 20)

        let world = WorldState(
            tick: 0,
            board: board,
            entities: entities,
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(phase: .playing),
            combat: CombatState(
                enemies: [
                    enemyID: EnemyRuntime(
                        id: enemyID,
                        archetype: .droneScout,
                        moveEveryTicks: 1,
                        baseDamage: 2,
                        rewardCurrency: 1
                    )
                ],
                basePosition: GridPosition(x: 3, y: 3),
                spawnEdgeX: 6,
                spawnYMin: 0,
                spawnYMax: 6
            )
        )

        let engine = SimulationEngine(worldState: world, systems: [EnemyMovementSystem()])
        let events = engine.run(ticks: 8)

        XCTAssertTrue(
            events.contains(where: {
                guard $0.kind == .structureDamaged, let entityID = $0.entity else { return false }
                return wallIDs.contains(entityID)
            })
        )
        XCTAssertFalse(events.contains(where: { $0.kind == .enemyReachedBase }))
    }

    func testEnemiesPreferBreachingWallsWhenBaseIsFullySealed() {
        let board = BoardState(
            width: 9,
            height: 9,
            basePosition: GridPosition(x: 4, y: 4),
            spawnEdgeX: 8,
            spawnYMin: 0,
            spawnYMax: 8,
            blockedCells: [],
            restrictedCells: [],
            ramps: []
        )
        var entities = EntityStore()
        let wallPositions = [
            GridPosition(x: 3, y: 3),
            GridPosition(x: 4, y: 3),
            GridPosition(x: 5, y: 3),
            GridPosition(x: 3, y: 4),
            GridPosition(x: 5, y: 4),
            GridPosition(x: 3, y: 5),
            GridPosition(x: 4, y: 5),
            GridPosition(x: 5, y: 5)
        ]
        let wallIDs = wallPositions.map { entities.spawnStructure(.wall, at: $0) }
        let decoyStructureID = entities.spawnStructure(.assembler, at: GridPosition(x: 1, y: 4))
        let enemyID = entities.spawnEnemy(at: GridPosition(x: 0, y: 4), health: 20)

        let world = WorldState(
            tick: 0,
            board: board,
            entities: entities,
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(phase: .playing),
            combat: CombatState(
                enemies: [
                    enemyID: EnemyRuntime(
                        id: enemyID,
                        archetype: .droneScout,
                        moveEveryTicks: 1,
                        baseDamage: 2,
                        rewardCurrency: 1
                    )
                ],
                basePosition: GridPosition(x: 4, y: 4),
                spawnEdgeX: 8,
                spawnYMin: 0,
                spawnYMax: 8
            )
        )

        let engine = SimulationEngine(worldState: world, systems: [EnemyMovementSystem()])
        let events = engine.run(ticks: 8)
        let damagedStructureIDs = Set(
            events.compactMap { event -> EntityID? in
                guard event.kind == .structureDamaged else { return nil }
                return event.entity
            }
        )

        XCTAssertTrue(damagedStructureIDs.contains(where: { wallIDs.contains($0) }))
        XCTAssertFalse(damagedStructureIDs.contains(decoyStructureID))
    }

    func testWaveSpawnsEnemiesAndTurretsFireProjectiles() {
        var world = WorldState.bootstrap()
        let turretID = world.entities.spawnStructure(.turretMount, at: GridPosition(x: 50, y: 32))
        world.economy.structureInputBuffers[turretID] = ["ammo_light": 400]
        world.rebuildAggregatedInventory()
        world.run.phase = .playing
        world.threat = ThreatState(
            waveIndex: 0,
            nextWaveTick: 0,
            waveIntervalTicks: 999,
            waveDurationTicks: 180,
            waveEndsAtTick: nil,
            isWaveActive: false,
            raidCooldownUntilTick: 999_999,
            milestoneEvery: 5,
            lastMilestoneWave: 0
        )

        let engine = SimulationEngine(
            worldState: world,
            systems: [
                WaveSystem(enableRaids: false),
                EnemyMovementSystem(),
                CombatSystem(turretRange: 200, projectileDamage: 30),
                ProjectileSystem()
            ]
        )

        let events = engine.run(ticks: 500)

        XCTAssertTrue(events.contains(where: { $0.kind == .enemySpawned }))
        XCTAssertTrue(events.contains(where: { $0.kind == .projectileFired }))
        XCTAssertTrue(events.contains(where: { $0.kind == .enemyDestroyed }))
        XCTAssertGreaterThan(engine.worldState.economy.currency, 0)
    }

    func testEnemyReachingBaseDamagesIntegrity() {
        let board = BoardState(
            width: 6,
            height: 6,
            basePosition: GridPosition(x: 0, y: 0),
            spawnEdgeX: 5,
            spawnYMin: 0,
            spawnYMax: 2,
            blockedCells: [],
            restrictedCells: [],
            ramps: []
        )
        var entities = EntityStore()
        let hqID = entities.spawnStructure(.hq, at: GridPosition(x: 1, y: 1), health: 8, maxHealth: 8)
        let enemyID = entities.spawnEnemy(at: GridPosition(x: 0, y: 0), health: 10)

        let world = WorldState(
            tick: 0,
            board: board,
            entities: entities,
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(phase: .playing, hqEntityID: hqID),
            combat: CombatState(
                enemies: [
                    enemyID: EnemyRuntime(
                        id: enemyID,
                        archetype: .droneScout,
                        moveEveryTicks: 1,
                        baseDamage: 2,
                        rewardCurrency: 1
                    )
                ],
                basePosition: GridPosition(x: 0, y: 0),
                spawnEdgeX: 3,
                spawnYMin: 0,
                spawnYMax: 2
            )
        )

        let engine = SimulationEngine(worldState: world, systems: [EnemyMovementSystem()])
        let events = engine.run(ticks: 2)

        XCTAssertTrue(events.contains(where: { $0.kind == .enemyReachedBase }))
        XCTAssertEqual(engine.worldState.hqHealth, 6)
        XCTAssertTrue(engine.worldState.combat.enemies.isEmpty)
    }

    func testHQZeroHealthEmitsGameOverAndHaltsSystems() {
        let board = BoardState(
            width: 6,
            height: 6,
            basePosition: GridPosition(x: 0, y: 0),
            spawnEdgeX: 5,
            spawnYMin: 0,
            spawnYMax: 2,
            blockedCells: [],
            restrictedCells: [],
            ramps: []
        )
        var entities = EntityStore()
        let hqID = entities.spawnStructure(.hq, at: GridPosition(x: 1, y: 1), health: 2, maxHealth: 2)
        let enemyID = entities.spawnEnemy(at: GridPosition(x: 0, y: 0), health: 10)

        let world = WorldState(
            tick: 0,
            board: board,
            entities: entities,
            economy: EconomyState(),
            threat: ThreatState(),
            run: RunState(phase: .playing, hqEntityID: hqID),
            combat: CombatState(
                enemies: [
                    enemyID: EnemyRuntime(
                        id: enemyID,
                        archetype: .droneScout,
                        moveEveryTicks: 1,
                        baseDamage: 2,
                        rewardCurrency: 1
                    )
                ],
                basePosition: GridPosition(x: 0, y: 0),
                spawnEdgeX: 3,
                spawnYMin: 0,
                spawnYMax: 2
            )
        )

        let engine = SimulationEngine(worldState: world, systems: [EnemyMovementSystem()])
        let firstStepEvents = engine.step()
        let secondStepEvents = engine.step()

        XCTAssertTrue(firstStepEvents.contains(where: { $0.kind == .gameOver }))
        XCTAssertEqual(engine.worldState.run.phase, .gameOver)
        XCTAssertTrue(secondStepEvents.isEmpty)
    }
}
