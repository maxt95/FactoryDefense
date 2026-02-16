import Foundation
import GameContent

private enum CanonicalBootstrapContent {
    static let bundle: GameContentBundle? = {
        let contentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Content/bootstrap")
        return try? ContentLoader().loadBundle(from: contentDirectory)
    }()
}

public struct CommandSystem: SimulationSystem {
    public init() {}

    public func update(state: inout WorldState, context: SystemContext) {
        let placementValidator = PlacementValidator()
        for command in context.commands {
            switch command.payload {
            case .placeStructure(let request):
                let coveredCells = request.structure.coveredCells(anchor: request.position)
                guard let expansionInsets = state.board.plannedExpansion(for: coveredCells) else {
                    context.emit(
                        SimEvent(
                            tick: state.tick,
                            kind: .placementRejected,
                            value: PlacementResult.outOfBounds.rawValue
                        )
                    )
                    continue
                }

                let placementAnchor = request.position.translated(byX: expansionInsets.left, byY: expansionInsets.top)
                var previewState = state
                previewState.applyBoardExpansion(expansionInsets)
                let result = placementValidator.canPlace(request.structure, at: placementAnchor, in: previewState)
                guard result == .ok else {
                    context.emit(
                        SimEvent(
                            tick: state.tick,
                            kind: .placementRejected,
                            value: result.rawValue
                        )
                    )
                    continue
                }

                guard state.economy.consume(costs: request.structure.buildCosts) else {
                    context.emit(
                        SimEvent(
                            tick: state.tick,
                            kind: .placementRejected,
                            value: PlacementResult.insufficientResources.rawValue
                        )
                    )
                    continue
                }

                state.applyBoardExpansion(expansionInsets)
                let placementPosition = GridPosition(
                    x: placementAnchor.x,
                    y: placementAnchor.y,
                    z: state.board.elevation(at: placementAnchor)
                )
                _ = state.entities.spawnStructure(request.structure, at: placementPosition)
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
    private let recipesByID: [String: RecipeDef]
    private let minimumConstructionStock: [ItemID: Int]
    private let reserveProtectedRecipeIDs: Set<String>

    public init(
        recipes: [RecipeDef] = EconomySystem.defaultRecipes,
        minimumConstructionStock: [ItemID: Int] = EconomySystem.defaultMinimumConstructionStock,
        reserveProtectedRecipeIDs: Set<String> = EconomySystem.defaultReserveProtectedRecipeIDs
    ) {
        self.recipesByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        self.minimumConstructionStock = minimumConstructionStock
        self.reserveProtectedRecipeIDs = reserveProtectedRecipeIDs
    }

    public func update(state: inout WorldState, context: SystemContext) {
        let structures = state.entities.all.filter { $0.category == .structure }
        var powerAvailable = 0
        var powerDemand = 0
        for entity in structures {
            guard let structureType = entity.structureType else { continue }
            let structurePower = structureType.powerDemand
            if structurePower < 0 {
                powerAvailable += abs(structurePower)
            } else {
                powerDemand += structurePower
            }
        }
        state.economy.powerAvailable = powerAvailable
        state.economy.powerDemand = powerDemand

        let efficiency = powerDemand == 0 ? 1.0 : min(1.0, Double(powerAvailable) / Double(powerDemand))
        let tickDuration = context.tickDurationSeconds

        produceRawResources(state: &state, tickDuration: tickDuration, efficiency: efficiency)

        runProduction(
            structures: state.entities.structures(of: .smelter),
            prioritizedRecipeIDs: ["smelt_steel", "smelt_iron", "smelt_copper"],
            state: &state,
            tickDuration: tickDuration,
            efficiency: efficiency
        )
        runProduction(
            structures: state.entities.structures(of: .assembler),
            prioritizedRecipeIDs: [
                "craft_turret_core",
                "craft_wall_kit",
                "craft_repair_kit",
                "assemble_power_cell",
                "etch_circuit",
                "forge_gear"
            ],
            state: &state,
            tickDuration: tickDuration,
            efficiency: efficiency
        )
        runProduction(
            structures: state.entities.structures(of: .ammoModule),
            prioritizedRecipeIDs: ["craft_ammo_plasma", "craft_ammo_heavy", "craft_ammo_light"],
            state: &state,
            tickDuration: tickDuration,
            efficiency: efficiency
        )

        pruneProductionState(for: Set(structures.map(\.id)), state: &state)

        if state.threat.isWaveActive {
            state.economy.currency += 1
        }
    }

    private func produceRawResources(state: inout WorldState, tickDuration: Double, efficiency: Double) {
        let minerCount = Double(state.entities.structures(of: .miner).count)
        guard minerCount > 0 else { return }
        let effectiveMinerRate = minerCount * efficiency * tickDuration
        state.economy.addFractional(itemID: "ore_iron", quantity: effectiveMinerRate * 1.0)
        state.economy.addFractional(itemID: "ore_copper", quantity: effectiveMinerRate * 0.8)
        state.economy.addFractional(itemID: "ore_coal", quantity: effectiveMinerRate * 0.6)
    }

    private func runProduction(
        structures: [Entity],
        prioritizedRecipeIDs: [String],
        state: inout WorldState,
        tickDuration: Double,
        efficiency: Double
    ) {
        for structure in structures.sorted(by: { $0.id < $1.id }) {
            let structureID = structure.id
            guard let selectedRecipe = selectRecipe(prioritizedRecipeIDs: prioritizedRecipeIDs, inventory: state.economy.inventories) else {
                state.economy.activeRecipeByStructure.removeValue(forKey: structureID)
                state.economy.productionProgressByStructure[structureID] = 0
                continue
            }

            if state.economy.activeRecipeByStructure[structureID] != selectedRecipe.id {
                state.economy.activeRecipeByStructure[structureID] = selectedRecipe.id
                state.economy.productionProgressByStructure[structureID] = 0
            }

            let progressGain = tickDuration * efficiency
            state.economy.productionProgressByStructure[structureID, default: 0] += progressGain

            var progress = state.economy.productionProgressByStructure[structureID, default: 0]
            let recipeSeconds = Double(selectedRecipe.seconds)
            guard recipeSeconds > 0 else { continue }

            while progress + 0.000_001 >= recipeSeconds, state.economy.canAfford(selectedRecipe.inputs) {
                _ = state.economy.consume(costs: selectedRecipe.inputs)
                for output in selectedRecipe.outputs {
                    state.economy.add(itemID: output.itemID, quantity: output.quantity)
                }
                progress -= recipeSeconds
            }

            state.economy.productionProgressByStructure[structureID] = max(0, progress)
        }
    }

    private func selectRecipe(prioritizedRecipeIDs: [String], inventory: [ItemID: Int]) -> RecipeDef? {
        for recipeID in prioritizedRecipeIDs {
            guard let recipe = recipesByID[recipeID] else { continue }
            guard recipe.inputs.allSatisfy({ inventory[$0.itemID, default: 0] >= $0.quantity }) else { continue }
            guard canRunRecipeWithoutBreachingConstructionStock(recipe: recipe, inventory: inventory) else { continue }
            return recipe
        }
        return nil
    }

    private func canRunRecipeWithoutBreachingConstructionStock(recipe: RecipeDef, inventory: [ItemID: Int]) -> Bool {
        guard reserveProtectedRecipeIDs.contains(recipe.id) else { return true }
        let outputItemIDs = Set(recipe.outputs.map(\.itemID))

        for input in recipe.inputs {
            let minimum = minimumConstructionStock[input.itemID, default: 0]
            guard minimum > 0 else { continue }
            // If the recipe regenerates the same item, let it run.
            guard !outputItemIDs.contains(input.itemID) else { continue }

            let remaining = inventory[input.itemID, default: 0] - input.quantity
            if remaining < minimum {
                return false
            }
        }

        return true
    }

    private func pruneProductionState(for validStructureIDs: Set<EntityID>, state: inout WorldState) {
        state.economy.activeRecipeByStructure = state.economy.activeRecipeByStructure.filter { validStructureIDs.contains($0.key) }
        state.economy.productionProgressByStructure = state.economy.productionProgressByStructure.filter { validStructureIDs.contains($0.key) }
    }

    public static var defaultRecipes: [RecipeDef] {
        if let loaded = CanonicalBootstrapContent.bundle?.recipes, !loaded.isEmpty {
            return loaded
        }

        return [
            RecipeDef(id: "smelt_iron", inputs: [ItemStack(itemID: "ore_iron", quantity: 2)], outputs: [ItemStack(itemID: "plate_iron", quantity: 1)], seconds: 2.0),
            RecipeDef(id: "smelt_copper", inputs: [ItemStack(itemID: "ore_copper", quantity: 2)], outputs: [ItemStack(itemID: "plate_copper", quantity: 1)], seconds: 2.0),
            RecipeDef(
                id: "smelt_steel",
                inputs: [ItemStack(itemID: "plate_iron", quantity: 2), ItemStack(itemID: "ore_coal", quantity: 1)],
                outputs: [ItemStack(itemID: "plate_steel", quantity: 1)],
                seconds: 4.0
            ),
            RecipeDef(id: "forge_gear", inputs: [ItemStack(itemID: "plate_iron", quantity: 2)], outputs: [ItemStack(itemID: "gear", quantity: 1)], seconds: 1.5),
            RecipeDef(
                id: "etch_circuit",
                inputs: [ItemStack(itemID: "plate_copper", quantity: 2), ItemStack(itemID: "ore_coal", quantity: 1)],
                outputs: [ItemStack(itemID: "circuit", quantity: 1)],
                seconds: 2.0
            ),
            RecipeDef(
                id: "assemble_power_cell",
                inputs: [ItemStack(itemID: "plate_copper", quantity: 1), ItemStack(itemID: "circuit", quantity: 1)],
                outputs: [ItemStack(itemID: "power_cell", quantity: 1)],
                seconds: 2.5
            ),
            RecipeDef(
                id: "craft_wall_kit",
                inputs: [ItemStack(itemID: "plate_steel", quantity: 1), ItemStack(itemID: "gear", quantity: 1)],
                outputs: [ItemStack(itemID: "wall_kit", quantity: 1)],
                seconds: 1.2
            ),
            RecipeDef(
                id: "craft_turret_core",
                inputs: [ItemStack(itemID: "plate_steel", quantity: 1), ItemStack(itemID: "circuit", quantity: 1), ItemStack(itemID: "gear", quantity: 1)],
                outputs: [ItemStack(itemID: "turret_core", quantity: 1)],
                seconds: 2.5
            ),
            RecipeDef(id: "craft_ammo_light", inputs: [ItemStack(itemID: "plate_iron", quantity: 1)], outputs: [ItemStack(itemID: "ammo_light", quantity: 4)], seconds: 2.0),
            RecipeDef(
                id: "craft_ammo_heavy",
                inputs: [ItemStack(itemID: "plate_steel", quantity: 1), ItemStack(itemID: "ammo_light", quantity: 2)],
                outputs: [ItemStack(itemID: "ammo_heavy", quantity: 3)],
                seconds: 2.6
            ),
            RecipeDef(
                id: "craft_ammo_plasma",
                inputs: [ItemStack(itemID: "power_cell", quantity: 1), ItemStack(itemID: "circuit", quantity: 1)],
                outputs: [ItemStack(itemID: "ammo_plasma", quantity: 2)],
                seconds: 3.0
            ),
            RecipeDef(
                id: "craft_repair_kit",
                inputs: [ItemStack(itemID: "plate_steel", quantity: 1), ItemStack(itemID: "circuit", quantity: 1)],
                outputs: [ItemStack(itemID: "repair_kit", quantity: 1)],
                seconds: 2.0
            )
        ]
    }

    public static let defaultMinimumConstructionStock: [ItemID: Int] = [
        "plate_iron": 6,
        "plate_copper": 4,
        "plate_steel": 4,
        "gear": 3,
        "circuit": 2
    ]

    public static let defaultReserveProtectedRecipeIDs: Set<String> = [
        "smelt_steel",
        "forge_gear",
        "etch_circuit",
        "assemble_power_cell",
        "craft_wall_kit",
        "craft_turret_core",
        "craft_repair_kit",
        "craft_ammo_light",
        "craft_ammo_heavy",
        "craft_ammo_plasma"
    ]
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
    private let turretDefsByID: [String: TurretDef]
    private let defaultTurretDefID: String
    private let overrideRange: Int?
    private let overrideDamage: Int?

    public init(
        turretDefinitions: [TurretDef] = CombatSystem.defaultTurretDefinitions,
        defaultTurretDefID: String = "turret_mk1",
        turretRange: Int? = nil,
        projectileDamage: Int? = nil
    ) {
        self.turretDefsByID = Dictionary(uniqueKeysWithValues: turretDefinitions.map { ($0.id, $0) })
        self.defaultTurretDefID = defaultTurretDefID
        self.overrideRange = turretRange
        self.overrideDamage = projectileDamage
    }

    public func update(state: inout WorldState, context: SystemContext) {
        guard !state.combat.enemies.isEmpty else { return }

        let turrets = state.entities.structures(of: .turretMount).sorted { $0.id < $1.id }
        guard !turrets.isEmpty else { return }

        var spentByItem: [ItemID: Int] = [:]
        var dryFiresByItem: [ItemID: Int] = [:]

        for turret in turrets {
            guard let turretDef = resolveTurretDef(for: turret) else { continue }
            guard let ammoItemID = ammoItemID(for: turretDef.ammoType) else { continue }

            let ticksPerShot = ticksBetweenShots(fireRate: turretDef.fireRate, tickDuration: context.tickDurationSeconds)
            if let lastTick = state.combat.lastFireTickByTurret[turret.id], state.tick < lastTick + ticksPerShot {
                continue
            }

            let range = overrideRange.map(Double.init) ?? Double(turretDef.range)
            guard let target = nearestEnemy(to: turret.position, state: state, range: range) else { continue }

            state.combat.lastFireTickByTurret[turret.id] = state.tick

            if state.economy.consume(itemID: ammoItemID, quantity: 1) {
                let distance = turret.position.manhattanDistance(to: target.position)
                let travelTicks = UInt64(max(1, distance / 2 + 1))
                let damage = overrideDamage ?? turretDef.damage

                let projectileID = state.entities.spawnProjectile(at: turret.position)
                state.combat.projectiles[projectileID] = ProjectileRuntime(
                    id: projectileID,
                    sourceTurretID: turret.id,
                    targetEnemyID: target.id,
                    damage: damage,
                    impactTick: state.tick + travelTicks
                )

                spentByItem[ammoItemID, default: 0] += 1
                context.emit(SimEvent(tick: state.tick, kind: .projectileFired, entity: projectileID, value: Int(travelTicks)))
            } else {
                dryFiresByItem[ammoItemID, default: 0] += 1
            }
        }

        for itemID in spentByItem.keys.sorted() {
            let spent = spentByItem[itemID, default: 0]
            guard spent > 0 else { continue }
            context.emit(SimEvent(tick: state.tick, kind: .ammoSpent, value: spent, itemID: itemID))
        }

        for itemID in dryFiresByItem.keys.sorted() {
            let dryFires = dryFiresByItem[itemID, default: 0]
            guard dryFires > 0 else { continue }
            context.emit(SimEvent(tick: state.tick, kind: .notEnoughAmmo, value: dryFires, itemID: itemID))
        }
    }

    private func resolveTurretDef(for turret: Entity) -> TurretDef? {
        if let turretDefID = turret.turretDefID, let turretDef = turretDefsByID[turretDefID] {
            return turretDef
        }
        return turretDefsByID[defaultTurretDefID]
    }

    private func ticksBetweenShots(fireRate: Float, tickDuration: Double) -> UInt64 {
        guard fireRate > 0 else { return 1 }
        let secondsBetweenShots = 1.0 / Double(fireRate)
        let ticks = Int((secondsBetweenShots / tickDuration).rounded())
        return UInt64(max(1, ticks))
    }

    private func ammoItemID(for ammoType: AmmoType) -> ItemID? {
        switch ammoType {
        case .lightBallistic:
            return "ammo_light"
        case .heavyBallistic:
            return "ammo_heavy"
        case .plasma:
            return "ammo_plasma"
        }
    }

    private func nearestEnemy(to position: GridPosition, state: WorldState, range: Double) -> Entity? {
        let enemies = state.entities.enemies().filter { enemy in
            Double(position.manhattanDistance(to: enemy.position)) <= range
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

    public static var defaultTurretDefinitions: [TurretDef] {
        if let loaded = CanonicalBootstrapContent.bundle?.turrets, !loaded.isEmpty {
            return loaded
        }

        return [
            TurretDef(id: "turret_mk1", ammoType: .lightBallistic, fireRate: 2.0, range: 8.0, damage: 12),
            TurretDef(id: "turret_mk2", ammoType: .heavyBallistic, fireRate: 1.4, range: 10.0, damage: 25),
            TurretDef(id: "gattling_tower", ammoType: .lightBallistic, fireRate: 4.2, range: 6.5, damage: 8),
            TurretDef(id: "plasma_sentinel", ammoType: .plasma, fireRate: 0.9, range: 11.0, damage: 45)
        ]
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
