import Foundation
import GameContent

public struct CommandSystem: SimulationSystem {
    public init() {}

    public func update(state: inout WorldState, context: SystemContext) {
        let placementValidator = PlacementValidator()
        for command in context.commands {
            switch command.payload {
            case .placeStructure(let request):
                let result = placementValidator.canPlace(request.structure, at: request.position, in: state)
                if result == .ok {
                    let placementPosition = GridPosition(
                        x: request.position.x,
                        y: request.position.y,
                        z: state.board.elevation(at: request.position)
                    )
                    _ = state.entities.spawnStructure(request.structure, at: placementPosition)
                } else {
                    context.emit(
                        SimEvent(
                            tick: state.tick,
                            kind: .placementRejected,
                            value: result.rawValue
                        )
                    )
                }
            case .extract:
                state.run.extracted = true
                context.emit(SimEvent(tick: state.tick, kind: .extracted, value: state.economy.currency))
            case .triggerWave:
                state.threat.nextWaveTick = state.tick
            }
        }
    }
}

public struct EconomySystem: SimulationSystem {
    public init() {}

    public func update(state: inout WorldState, context: SystemContext) {
        let powerPlants = state.entities.structures(of: .powerPlant).count
        let miners = state.entities.structures(of: .miner).count
        let smelters = state.entities.structures(of: .smelter).count
        let ammoModules = state.entities.structures(of: .ammoModule).count
        let assemblers = state.entities.structures(of: .assembler).count
        let conveyors = state.entities.structures(of: .conveyor).count
        let storages = state.entities.structures(of: .storage).count

        state.economy.powerAvailable = powerPlants * 12
        state.economy.powerDemand = miners * 2 + smelters * 3 + ammoModules * 4 + assemblers * 3 + conveyors + storages

        let efficiency: Double
        if state.economy.powerDemand == 0 {
            efficiency = 1.0
        } else {
            efficiency = min(1.0, Double(state.economy.powerAvailable) / Double(state.economy.powerDemand))
        }

        let logisticsBoost = 1.0 + min(0.9, Double(conveyors) * 0.03 + Double(storages) * 0.04)
        let throughputMultiplier = efficiency * logisticsBoost

        let oreProduced = Int((Double(miners) * throughputMultiplier).rounded(.down))
        state.economy.add(itemID: "ore_iron", quantity: oreProduced)
        let copperProduced = Int((Double(miners) * 0.8 * throughputMultiplier).rounded(.down))
        state.economy.add(itemID: "ore_copper", quantity: copperProduced)
        let coalProduced = Int((Double(max(1, miners / 2)) * 0.6 * throughputMultiplier).rounded(.down))
        state.economy.add(itemID: "ore_coal", quantity: coalProduced)

        let ironSmeltRuns = min(
            max(1, Int((Double(smelters) * throughputMultiplier).rounded(.down))),
            state.economy.inventories["ore_iron", default: 0] / 2
        )
        if ironSmeltRuns > 0 {
            _ = state.economy.consume(itemID: "ore_iron", quantity: ironSmeltRuns * 2)
            state.economy.add(itemID: "plate_iron", quantity: ironSmeltRuns)
        }

        let copperSmeltRuns = min(
            max(1, Int((Double(max(1, smelters / 2)) * throughputMultiplier).rounded(.down))),
            state.economy.inventories["ore_copper", default: 0] / 2
        )
        if copperSmeltRuns > 0 {
            _ = state.economy.consume(itemID: "ore_copper", quantity: copperSmeltRuns * 2)
            state.economy.add(itemID: "plate_copper", quantity: copperSmeltRuns)
        }

        let steelRuns = min(
            max(1, Int((Double(max(1, smelters / 3)) * throughputMultiplier).rounded(.down))),
            min(
                state.economy.inventories["plate_iron", default: 0] / 2,
                state.economy.inventories["ore_coal", default: 0]
            )
        )
        if steelRuns > 0 {
            _ = state.economy.consume(itemID: "plate_iron", quantity: steelRuns * 2)
            _ = state.economy.consume(itemID: "ore_coal", quantity: steelRuns)
            state.economy.add(itemID: "plate_steel", quantity: steelRuns)
        }

        let assemblerRuns = min(
            max(1, Int((Double(assemblers) * throughputMultiplier).rounded(.down))),
            min(
                state.economy.inventories["plate_copper", default: 0] / 2,
                state.economy.inventories["ore_coal", default: 0]
            )
        )
        if assemblerRuns > 0 {
            _ = state.economy.consume(itemID: "plate_copper", quantity: assemblerRuns * 2)
            _ = state.economy.consume(itemID: "ore_coal", quantity: assemblerRuns)
            state.economy.add(itemID: "circuit", quantity: assemblerRuns)
        }

        let powerCellRuns = min(
            max(1, Int((Double(max(1, assemblers / 2)) * throughputMultiplier).rounded(.down))),
            min(
                state.economy.inventories["plate_copper", default: 0],
                state.economy.inventories["circuit", default: 0]
            )
        )
        if powerCellRuns > 0 {
            _ = state.economy.consume(itemID: "plate_copper", quantity: powerCellRuns)
            _ = state.economy.consume(itemID: "circuit", quantity: powerCellRuns)
            state.economy.add(itemID: "power_cell", quantity: powerCellRuns)
        }

        let ammoRuns = min(
            max(1, Int((Double(ammoModules) * throughputMultiplier).rounded(.down))),
            state.economy.inventories["plate_iron", default: 0]
        )
        if ammoRuns > 0 {
            _ = state.economy.consume(itemID: "plate_iron", quantity: ammoRuns)
            state.economy.add(itemID: "ammo_light", quantity: ammoRuns * 4)
        }

        let heavyAmmoRuns = min(
            max(1, Int((Double(max(1, ammoModules / 2)) * throughputMultiplier).rounded(.down))),
            min(
                state.economy.inventories["plate_steel", default: 0],
                state.economy.inventories["ammo_light", default: 0] / 2
            )
        )
        if heavyAmmoRuns > 0 {
            _ = state.economy.consume(itemID: "plate_steel", quantity: heavyAmmoRuns)
            _ = state.economy.consume(itemID: "ammo_light", quantity: heavyAmmoRuns * 2)
            state.economy.add(itemID: "ammo_heavy", quantity: heavyAmmoRuns * 3)
        }

        if state.threat.isWaveActive {
            state.economy.currency += 1
        }
    }
}

public struct WaveSystem: SimulationSystem {
    public var raidRollModulus: UInt64
    public var raidRollTrigger: UInt64
    public var raidCooldownTicks: UInt64
    public var enableRaids: Bool

    public init(
        raidRollModulus: UInt64 = 97,
        raidRollTrigger: UInt64 = 3,
        raidCooldownTicks: UInt64 = 220,
        enableRaids: Bool = true
    ) {
        self.raidRollModulus = raidRollModulus
        self.raidRollTrigger = raidRollTrigger
        self.raidCooldownTicks = raidCooldownTicks
        self.enableRaids = enableRaids
    }

    public func update(state: inout WorldState, context: SystemContext) {
        if !state.threat.isWaveActive && state.tick >= state.threat.nextWaveTick {
            state.threat.isWaveActive = true
            state.threat.waveIndex += 1
            state.threat.waveEndsAtTick = state.tick + state.threat.waveDurationTicks
            context.emit(SimEvent(tick: state.tick, kind: .waveStarted, value: state.threat.waveIndex))
            spawnWaveEnemies(state: &state, context: context)
        }

        if state.threat.isWaveActive,
           let endTick = state.threat.waveEndsAtTick,
           state.tick >= endTick {
            state.threat.isWaveActive = false
            state.threat.waveEndsAtTick = nil
            state.threat.nextWaveTick = state.tick + state.threat.waveIntervalTicks
            context.emit(SimEvent(tick: state.tick, kind: .waveEnded, value: state.threat.waveIndex))

            if state.threat.waveIndex % state.threat.milestoneEvery == 0,
               state.threat.waveIndex != state.threat.lastMilestoneWave {
                state.threat.lastMilestoneWave = state.threat.waveIndex
                let milestoneReward = state.threat.waveIndex * 10
                state.economy.currency += milestoneReward
                context.emit(SimEvent(tick: state.tick, kind: .milestoneReached, value: state.threat.waveIndex))
            }
        }

        guard enableRaids else { return }
        guard state.tick >= state.threat.raidCooldownUntilTick else { return }

        let roll = deterministicRaidRoll(tick: state.tick, wave: state.threat.waveIndex, modulus: raidRollModulus)
        if roll <= raidRollTrigger {
            state.threat.raidCooldownUntilTick = state.tick + raidCooldownTicks
            state.run.baseIntegrity = max(0, state.run.baseIntegrity - 2)
            context.emit(SimEvent(tick: state.tick, kind: .raidTriggered, value: Int(roll)))
            spawnRaidEnemies(state: &state, context: context)
            if state.run.baseIntegrity == 0 {
                state.run.gameOver = true
            }
        }
    }

    private func spawnWaveEnemies(state: inout WorldState, context: SystemContext) {
        let wave = state.threat.waveIndex
        let spawnCount = min(24, max(3, 2 + wave * 2))

        for offset in 0..<spawnCount {
            let isRaider = wave >= 4 && offset % 4 == 0
            let archetype: EnemyArchetype = isRaider ? .raider : .scout
            let health = isRaider ? (45 + wave * 5) : (20 + wave * 3)
            let moveEvery = isRaider ? max(4, 10 - wave / 3) : max(3, 8 - wave / 4)
            let damage = isRaider ? 3 : 1
            let reward = isRaider ? (4 + wave / 2) : (2 + wave / 3)

            spawnEnemy(
                state: &state,
                context: context,
                wave: wave,
                index: offset,
                archetype: archetype,
                health: health,
                moveEveryTicks: UInt64(moveEvery),
                baseDamage: damage,
                rewardCurrency: reward
            )
        }
    }

    private func spawnRaidEnemies(state: inout WorldState, context: SystemContext) {
        let wave = max(1, state.threat.waveIndex)
        let raidCount = min(8, max(1, 1 + wave / 3))

        for offset in 0..<raidCount {
            spawnEnemy(
                state: &state,
                context: context,
                wave: wave + 10,
                index: offset,
                archetype: .raider,
                health: 55 + wave * 5,
                moveEveryTicks: UInt64(max(3, 7 - wave / 4)),
                baseDamage: 3,
                rewardCurrency: 5 + wave / 2
            )
        }
    }

    private func spawnEnemy(
        state: inout WorldState,
        context: SystemContext,
        wave: Int,
        index: Int,
        archetype: EnemyArchetype,
        health: Int,
        moveEveryTicks: UInt64,
        baseDamage: Int,
        rewardCurrency: Int
    ) {
        let span = max(1, state.combat.spawnYMax - state.combat.spawnYMin + 1)
        let y = state.combat.spawnYMin + ((wave * 7 + index * 5) % span)
        let position = GridPosition(x: state.combat.spawnEdgeX, y: y)

        let enemyID = state.entities.spawnEnemy(at: position, health: health)
        state.combat.enemies[enemyID] = EnemyRuntime(
            id: enemyID,
            archetype: archetype,
            moveEveryTicks: max(1, moveEveryTicks),
            baseDamage: baseDamage,
            rewardCurrency: rewardCurrency
        )

        context.emit(SimEvent(tick: state.tick, kind: .enemySpawned, entity: enemyID, value: health))
    }

    private func deterministicRaidRoll(tick: UInt64, wave: Int, modulus: UInt64) -> UInt64 {
        let seed = tick &* 1_103_515_245 &+ UInt64(wave &* 12_345) &+ 0x9E3779B97F4A7C15
        return seed % max(1, modulus)
    }
}

public struct EnemyMovementSystem: SimulationSystem {
    public init() {}

    public func update(state: inout WorldState, context: SystemContext) {
        guard !state.combat.enemies.isEmpty else { return }

        let pathfinder = Pathfinder()
        let map = buildNavigationMap(state: state)
        let sortedEnemyIDs = state.combat.enemies.keys.sorted()

        for enemyID in sortedEnemyIDs {
            guard let runtime = state.combat.enemies[enemyID] else { continue }
            guard let enemy = state.entities.entity(id: enemyID) else {
                state.combat.enemies.removeValue(forKey: enemyID)
                continue
            }

            guard state.tick % max(1, runtime.moveEveryTicks) == 0 else { continue }

            if enemy.position == state.combat.basePosition {
                applyBaseHit(state: &state, context: context, enemyID: enemyID, damage: runtime.baseDamage)
                continue
            }

            guard let path = pathfinder.findPath(on: map, from: enemy.position, to: state.combat.basePosition),
                  path.count > 1 else {
                // If no valid path exists, treat this as a breach pressure tick.
                applyBaseHit(state: &state, context: context, enemyID: enemyID, damage: 1)
                continue
            }

            let next = path[1]
            state.entities.updatePosition(enemyID, to: next)
            context.emit(SimEvent(tick: state.tick, kind: .enemyMoved, entity: enemyID))

            if next == state.combat.basePosition {
                applyBaseHit(state: &state, context: context, enemyID: enemyID, damage: runtime.baseDamage)
            }
        }
    }

    private func buildNavigationMap(state: WorldState) -> GridMap {
        PlacementValidator().navigationMap(for: state)
    }

    private func applyBaseHit(state: inout WorldState, context: SystemContext, enemyID: EntityID, damage: Int) {
        state.run.baseIntegrity = max(0, state.run.baseIntegrity - max(1, damage))
        context.emit(SimEvent(tick: state.tick, kind: .enemyReachedBase, entity: enemyID, value: damage))
        state.entities.remove(enemyID)
        state.combat.enemies.removeValue(forKey: enemyID)

        if state.run.baseIntegrity == 0 {
            state.run.gameOver = true
        }
    }
}

public struct CombatSystem: SimulationSystem {
    public var ammoItemID: ItemID
    public var turretRange: Int
    public var projectileDamage: Int

    public init(ammoItemID: ItemID = "ammo_light", turretRange: Int = 8, projectileDamage: Int = 12) {
        self.ammoItemID = ammoItemID
        self.turretRange = turretRange
        self.projectileDamage = projectileDamage
    }

    public func update(state: inout WorldState, context: SystemContext) {
        guard !state.combat.enemies.isEmpty else { return }

        let turrets = state.entities.structures(of: .turretMount).sorted { $0.id < $1.id }
        guard !turrets.isEmpty else { return }

        var shotsFired = 0
        var dryFires = 0

        for turret in turrets {
            guard let target = nearestEnemy(to: turret.position, state: state) else { continue }

            if state.economy.consume(itemID: ammoItemID, quantity: 1) {
                let distance = turret.position.manhattanDistance(to: target.position)
                let travelTicks = UInt64(max(1, distance / 2 + 1))

                let projectileID = state.entities.spawnProjectile(at: turret.position)
                state.combat.projectiles[projectileID] = ProjectileRuntime(
                    id: projectileID,
                    sourceTurretID: turret.id,
                    targetEnemyID: target.id,
                    damage: projectileDamage,
                    impactTick: state.tick + travelTicks
                )

                shotsFired += 1
                context.emit(SimEvent(tick: state.tick, kind: .projectileFired, entity: projectileID, value: Int(travelTicks)))
            } else {
                dryFires += 1
            }
        }

        if shotsFired > 0 {
            context.emit(SimEvent(tick: state.tick, kind: .ammoSpent, value: shotsFired, itemID: ammoItemID))
        }

        if dryFires > 0 {
            context.emit(SimEvent(tick: state.tick, kind: .notEnoughAmmo, value: dryFires, itemID: ammoItemID))
        }
    }

    private func nearestEnemy(to position: GridPosition, state: WorldState) -> Entity? {
        let enemies = state.entities.enemies().filter { enemy in
            position.manhattanDistance(to: enemy.position) <= turretRange
        }

        guard !enemies.isEmpty else { return nil }

        return enemies.min { lhs, rhs in
            let lDist = position.manhattanDistance(to: lhs.position)
            let rDist = position.manhattanDistance(to: rhs.position)
            if lDist == rDist {
                return lhs.id < rhs.id
            }
            return lDist < rDist
        }
    }
}

public struct ProjectileSystem: SimulationSystem {
    public init() {}

    public func update(state: inout WorldState, context: SystemContext) {
        guard !state.combat.projectiles.isEmpty else { return }

        let projectileIDs = state.combat.projectiles.keys.sorted()

        for projectileID in projectileIDs {
            guard let projectile = state.combat.projectiles[projectileID] else { continue }
            guard state.tick >= projectile.impactTick else { continue }

            state.entities.remove(projectileID)
            state.combat.projectiles.removeValue(forKey: projectileID)

            guard state.entities.entity(id: projectile.targetEnemyID) != nil else {
                continue
            }

            state.entities.damage(projectile.targetEnemyID, amount: projectile.damage)

            if state.entities.entity(id: projectile.targetEnemyID) == nil {
                let reward = state.combat.enemies.removeValue(forKey: projectile.targetEnemyID)?.rewardCurrency ?? 0
                if reward > 0 {
                    state.economy.currency += reward
                }
                context.emit(SimEvent(tick: state.tick, kind: .enemyDestroyed, entity: projectile.targetEnemyID, value: reward))
            }
        }
    }
}
