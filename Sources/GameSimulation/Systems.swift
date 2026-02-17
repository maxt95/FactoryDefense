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
                            value: PlacementResult.outOfBounds.rawValue,
                            placementReason: .outOfBounds
                        )
                    )
                    continue
                }

                let placementAnchor = request.position.translated(byX: expansionInsets.left, byY: expansionInsets.top)
                var previewState = state
                previewState.applyBoardExpansion(expansionInsets)
                let result = placementValidator.canPlace(
                    request.structure,
                    at: placementAnchor,
                    targetPatchID: request.targetPatchID,
                    in: previewState
                )
                guard result == .ok else {
                    context.emit(
                        SimEvent(
                            tick: state.tick,
                            kind: .placementRejected,
                            value: result.rawValue,
                            placementReason: result
                        )
                    )
                    continue
                }

                let targetPatchID: Int?
                if request.structure == .miner {
                    targetPatchID = placementValidator.resolvedMinerPatchID(
                        forMinerAt: placementAnchor,
                        targetPatchID: request.targetPatchID,
                        in: previewState
                    )
                    guard targetPatchID != nil else {
                        context.emit(
                            SimEvent(
                                tick: state.tick,
                                kind: .placementRejected,
                                value: PlacementResult.invalidMinerPlacement.rawValue,
                                placementReason: .invalidMinerPlacement
                            )
                        )
                        continue
                    }
                } else {
                    targetPatchID = nil
                }

                let hostWallID: EntityID?
                if request.structure == .turretMount {
                    hostWallID = placementValidator.resolvedTurretHostWallID(forTurretAt: placementAnchor, in: previewState.entities)
                    guard hostWallID != nil else {
                        context.emit(
                            SimEvent(
                                tick: state.tick,
                                kind: .placementRejected,
                                value: PlacementResult.invalidTurretMountPlacement.rawValue,
                                placementReason: .invalidTurretMountPlacement
                            )
                        )
                        continue
                    }
                } else {
                    hostWallID = nil
                }

                guard consumeConstructionCosts(request.structure.buildCosts, state: &state) else {
                    context.emit(
                        SimEvent(
                            tick: state.tick,
                            kind: .placementRejected,
                            value: PlacementResult.insufficientResources.rawValue,
                            placementReason: .insufficientResources
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
                let structureID = state.entities.spawnStructure(
                    request.structure,
                    at: placementPosition,
                    rotation: request.rotation,
                    hostWallID: hostWallID,
                    boundPatchID: targetPatchID
                )
                if let targetPatchID {
                    bindMiner(structureID, toPatchID: targetPatchID, state: &state)
                }
                if request.structure == .wall {
                    state.combat.wallNetworksDirty = true
                }
                context.emit(
                    SimEvent(
                        tick: state.tick,
                        kind: .structurePlaced,
                        entity: structureID
                    )
                )
            case .removeStructure(let entityID):
                guard let structure = state.entities.entity(id: entityID),
                      structure.category == .structure,
                      let structureType = structure.structureType else {
                    context.emit(
                        SimEvent(
                            tick: state.tick,
                            kind: .placementRejected,
                            value: PlacementResult.invalidRemoval.rawValue,
                            placementReason: .invalidRemoval,
                            reasonDetail: "missing-structure"
                        )
                    )
                    continue
                }
                guard structureType != .hq else {
                    context.emit(
                        SimEvent(
                            tick: state.tick,
                            kind: .placementRejected,
                            value: PlacementResult.invalidRemoval.rawValue,
                            placementReason: .invalidRemoval,
                            reasonDetail: "hq-removal-forbidden"
                        )
                    )
                    continue
                }

                var removalIDs: [EntityID] = [entityID]
                if structureType == .wall {
                    let mountedTurretIDs = state.entities.all
                        .filter { $0.category == .structure && $0.structureType == .turretMount && $0.hostWallID == entityID }
                        .map(\.id)
                        .sorted()
                    removalIDs.append(contentsOf: mountedTurretIDs)
                }

                for removalID in removalIDs.sorted() {
                    guard let removed = state.entities.entity(id: removalID),
                          let removedStructureType = removed.structureType else { continue }
                    applyRefund(for: removedStructureType, state: &state)
                    unbindPatchIfNeeded(for: removed, state: &state)
                    state.entities.remove(removalID)
                    cleanupRuntimeState(for: removalID, state: &state)
                    context.emit(
                        SimEvent(
                            tick: state.tick,
                            kind: .structureRemoved,
                            entity: removalID
                        )
                    )
                }

                if removalIDs.contains(where: { state.entities.entity(id: $0)?.structureType == .wall }) || structureType == .wall {
                    state.combat.wallNetworksDirty = true
                }
            case .placeConveyor(let position, let direction):
                let request = BuildRequest(
                    structure: .conveyor,
                    position: position,
                    rotation: rotation(for: direction)
                )
                let translated = PlayerCommand(
                    tick: command.tick,
                    actor: command.actor,
                    payload: .placeStructure(request)
                )
                let translatedContext = SystemContext(
                    tickDurationSeconds: context.tickDurationSeconds,
                    commands: [translated],
                    emitEvent: context.emit
                )
                update(state: &state, context: translatedContext)
            case .configureConveyorIO(let entityID, let inputDirection, let outputDirection):
                guard inputDirection != outputDirection else { continue }
                guard let entity = state.entities.entity(id: entityID), entity.structureType == .conveyor else { continue }
                state.economy.conveyorIOByEntity[entityID] = ConveyorIOConfig(
                    inputDirection: inputDirection,
                    outputDirection: outputDirection
                )
            case .rotateBuilding(let entityID):
                state.entities.rotateStructure(entityID)
            case .pinRecipe(let entityID, let recipeID):
                if state.entities.entity(id: entityID)?.category == .structure {
                    state.economy.pinnedRecipeByStructure[entityID] = recipeID
                }
            case .extract:
                // Extraction is deferred for v1; command retained for snapshot compatibility.
                continue
            case .triggerWave:
                state.threat.nextWaveTick = state.tick
            }
        }

        state.rebuildAggregatedInventory()
    }

    private func bindMiner(_ minerID: EntityID, toPatchID patchID: Int, state: inout WorldState) {
        guard let patchIndex = state.orePatches.firstIndex(where: { $0.id == patchID }) else { return }
        state.orePatches[patchIndex].boundMinerID = minerID
        state.entities.updateBoundPatchID(minerID, to: patchID)
    }

    private func rotation(for direction: CardinalDirection) -> Rotation {
        switch direction {
        case .north:
            return .north
        case .east:
            return .east
        case .south:
            return .south
        case .west:
            return .west
        }
    }

    private func applyRefund(for structureType: StructureType, state: inout WorldState) {
        for cost in structureType.buildCosts {
            let refundQuantity = max(0, cost.quantity / 2)
            if refundQuantity > 0 {
                addToHQStorage(itemID: cost.itemID, quantity: refundQuantity, state: &state)
            }
        }
    }

    private enum ConstructionPoolKind {
        case outputBuffer
        case inputBuffer
        case sharedPool
    }

    private struct ConstructionPoolRef {
        var kind: ConstructionPoolKind
        var structureID: EntityID
    }

    private func consumeConstructionCosts(_ costs: [ItemStack], state: inout WorldState) -> Bool {
        guard !costs.isEmpty else { return true }
        let refs = constructionPoolOrder(state: state)
        var poolTotals: [ItemID: Int] = [:]
        for ref in refs {
            for (itemID, quantity) in poolItems(ref: ref, state: state) where quantity > 0 {
                poolTotals[itemID, default: 0] += quantity
            }
        }
        guard costs.allSatisfy({ poolTotals[$0.itemID, default: 0] >= $0.quantity }) else { return false }

        for cost in costs {
            var remaining = cost.quantity
            for ref in refs where remaining > 0 {
                var items = poolItems(ref: ref, state: state)
                let available = items[cost.itemID, default: 0]
                guard available > 0 else { continue }
                let consumed = min(remaining, available)
                let updated = available - consumed
                if updated == 0 {
                    items.removeValue(forKey: cost.itemID)
                } else {
                    items[cost.itemID] = updated
                }
                setPoolItems(items, ref: ref, state: &state)
                remaining -= consumed
            }
            guard remaining == 0 else { return false }
        }

        return true
    }

    private func constructionPoolOrder(state: WorldState) -> [ConstructionPoolRef] {
        let hqID = state.run.hqEntityID
        var refs: [ConstructionPoolRef] = []

        refs += state.economy.structureOutputBuffers.keys.sorted().compactMap { id in
            guard id != hqID else { return nil }
            return ConstructionPoolRef(kind: .outputBuffer, structureID: id)
        }
        refs += state.economy.storageSharedPoolByEntity.keys.sorted().compactMap { id in
            guard id != hqID else { return nil }
            return ConstructionPoolRef(kind: .sharedPool, structureID: id)
        }
        refs += state.economy.structureInputBuffers.keys.sorted().compactMap { id in
            guard id != hqID else { return nil }
            return ConstructionPoolRef(kind: .inputBuffer, structureID: id)
        }

        if let hqID {
            refs.append(ConstructionPoolRef(kind: .sharedPool, structureID: hqID))
            refs.append(ConstructionPoolRef(kind: .outputBuffer, structureID: hqID))
            refs.append(ConstructionPoolRef(kind: .inputBuffer, structureID: hqID))
        }

        return refs
    }

    private func poolItems(ref: ConstructionPoolRef, state: WorldState) -> [ItemID: Int] {
        switch ref.kind {
        case .outputBuffer:
            return state.economy.structureOutputBuffers[ref.structureID, default: [:]]
        case .inputBuffer:
            return state.economy.structureInputBuffers[ref.structureID, default: [:]]
        case .sharedPool:
            return state.economy.storageSharedPoolByEntity[ref.structureID, default: [:]]
        }
    }

    private func setPoolItems(_ items: [ItemID: Int], ref: ConstructionPoolRef, state: inout WorldState) {
        switch ref.kind {
        case .outputBuffer:
            if items.isEmpty {
                state.economy.structureOutputBuffers.removeValue(forKey: ref.structureID)
            } else {
                state.economy.structureOutputBuffers[ref.structureID] = items
            }
        case .inputBuffer:
            if items.isEmpty {
                state.economy.structureInputBuffers.removeValue(forKey: ref.structureID)
            } else {
                state.economy.structureInputBuffers[ref.structureID] = items
            }
        case .sharedPool:
            if items.isEmpty {
                state.economy.storageSharedPoolByEntity.removeValue(forKey: ref.structureID)
            } else {
                state.economy.storageSharedPoolByEntity[ref.structureID] = items
            }
        }
    }

    private func addToHQStorage(itemID: ItemID, quantity: Int, state: inout WorldState) {
        guard quantity > 0 else { return }
        if let hqID = state.run.hqEntityID {
            var pool = state.economy.storageSharedPoolByEntity[hqID, default: [:]]
            pool[itemID, default: 0] += quantity
            state.economy.storageSharedPoolByEntity[hqID] = pool
        } else {
            state.economy.add(itemID: itemID, quantity: quantity)
        }
    }

    private func unbindPatchIfNeeded(for structure: Entity, state: inout WorldState) {
        guard structure.structureType == .miner, let patchID = structure.boundPatchID else { return }
        if let patchIndex = state.orePatches.firstIndex(where: { $0.id == patchID && $0.boundMinerID == structure.id }) {
            state.orePatches[patchIndex].boundMinerID = nil
        }
    }

    private func cleanupRuntimeState(for structureID: EntityID, state: inout WorldState) {
        state.economy.activeRecipeByStructure.removeValue(forKey: structureID)
        state.economy.pinnedRecipeByStructure.removeValue(forKey: structureID)
        state.economy.productionProgressByStructure.removeValue(forKey: structureID)
        state.economy.structureInputBuffers.removeValue(forKey: structureID)
        state.economy.structureOutputBuffers.removeValue(forKey: structureID)
        state.economy.storageSharedPoolByEntity.removeValue(forKey: structureID)
        state.economy.conveyorPayloadByEntity.removeValue(forKey: structureID)
        state.economy.conveyorIOByEntity.removeValue(forKey: structureID)
        state.economy.splitterOutputToggleByEntity.removeValue(forKey: structureID)
        state.economy.mergerInputToggleByEntity.removeValue(forKey: structureID)
        state.combat.lastFireTickByTurret.removeValue(forKey: structureID)
    }
}

public struct EconomySystem: SimulationSystem {
    private let recipesByID: [String: RecipeDef]
    private let buildingDefsByID: [String: BuildingDef]
    private let minimumConstructionStock: [ItemID: Int]
    private let reserveProtectedRecipeIDs: Set<String>
    private let conveyorTicksPerTile: Int

    public init(
        recipes: [RecipeDef] = EconomySystem.defaultRecipes,
        buildings: [BuildingDef] = EconomySystem.defaultBuildings,
        minimumConstructionStock: [ItemID: Int] = EconomySystem.defaultMinimumConstructionStock,
        reserveProtectedRecipeIDs: Set<String> = EconomySystem.defaultReserveProtectedRecipeIDs,
        conveyorTicksPerTile: Int = 5
    ) {
        self.recipesByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        self.buildingDefsByID = Dictionary(uniqueKeysWithValues: buildings.map { ($0.id, $0) })
        self.minimumConstructionStock = minimumConstructionStock
        self.reserveProtectedRecipeIDs = reserveProtectedRecipeIDs
        self.conveyorTicksPerTile = max(1, conveyorTicksPerTile)
    }

    public func update(state: inout WorldState, context: SystemContext) {
        let structures = state.entities.all.filter { $0.category == .structure }
        syncLogisticsRuntime(structures: structures, state: &state)
        syncOrePatchBindings(state: &state)
        rebuildWallNetworksIfNeeded(state: &state, context: context)

        var powerAvailable = 0
        var powerDemand = 0
        for entity in structures {
            guard let structureType = entity.structureType else { continue }
            let structurePower: Int
            if structureType == .miner, !minerCanExtract(entity, state: state) {
                structurePower = 0
            } else {
                structurePower = structureType.powerDemand
            }
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

        advanceConveyors(structures: structures, state: &state)
        produceRawResources(state: &state, tickDuration: tickDuration, efficiency: efficiency, context: context)

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

        drainStructureOutputBuffers(structures: structures, state: &state)
        drainStorageSharedPools(structures: structures, state: &state)
        pruneRuntimeState(for: structures, state: &state)
        state.rebuildAggregatedInventory()

        if state.threat.isWaveActive {
            state.economy.currency += 1
        }
    }

    private func produceRawResources(
        state: inout WorldState,
        tickDuration: Double,
        efficiency: Double,
        context: SystemContext
    ) {
        let miners = state.entities.structures(of: .miner).sorted(by: { $0.id < $1.id })
        guard !miners.isEmpty else { return }

        for miner in miners {
            guard let patchIndex = boundPatchIndex(for: miner, state: &state) else {
                state.economy.productionProgressByStructure[miner.id] = 0
                continue
            }

            let outputCapacity = outputBufferCapacity(for: .miner)
            var outputBuffer = state.economy.structureOutputBuffers[miner.id, default: [:]]
            let currentOutput = outputBuffer.values.reduce(0, +)
            guard currentOutput < outputCapacity else { continue }

            var patch = state.orePatches[patchIndex]
            guard patch.remainingOre > 0 else {
                state.economy.productionProgressByStructure[miner.id] = 0
                continue
            }

            state.economy.productionProgressByStructure[miner.id, default: 0] += tickDuration * efficiency
            var progress = state.economy.productionProgressByStructure[miner.id, default: 0]
            var exhaustedThisTick = false

            while progress + 0.000_001 >= 1.0,
                  patch.remainingOre > 0,
                  outputBuffer.values.reduce(0, +) < outputCapacity {
                outputBuffer[patch.oreType, default: 0] += 1
                patch.remainingOre -= 1
                progress -= 1.0
                if patch.remainingOre <= 0 {
                    exhaustedThisTick = true
                    break
                }
            }

            state.economy.structureOutputBuffers[miner.id] = outputBuffer
            state.economy.productionProgressByStructure[miner.id] = max(0, progress)
            state.orePatches[patchIndex] = patch

            if exhaustedThisTick {
                context.emit(
                    SimEvent(
                        tick: state.tick,
                        kind: .patchExhausted,
                        entity: miner.id,
                        value: patch.id,
                        itemID: patch.oreType
                    )
                )
                context.emit(
                    SimEvent(
                        tick: state.tick,
                        kind: .minerIdled,
                        entity: miner.id,
                        value: patch.id
                    )
                )
            }
        }
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
            guard let structureType = structure.structureType else { continue }

            guard let selectedRecipe = selectRecipe(
                prioritizedRecipeIDs: prioritizedRecipeIDs,
                structureID: structureID,
                state: state
            ) else {
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

            while progress + 0.000_001 >= recipeSeconds,
                  canAffordRecipeInputs(selectedRecipe.inputs, structureID: structureID, state: state),
                  canStoreRecipeOutputs(selectedRecipe.outputs, structureID: structureID, structureType: structureType, state: state) {
                _ = consumeRecipeInputs(selectedRecipe.inputs, structureID: structureID, state: &state)
                storeRecipeOutputs(selectedRecipe.outputs, structureID: structureID, structureType: structureType, state: &state)
                progress -= recipeSeconds
            }

            state.economy.productionProgressByStructure[structureID] = max(0, progress)
        }
    }

    private func selectRecipe(
        prioritizedRecipeIDs: [String],
        structureID: EntityID,
        state: WorldState
    ) -> RecipeDef? {
        let inventory = localInputInventory(for: structureID, state: state)
        if let pinnedRecipeID = state.economy.pinnedRecipeByStructure[structureID],
           let pinnedRecipe = recipesByID[pinnedRecipeID],
           pinnedRecipe.inputs.allSatisfy({ inventory[$0.itemID, default: 0] >= $0.quantity }),
           canRunRecipeWithoutBreachingConstructionStock(recipe: pinnedRecipe, inventory: state.economy.inventories) {
            return pinnedRecipe
        }
        for recipeID in prioritizedRecipeIDs {
            guard let recipe = recipesByID[recipeID] else { continue }
            guard recipe.inputs.allSatisfy({ inventory[$0.itemID, default: 0] >= $0.quantity }) else { continue }
            guard canRunRecipeWithoutBreachingConstructionStock(recipe: recipe, inventory: state.economy.inventories) else { continue }
            return recipe
        }
        return nil
    }

    private func localInputInventory(for structureID: EntityID, state: WorldState) -> [ItemID: Int] {
        state.economy.structureInputBuffers[structureID, default: [:]]
    }

    private func canAffordRecipeInputs(_ inputs: [ItemStack], structureID: EntityID, state: WorldState) -> Bool {
        let localBuffer = state.economy.structureInputBuffers[structureID, default: [:]]
        for input in inputs {
            if localBuffer[input.itemID, default: 0] < input.quantity {
                return false
            }
        }
        return true
    }

    @discardableResult
    private func consumeRecipeInputs(
        _ inputs: [ItemStack],
        structureID: EntityID,
        state: inout WorldState
    ) -> Bool {
        guard canAffordRecipeInputs(inputs, structureID: structureID, state: state) else {
            return false
        }

        var localBuffer = state.economy.structureInputBuffers[structureID, default: [:]]
        for input in inputs {
            let localAvailable = localBuffer[input.itemID, default: 0]
            guard localAvailable >= input.quantity else { return false }
            let updated = localAvailable - input.quantity
            if updated > 0 {
                localBuffer[input.itemID] = updated
            } else {
                localBuffer.removeValue(forKey: input.itemID)
            }
        }

        if inputBufferCapacity(for: structureID, state: state) > 0 || !localBuffer.isEmpty {
            state.economy.structureInputBuffers[structureID] = localBuffer
        } else {
            state.economy.structureInputBuffers.removeValue(forKey: structureID)
        }
        return true
    }

    private func canStoreRecipeOutputs(
        _ outputs: [ItemStack],
        structureID: EntityID,
        structureType: StructureType,
        state: WorldState
    ) -> Bool {
        let capacity = outputBufferCapacity(for: structureType)
        guard capacity > 0 else { return true }

        let current = state.economy.structureOutputBuffers[structureID, default: [:]].values.reduce(0, +)
        let additional = outputs.reduce(0) { $0 + max(0, $1.quantity) }
        return current + additional <= capacity
    }

    private func storeRecipeOutputs(
        _ outputs: [ItemStack],
        structureID: EntityID,
        structureType: StructureType,
        state: inout WorldState
    ) {
        let capacity = outputBufferCapacity(for: structureType)
        guard capacity > 0 else {
            for output in outputs {
                state.economy.add(itemID: output.itemID, quantity: output.quantity)
            }
            return
        }

        var outputBuffer = state.economy.structureOutputBuffers[structureID, default: [:]]
        for output in outputs where output.quantity > 0 {
            outputBuffer[output.itemID, default: 0] += output.quantity
        }
        state.economy.structureOutputBuffers[structureID] = outputBuffer
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

    private func syncLogisticsRuntime(structures: [Entity], state: inout WorldState) {
        let structureTypesByID: [EntityID: StructureType] = Dictionary(
            uniqueKeysWithValues: structures.compactMap { structure in
                guard let structureType = structure.structureType else { return nil }
                return (structure.id, structureType)
            }
        )

        for (structureID, structureType) in structureTypesByID {
            if structureType == .storage || structureType == .hq {
                state.economy.structureInputBuffers.removeValue(forKey: structureID)
                state.economy.structureOutputBuffers.removeValue(forKey: structureID)
                _ = state.economy.storageSharedPoolByEntity[structureID, default: [:]]
            } else if inputBufferCapacity(for: structureType) > 0 {
                _ = state.economy.structureInputBuffers[structureID, default: [:]]
            } else {
                state.economy.structureInputBuffers.removeValue(forKey: structureID)
            }

            if structureType == .storage || structureType == .hq {
                // Storage uses a shared pool rather than split input/output buffers.
            } else if outputBufferCapacity(for: structureType) > 0 {
                _ = state.economy.structureOutputBuffers[structureID, default: [:]]
            } else {
                state.economy.structureOutputBuffers.removeValue(forKey: structureID)
            }

            if !isBeltNode(structureType) {
                state.economy.conveyorPayloadByEntity.removeValue(forKey: structureID)
            }
            if structureType != .conveyor {
                state.economy.conveyorIOByEntity.removeValue(forKey: structureID)
            }
            if structureType != .splitter {
                state.economy.splitterOutputToggleByEntity.removeValue(forKey: structureID)
            }
            if structureType != .merger {
                state.economy.mergerInputToggleByEntity.removeValue(forKey: structureID)
            }
            if structureType != .storage && structureType != .hq {
                state.economy.storageSharedPoolByEntity.removeValue(forKey: structureID)
            }
        }

        let validStructureIDs = Set(structureTypesByID.keys)
        state.economy.structureInputBuffers = state.economy.structureInputBuffers.filter { validStructureIDs.contains($0.key) }
        state.economy.structureOutputBuffers = state.economy.structureOutputBuffers.filter { validStructureIDs.contains($0.key) }
        state.economy.storageSharedPoolByEntity = state.economy.storageSharedPoolByEntity.filter { validStructureIDs.contains($0.key) }
        state.economy.conveyorPayloadByEntity = state.economy.conveyorPayloadByEntity.filter {
            guard let type = structureTypesByID[$0.key] else { return false }
            return isBeltNode(type)
        }
        state.economy.conveyorIOByEntity = state.economy.conveyorIOByEntity.filter {
            structureTypesByID[$0.key] == .conveyor
        }
        state.economy.splitterOutputToggleByEntity = state.economy.splitterOutputToggleByEntity.filter {
            structureTypesByID[$0.key] == .splitter
        }
        state.economy.mergerInputToggleByEntity = state.economy.mergerInputToggleByEntity.filter {
            structureTypesByID[$0.key] == .merger
        }
    }

    private func syncOrePatchBindings(state: inout WorldState) {
        let minerIDs = Set(state.entities.structures(of: .miner).map(\.id))
        let patchIDs = Set(state.orePatches.map(\.id))

        for patchIndex in state.orePatches.indices {
            if let boundMinerID = state.orePatches[patchIndex].boundMinerID,
               !minerIDs.contains(boundMinerID) {
                state.orePatches[patchIndex].boundMinerID = nil
            }
        }

        for miner in state.entities.structures(of: .miner) {
            guard let patchID = miner.boundPatchID else { continue }
            if !patchIDs.contains(patchID) {
                state.entities.updateBoundPatchID(miner.id, to: nil)
                state.economy.productionProgressByStructure[miner.id] = 0
            }
        }
    }

    private func minerCanExtract(_ miner: Entity, state: WorldState) -> Bool {
        guard let patchID = miner.boundPatchID,
              let patch = state.orePatches.first(where: { $0.id == patchID }) else {
            return false
        }
        return patch.remainingOre > 0 && patch.boundMinerID == miner.id
    }

    private func boundPatchIndex(for miner: Entity, state: inout WorldState) -> Int? {
        if let patchID = miner.boundPatchID,
           let patchIndex = state.orePatches.firstIndex(where: { $0.id == patchID }),
           isAdjacent(miner.position, state.orePatches[patchIndex].position),
           state.orePatches[patchIndex].boundMinerID == miner.id {
            return patchIndex
        }

        let candidates = state.orePatches.indices
            .filter { index in
                let patch = state.orePatches[index]
                return patch.boundMinerID == nil && !patch.isExhausted && isAdjacent(miner.position, patch.position)
            }
            .sorted { lhs, rhs in
                state.orePatches[lhs].id < state.orePatches[rhs].id
            }

        guard let selectedIndex = candidates.first else { return nil }
        let patchID = state.orePatches[selectedIndex].id
        state.orePatches[selectedIndex].boundMinerID = miner.id
        state.entities.updateBoundPatchID(miner.id, to: patchID)
        return selectedIndex
    }

    private func isAdjacent(_ lhs: GridPosition, _ rhs: GridPosition) -> Bool {
        abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y) == 1
    }

    private func advanceConveyors(structures: [Entity], state: inout WorldState) {
        let beltNodes = structures
            .filter { structure in
                guard let type = structure.structureType else { return false }
                return isBeltNode(type)
            }
            .sorted(by: { $0.id < $1.id })

        guard !beltNodes.isEmpty else { return }

        let beltNodesByID = Dictionary(uniqueKeysWithValues: beltNodes.map { ($0.id, $0) })
        let beltNodeIDByPosition = Dictionary(uniqueKeysWithValues: beltNodes.map { ($0.position, $0.id) })
        var structuresByPosition: [GridPosition: Entity] = [:]
        var wallsByPosition: [GridPosition: EntityID] = [:]
        for structure in structures.sorted(by: { $0.id < $1.id }) {
            if structuresByPosition[structure.position] == nil {
                structuresByPosition[structure.position] = structure
            }
            if structure.structureType == .wall {
                wallsByPosition[structure.position] = structure.id
            }
        }

        for node in beltNodes {
            guard var payload = state.economy.conveyorPayloadByEntity[node.id] else { continue }
            payload.progressTicks = min(conveyorTicksPerTile, payload.progressTicks + 1)
            state.economy.conveyorPayloadByEntity[node.id] = payload
        }

        let readySourcePositions = Set(
            beltNodes.compactMap { node -> GridPosition? in
                guard let payload = state.economy.conveyorPayloadByEntity[node.id],
                      payload.progressTicks >= conveyorTicksPerTile else {
                    return nil
                }
                return node.position
            }
        )

        for node in beltNodes {
            guard let payload = state.economy.conveyorPayloadByEntity[node.id] else { continue }
            guard payload.progressTicks >= conveyorTicksPerTile else { continue }
            guard let nodeType = node.structureType else { continue }

            var delivered = false
            let targetPositions = transferTargets(for: node, structureType: nodeType, state: state)
            for targetPosition in targetPositions {
                if let targetBeltID = beltNodeIDByPosition[targetPosition],
                   state.economy.conveyorPayloadByEntity[targetBeltID] == nil,
                   enqueueBeltPayload(
                    itemID: payload.itemID,
                    targetStructureID: targetBeltID,
                    sourcePosition: node.position,
                    readySourcePositions: readySourcePositions,
                    nodesByID: beltNodesByID,
                    state: &state
                   ) {
                    if nodeType == .splitter {
                        state.economy.splitterOutputToggleByEntity[node.id, default: 0] += 1
                    }
                    state.economy.conveyorPayloadByEntity.removeValue(forKey: node.id)
                    delivered = true
                    break
                }

                if let targetStructure = structuresByPosition[targetPosition],
                   let targetType = targetStructure.structureType,
                   enqueueInputItem(
                    itemID: payload.itemID,
                    structureID: targetStructure.id,
                    structureType: targetType,
                    sourcePosition: node.position,
                    state: &state
                   ) {
                    if nodeType == .splitter {
                        state.economy.splitterOutputToggleByEntity[node.id, default: 0] += 1
                    }
                    state.economy.conveyorPayloadByEntity.removeValue(forKey: node.id)
                    delivered = true
                    break
                }

                if let wallID = wallsByPosition[targetPosition],
                   injectWallNetwork(itemID: payload.itemID, wallID: wallID, state: &state) {
                    if nodeType == .splitter {
                        state.economy.splitterOutputToggleByEntity[node.id, default: 0] += 1
                    }
                    state.economy.conveyorPayloadByEntity.removeValue(forKey: node.id)
                    delivered = true
                    break
                }
            }

            if !delivered {
                continue
            }
        }
    }

    private func drainStructureOutputBuffers(structures: [Entity], state: inout WorldState) {
        var beltNodesByPosition: [GridPosition: EntityID] = [:]
        var beltNodesByID: [EntityID: Entity] = [:]
        var structuresByPosition: [GridPosition: Entity] = [:]
        var wallsByPosition: [GridPosition: EntityID] = [:]
        for structure in structures.sorted(by: { $0.id < $1.id }) {
            if structuresByPosition[structure.position] == nil {
                structuresByPosition[structure.position] = structure
            }
            if let type = structure.structureType, isBeltNode(type), beltNodesByPosition[structure.position] == nil {
                beltNodesByPosition[structure.position] = structure.id
                beltNodesByID[structure.id] = structure
            }
            if structure.structureType == .wall {
                wallsByPosition[structure.position] = structure.id
            }
        }

        for structure in structures.sorted(by: { $0.id < $1.id }) {
            guard let structureType = structure.structureType else { continue }
            guard outputBufferCapacity(for: structureType) > 0 else { continue }
            guard !(state.economy.structureOutputBuffers[structure.id, default: [:]].isEmpty) else { continue }
            for outputDirection in buildingTransferDirections(for: structureType) {
                let targetPosition = structure.position.translated(by: outputDirection)
                guard let itemID = popFirstOutputItem(structureID: structure.id, state: &state) else {
                    continue
                }

                var delivered = false
                if let beltNodeID = beltNodesByPosition[targetPosition],
                   enqueueBeltPayload(
                    itemID: itemID,
                    targetStructureID: beltNodeID,
                    sourcePosition: structure.position,
                    readySourcePositions: [],
                    nodesByID: beltNodesByID,
                    state: &state
                   ) {
                    delivered = true
                } else if let targetStructure = structuresByPosition[targetPosition],
                          let targetType = targetStructure.structureType,
                          enqueueInputItem(
                            itemID: itemID,
                            structureID: targetStructure.id,
                            structureType: targetType,
                            sourcePosition: structure.position,
                            state: &state
                          ) {
                    delivered = true
                } else if let wallID = wallsByPosition[targetPosition],
                          injectWallNetwork(itemID: itemID, wallID: wallID, state: &state) {
                    delivered = true
                }

                if delivered {
                    continue
                }

                var outputBuffer = state.economy.structureOutputBuffers[structure.id, default: [:]]
                outputBuffer[itemID, default: 0] += 1
                state.economy.structureOutputBuffers[structure.id] = outputBuffer
            }
        }
    }

    private func drainStorageSharedPools(structures: [Entity], state: inout WorldState) {
        let beltNodes = structures
            .filter { structure in
                guard let type = structure.structureType else { return false }
                return isBeltNode(type)
            }
            .sorted(by: { $0.id < $1.id })
        let beltNodesByPosition = Dictionary(uniqueKeysWithValues: beltNodes.map { ($0.position, $0.id) })
        let beltNodesByID = Dictionary(uniqueKeysWithValues: beltNodes.map { ($0.id, $0) })
        var structuresByPosition: [GridPosition: Entity] = [:]
        var wallsByPosition: [GridPosition: EntityID] = [:]
        for structure in structures.sorted(by: { $0.id < $1.id }) {
            if structuresByPosition[structure.position] == nil {
                structuresByPosition[structure.position] = structure
            }
            if structure.structureType == .wall {
                wallsByPosition[structure.position] = structure.id
            }
        }

        let storages = structures
            .filter { $0.structureType == .storage || $0.structureType == .hq }
            .sorted(by: { $0.id < $1.id })
        for storage in storages {
            for outputDirection in CardinalDirection.allCases {
                let targetPosition = storage.position.translated(by: outputDirection)
                guard let itemID = popFirstStoragePoolItem(storageID: storage.id, state: &state) else {
                    continue
                }

                var delivered = false
                if let beltNodeID = beltNodesByPosition[targetPosition],
                   enqueueBeltPayload(
                    itemID: itemID,
                    targetStructureID: beltNodeID,
                    sourcePosition: storage.position,
                    readySourcePositions: [],
                    nodesByID: beltNodesByID,
                    state: &state
                   ) {
                    delivered = true
                } else if let targetStructure = structuresByPosition[targetPosition],
                          let targetType = targetStructure.structureType,
                          enqueueInputItem(
                            itemID: itemID,
                            structureID: targetStructure.id,
                            structureType: targetType,
                            sourcePosition: storage.position,
                            state: &state
                          ) {
                    delivered = true
                } else if let wallID = wallsByPosition[targetPosition],
                          injectWallNetwork(itemID: itemID, wallID: wallID, state: &state) {
                    delivered = true
                }

                if !delivered {
                    pushStoragePoolItem(itemID: itemID, storageID: storage.id, state: &state)
                }
            }
        }
    }

    private func transferTargets(for node: Entity, structureType: StructureType, state: WorldState) -> [GridPosition] {
        switch structureType {
        case .conveyor:
            let io = resolvedConveyorIO(for: node, state: state)
            return [node.position.translated(by: io.outputDirection)]
        case .merger:
            let facing = node.rotation.direction
            return [node.position.translated(by: facing)]
        case .splitter:
            let facing = node.rotation.direction
            let toggle = state.economy.splitterOutputToggleByEntity[node.id, default: 0]
            let first = toggle % 2 == 0 ? facing.left : facing.right
            let second = first == facing.left ? facing.right : facing.left
            return [node.position.translated(by: first), node.position.translated(by: second)]
        default:
            return []
        }
    }

    @discardableResult
    private func enqueueBeltPayload(
        itemID: ItemID,
        targetStructureID: EntityID,
        sourcePosition: GridPosition,
        readySourcePositions: Set<GridPosition>,
        nodesByID: [EntityID: Entity],
        state: inout WorldState
    ) -> Bool {
        guard state.economy.conveyorPayloadByEntity[targetStructureID] == nil else { return false }
        guard let targetNode = nodesByID[targetStructureID], let targetType = targetNode.structureType else { return false }
        guard isBeltNode(targetType) else { return false }

        if targetType == .conveyor {
            let io = resolvedConveyorIO(for: targetNode, state: state)
            let inputPosition = targetNode.position.translated(by: io.inputDirection)
            guard sourcePosition == inputPosition else { return false }
        } else if targetType == .merger {
            let facing = targetNode.rotation.direction
            let leftInput = targetNode.position.translated(by: facing.left)
            let rightInput = targetNode.position.translated(by: facing.right)
            guard sourcePosition == leftInput || sourcePosition == rightInput else { return false }

            let toggle = state.economy.mergerInputToggleByEntity[targetStructureID, default: 0]
            let preferredInput = toggle % 2 == 0 ? leftInput : rightInput
            if sourcePosition != preferredInput && readySourcePositions.contains(preferredInput) {
                return false
            }
            state.economy.mergerInputToggleByEntity[targetStructureID] = toggle + 1
        }

        state.economy.conveyorPayloadByEntity[targetStructureID] = ConveyorPayload(itemID: itemID, progressTicks: 0)
        return true
    }

    private func resolvedConveyorIO(for node: Entity, state: WorldState) -> ConveyorIOConfig {
        if let configured = state.economy.conveyorIOByEntity[node.id] {
            return configured
        }
        return ConveyorIOConfig.default(for: node.rotation)
    }

    private func buildingTransferDirections(for structureType: StructureType) -> [CardinalDirection] {
        switch structureType {
        case .miner, .smelter, .assembler, .ammoModule, .storage, .hq:
            return CardinalDirection.allCases
        default:
            return []
        }
    }

    private func isBeltNode(_ structureType: StructureType) -> Bool {
        structureType == .conveyor || structureType == .splitter || structureType == .merger
    }

    private func popFirstOutputItem(structureID: EntityID, matching filter: ItemFilter? = nil, state: inout WorldState) -> ItemID? {
        var outputBuffer = state.economy.structureOutputBuffers[structureID, default: [:]]
        let candidates = outputBuffer.keys.sorted().filter { itemMatchesFilter(itemID: $0, filter: filter) }
        guard let itemID = candidates.first else { return nil }
        let quantity = outputBuffer[itemID, default: 0]
        guard quantity > 0 else { return nil }
        if quantity == 1 {
            outputBuffer.removeValue(forKey: itemID)
        } else {
            outputBuffer[itemID] = quantity - 1
        }
        state.economy.structureOutputBuffers[structureID] = outputBuffer
        return itemID
    }

    private func popFirstStoragePoolItem(storageID: EntityID, matching filter: ItemFilter? = nil, state: inout WorldState) -> ItemID? {
        var pool = state.economy.storageSharedPoolByEntity[storageID, default: [:]]
        let candidates = pool.keys.sorted().filter { itemMatchesFilter(itemID: $0, filter: filter) }
        guard let itemID = candidates.first else { return nil }
        let quantity = pool[itemID, default: 0]
        guard quantity > 0 else { return nil }
        if quantity == 1 {
            pool.removeValue(forKey: itemID)
        } else {
            pool[itemID] = quantity - 1
        }
        state.economy.storageSharedPoolByEntity[storageID] = pool
        return itemID
    }

    private func pushStoragePoolItem(itemID: ItemID, storageID: EntityID, state: inout WorldState) {
        var pool = state.economy.storageSharedPoolByEntity[storageID, default: [:]]
        pool[itemID, default: 0] += 1
        state.economy.storageSharedPoolByEntity[storageID] = pool
    }

    private struct ResolvedPort {
        let id: String
        let direction: CardinalDirection
        let mode: PortMode
        let filter: ItemFilter
        let capacity: Int
    }

    private func resolvedPorts(for structure: Entity) -> [ResolvedPort] {
        guard let structureType = structure.structureType else { return [] }
        return resolvedPorts(for: structureType, rotation: structure.rotation)
    }

    private func resolvedPorts(for structureType: StructureType, rotation: Rotation) -> [ResolvedPort] {
        let ports: [PortDef]
        if let definition = buildingDefsByID[structureType.rawValue] {
            ports = definition.ports
        } else if structureType == .hq {
            let anyFilter = ItemFilter.any
            ports = [
                PortDef(id: "hq_west", direction: .west, mode: .bidirectional, filter: anyFilter, bufferCapacity: 6),
                PortDef(id: "hq_north", direction: .north, mode: .bidirectional, filter: anyFilter, bufferCapacity: 6),
                PortDef(id: "hq_east", direction: .east, mode: .bidirectional, filter: anyFilter, bufferCapacity: 6),
                PortDef(id: "hq_south", direction: .south, mode: .bidirectional, filter: anyFilter, bufferCapacity: 6)
            ]
        } else {
            return []
        }
        return ports.map { port in
            ResolvedPort(
                id: port.id,
                direction: rotate(portDirection: port.direction, by: rotation),
                mode: port.mode,
                filter: port.filter,
                capacity: port.bufferCapacity
            )
        }
    }

    private func resolvedInputPorts(for structure: Entity) -> [ResolvedPort] {
        resolvedPorts(for: structure).filter { $0.mode == .input || $0.mode == .bidirectional }
    }

    private func resolvedOutputPorts(for structure: Entity, includeBidirectional: Bool) -> [ResolvedPort] {
        let modes: Set<PortMode> = includeBidirectional ? [.output, .bidirectional] : [.output]
        return resolvedPorts(for: structure)
            .filter { modes.contains($0.mode) }
            .sorted { lhs, rhs in
                if lhs.direction.rawValue == rhs.direction.rawValue {
                    return lhs.id < rhs.id
                }
                return lhs.direction.rawValue < rhs.direction.rawValue
            }
    }

    private func rotate(portDirection: PortDirection, by rotation: Rotation) -> CardinalDirection {
        let base = CardinalDirection(rawValue: portDirection.rawValue) ?? .north
        switch rotation {
        case .north:
            return base
        case .east:
            return base.right
        case .south:
            return base.opposite
        case .west:
            return base.left
        }
    }

    private func itemMatchesFilter(itemID: ItemID, filter: ItemFilter?) -> Bool {
        guard let filter else { return true }
        switch filter {
        case .any:
            return true
        case .allow(let allowed):
            return allowed.contains(itemID)
        }
    }

    private func injectWallNetwork(itemID: ItemID, wallID: EntityID, state: inout WorldState) -> Bool {
        guard let networkID = state.combat.wallNetworkByWallEntityID[wallID],
              var network = state.combat.wallNetworks[networkID] else {
            return false
        }

        if itemID.hasPrefix("ammo_") {
            let totalAmmo = network.ammoPoolByItemID.values.reduce(0, +)
            guard totalAmmo < network.capacity else { return false }
            network.ammoPoolByItemID[itemID, default: 0] += 1
            state.combat.wallNetworks[networkID] = network
            return true
        }

        if itemID == "repair_kit" {
            var damagedWalls = network.wallEntityIDs.compactMap { id -> Entity? in
                state.entities.entity(id: id)
            }.filter { wall in
                wall.health < wall.maxHealth
            }
            damagedWalls.sort { lhs, rhs in
                if lhs.health == rhs.health { return lhs.id < rhs.id }
                return lhs.health < rhs.health
            }
            guard let mostDamaged = damagedWalls.first else { return false }
            let repairedHealth = min(mostDamaged.maxHealth, mostDamaged.health + 50)
            let delta = repairedHealth - mostDamaged.health
            guard delta > 0 else { return false }
            state.entities.damage(mostDamaged.id, amount: -delta)
            return true
        }

        return false
    }

    private func rebuildWallNetworksIfNeeded(state: inout WorldState, context: SystemContext) {
        guard state.combat.wallNetworksDirty else { return }

        let oldNetworks = state.combat.wallNetworks
        let walls = state.entities.structures(of: .wall).sorted { $0.id < $1.id }

        guard !walls.isEmpty else {
            state.combat.wallNetworkByWallEntityID = [:]
            state.combat.wallNetworks = [:]
            state.combat.wallNetworksDirty = false
            context.emit(SimEvent(tick: state.tick, kind: .wallNetworkRebuilt))
            return
        }

        let wallsByID = Dictionary(uniqueKeysWithValues: walls.map { ($0.id, $0) })
        let wallIDsByPosition = Dictionary(uniqueKeysWithValues: walls.map { ($0.position, $0.id) })
        var visited: Set<EntityID> = []
        var components: [[EntityID]] = []

        for wall in walls {
            guard !visited.contains(wall.id) else { continue }
            var queue: [EntityID] = [wall.id]
            visited.insert(wall.id)
            var component: [EntityID] = []

            while !queue.isEmpty {
                let currentID = queue.removeFirst()
                component.append(currentID)
                guard let currentWall = wallsByID[currentID] else { continue }

                let neighbors = [
                    currentWall.position.translated(byX: 1),
                    currentWall.position.translated(byX: -1),
                    currentWall.position.translated(byY: 1),
                    currentWall.position.translated(byY: -1)
                ]
                for neighbor in neighbors {
                    guard let neighborID = wallIDsByPosition[neighbor] else { continue }
                    guard !visited.contains(neighborID) else { continue }
                    visited.insert(neighborID)
                    queue.append(neighborID)
                }
            }

            components.append(component.sorted())
        }

        var newWallNetworkByWallEntityID: [EntityID: Int] = [:]
        var newWallNetworks: [Int: WallNetworkState] = [:]

        for (index, component) in components.enumerated() {
            let networkID = index + 1
            let capacity = component.count * 12
            var ammoPool: [ItemID: Int] = [:]

            // Proportional pool carry-over by overlap count from old networks.
            for oldNetwork in oldNetworks.values {
                let overlapCount = oldNetwork.wallEntityIDs.filter { component.contains($0) }.count
                guard overlapCount > 0 else { continue }
                let oldWallCount = max(1, oldNetwork.wallEntityIDs.count)
                for (itemID, quantity) in oldNetwork.ammoPoolByItemID {
                    let allocated = (quantity * overlapCount) / oldWallCount
                    if allocated > 0 {
                        ammoPool[itemID, default: 0] += allocated
                    }
                }
            }

            trimAmmoPoolToCapacity(&ammoPool, capacity: capacity)
            newWallNetworks[networkID] = WallNetworkState(
                id: networkID,
                wallEntityIDs: component,
                ammoPoolByItemID: ammoPool,
                capacity: capacity
            )
            for wallID in component {
                newWallNetworkByWallEntityID[wallID] = networkID
            }
        }

        state.combat.wallNetworkByWallEntityID = newWallNetworkByWallEntityID
        state.combat.wallNetworks = newWallNetworks
        state.combat.wallNetworksDirty = false

        if !oldNetworks.isEmpty && oldNetworks.count != newWallNetworks.count {
            context.emit(SimEvent(tick: state.tick, kind: .wallNetworkSplit, value: newWallNetworks.count))
        }
        context.emit(SimEvent(tick: state.tick, kind: .wallNetworkRebuilt))
    }

    private func trimAmmoPoolToCapacity(_ ammoPool: inout [ItemID: Int], capacity: Int) {
        guard capacity >= 0 else {
            ammoPool = [:]
            return
        }

        var total = ammoPool.values.reduce(0, +)
        guard total > capacity else { return }

        for itemID in ammoPool.keys.sorted() {
            guard total > capacity else { break }
            let overflow = total - capacity
            let quantity = ammoPool[itemID, default: 0]
            guard quantity > 0 else { continue }
            let reduction = min(quantity, overflow)
            let updated = quantity - reduction
            if updated > 0 {
                ammoPool[itemID] = updated
            } else {
                ammoPool.removeValue(forKey: itemID)
            }
            total -= reduction
        }
    }

    @discardableResult
    private func enqueueInputItem(
        itemID: ItemID,
        structureID: EntityID,
        structureType: StructureType,
        sourcePosition: GridPosition? = nil,
        state: inout WorldState
    ) -> Bool {
        guard let structure = state.entities.entity(id: structureID) else { return false }

        if structureType == .storage || structureType == .hq {
            guard canAcceptInputViaPortModel(itemID: itemID, structure: structure, sourcePosition: sourcePosition, state: state) else { return false }
            var pool = state.economy.storageSharedPoolByEntity[structureID, default: [:]]
            let capacity = storagePoolCapacity(for: structureType, structure: structure)
            let current = pool.values.reduce(0, +)
            guard current < capacity else { return false }
            pool[itemID, default: 0] += 1
            state.economy.storageSharedPoolByEntity[structureID] = pool
            return true
        }

        let capacity = inputBufferCapacity(for: structureType)
        guard capacity > 0 else { return false }
        guard canAcceptInputViaPortModel(itemID: itemID, structure: structure, sourcePosition: sourcePosition, state: state) else { return false }

        var inputBuffer = state.economy.structureInputBuffers[structureID, default: [:]]
        let current = inputBuffer.values.reduce(0, +)
        guard current < capacity else { return false }

        inputBuffer[itemID, default: 0] += 1
        state.economy.structureInputBuffers[structureID] = inputBuffer
        return true
    }

    private func canAcceptInputViaPortModel(
        itemID: ItemID,
        structure: Entity,
        sourcePosition: GridPosition?,
        state: WorldState
    ) -> Bool {
        _ = sourcePosition
        _ = state
        guard let structureType = structure.structureType else { return false }
        return acceptsInputByStructureType(itemID: itemID, structureType: structureType)
    }

    private func storagePoolCapacity(for structureType: StructureType, structure: Entity) -> Int {
        switch structureType {
        case .storage:
            let inputCap = resolvedInputPorts(for: structure).reduce(0) { $0 + $1.capacity }
            return inputCap > 0 ? inputCap : 48
        case .hq:
            return 24
        default:
            return 0
        }
    }

    private func acceptsInputByStructureType(itemID: ItemID, structureType: StructureType) -> Bool {
        switch structureType {
        case .smelter:
            return itemID == "ore_iron" || itemID == "ore_copper" || itemID == "ore_coal" || itemID == "plate_iron"
        case .assembler:
            return itemID == "plate_iron"
                || itemID == "plate_copper"
                || itemID == "plate_steel"
                || itemID == "ore_coal"
                || itemID == "gear"
                || itemID == "circuit"
        case .ammoModule:
            return itemID == "plate_iron"
                || itemID == "plate_steel"
                || itemID == "ammo_light"
                || itemID == "power_cell"
                || itemID == "circuit"
        case .storage:
            return true
        case .hq:
            return true
        case .turretMount:
            return itemID.hasPrefix("ammo_")
        default:
            return false
        }
    }

    private func inputBufferCapacity(for structureID: EntityID, state: WorldState) -> Int {
        guard let structureType = state.entities.entity(id: structureID)?.structureType else { return 0 }
        return inputBufferCapacity(for: structureType)
    }

    private func inputBufferCapacity(for structureType: StructureType) -> Int {
        switch structureType {
        case .smelter, .assembler, .ammoModule:
            return 12
        case .storage:
            return 24
        case .turretMount:
            return 6
        default:
            return 0
        }
    }

    private func outputBufferCapacity(for structureType: StructureType) -> Int {
        switch structureType {
        case .miner:
            return 8
        case .smelter, .assembler:
            return 4
        case .ammoModule:
            return 8
        case .storage:
            return 24
        default:
            return 0
        }
    }

    private func pruneRuntimeState(for structures: [Entity], state: inout WorldState) {
        let validStructureIDs = Set(structures.map(\.id))
        state.economy.activeRecipeByStructure = state.economy.activeRecipeByStructure.filter { validStructureIDs.contains($0.key) }
        state.economy.pinnedRecipeByStructure = state.economy.pinnedRecipeByStructure.filter { validStructureIDs.contains($0.key) }
        state.economy.productionProgressByStructure = state.economy.productionProgressByStructure.filter { validStructureIDs.contains($0.key) }
        state.economy.structureInputBuffers = state.economy.structureInputBuffers.filter { validStructureIDs.contains($0.key) }
        state.economy.structureOutputBuffers = state.economy.structureOutputBuffers.filter { validStructureIDs.contains($0.key) }
        state.economy.storageSharedPoolByEntity = state.economy.storageSharedPoolByEntity.filter { validStructureIDs.contains($0.key) }
        state.economy.conveyorPayloadByEntity = state.economy.conveyorPayloadByEntity.filter { validStructureIDs.contains($0.key) }
        state.economy.conveyorIOByEntity = state.economy.conveyorIOByEntity.filter { validStructureIDs.contains($0.key) }
        state.economy.splitterOutputToggleByEntity = state.economy.splitterOutputToggleByEntity.filter { validStructureIDs.contains($0.key) }
        state.economy.mergerInputToggleByEntity = state.economy.mergerInputToggleByEntity.filter { validStructureIDs.contains($0.key) }
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

    public static var defaultBuildings: [BuildingDef] {
        if let loaded = CanonicalBootstrapContent.bundle?.buildings, !loaded.isEmpty {
            return loaded
        }
        return []
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
    private let enemyDefsByID: [EnemyID: EnemyDef]
    private let handAuthoredByIndex: [Int: WaveDef]
    private let proceduralConfig: ProceduralWaveConfigDef
    private let maxConcurrentEnemies: Int

    private struct SpawnCluster {
        var id: Int
        var entryPoint: GridPosition
        var spawnPoint: GridPosition
        var activationDelay: UInt64
    }

    public init(
        raidRollModulus: UInt64 = 97,
        raidRollTrigger: UInt64 = 3,
        raidCooldownTicks: UInt64 = 220,
        enableRaids: Bool = true,
        enemyDefinitions: [EnemyDef] = WaveSystem.defaultEnemyDefinitions,
        waveContent: WaveContentDef = WaveSystem.defaultWaveContent,
        maxConcurrentEnemies: Int = 500
    ) {
        self.raidRollModulus = raidRollModulus
        self.raidRollTrigger = raidRollTrigger
        self.raidCooldownTicks = raidCooldownTicks
        self.enableRaids = enableRaids
        self.enemyDefsByID = Dictionary(uniqueKeysWithValues: enemyDefinitions.map { ($0.id, $0) })
        self.handAuthoredByIndex = Dictionary(uniqueKeysWithValues: waveContent.handAuthoredWaves.map { ($0.index, $0) })
        self.proceduralConfig = waveContent.proceduralConfig
        self.maxConcurrentEnemies = max(1, maxConcurrentEnemies)
    }

    public func update(state: inout WorldState, context: SystemContext) {
        emitLifecycleEvents(state: &state, context: context)

        if state.run.phase == .gracePeriod {
            guard state.tick >= state.threat.graceEndsAtTick else { return }
            state.run.phase = .playing
            state.threat.nextTrickleTick = state.tick
            state.threat.nextWaveTick = state.tick + state.threat.waveGapBaseTicks
            if !state.run.gracePeriodEndedEmitted {
                state.run.gracePeriodEndedEmitted = true
                context.emit(SimEvent(tick: state.tick, kind: .gracePeriodEnded))
            }
            return
        }

        guard state.run.phase == .playing else { return }
        drainPendingSpawns(state: &state, context: context)

        if state.tick >= state.threat.nextTrickleTick {
            scheduleTrickleSpawns(state: &state)
            state.threat.nextTrickleTick = state.tick + state.threat.trickleIntervalTicks
        }

        if !state.threat.isWaveActive && state.tick >= state.threat.nextWaveTick {
            state.threat.isWaveActive = true
            state.threat.waveIndex += 1
            state.threat.waveEndsAtTick = state.tick + state.threat.waveDurationTicks
            context.emit(SimEvent(tick: state.tick, kind: .waveStarted, value: state.threat.waveIndex))
            scheduleWaveSurgeSpawns(state: &state)
        }

        if state.threat.isWaveActive,
           let endTick = state.threat.waveEndsAtTick,
           state.tick >= endTick {
            state.threat.isWaveActive = false
            state.threat.waveEndsAtTick = nil
            state.threat.nextWaveTick = state.tick + nextWaveGapTicks(state: state)
            context.emit(SimEvent(tick: state.tick, kind: .waveCleared, value: state.threat.waveIndex))
            context.emit(SimEvent(tick: state.tick, kind: .waveEnded, value: state.threat.waveIndex))

            if state.threat.waveIndex % state.threat.milestoneEvery == 0,
               state.threat.waveIndex != state.threat.lastMilestoneWave {
                state.threat.lastMilestoneWave = state.threat.waveIndex
                let milestoneReward = state.threat.waveIndex * 10
                state.economy.currency += milestoneReward
                context.emit(SimEvent(tick: state.tick, kind: .milestoneReached, value: state.threat.waveIndex))
            }
        }

        state.threat.telemetry.queuedSpawnBacklog = state.threat.pendingSpawns.count
    }

    private func drainPendingSpawns(state: inout WorldState, context: SystemContext) {
        guard !state.threat.pendingSpawns.isEmpty else { return }

        state.threat.pendingSpawns.sort { lhs, rhs in
            if lhs.spawnTick != rhs.spawnTick { return lhs.spawnTick < rhs.spawnTick }
            if lhs.clusterID != rhs.clusterID { return lhs.clusterID < rhs.clusterID }
            if lhs.waveIndex != rhs.waveIndex { return lhs.waveIndex < rhs.waveIndex }
            return lhs.enemyID < rhs.enemyID
        }

        while let next = state.threat.pendingSpawns.first {
            guard next.spawnTick <= state.tick else { break }
            guard state.combat.enemies.count < maxConcurrentEnemies else { break }
            _ = state.threat.pendingSpawns.removeFirst()
            spawnEnemy(from: next, state: &state, context: context)
        }
    }

    private func scheduleTrickleSpawns(state: inout WorldState) {
        let minCount = max(1, state.threat.trickleMinCount)
        let maxCount = max(minCount, state.threat.trickleMaxCount)
        let count = minCount + Int(nextRandom(modulus: UInt64(maxCount - minCount + 1), state: &state))

        let trickleEnemyIDs: [EnemyID]
        switch state.run.difficulty {
        case .hard:
            trickleEnemyIDs = ["swarmling", "drone_scout"]
        case .easy, .normal:
            trickleEnemyIDs = ["swarmling"]
        }

        for offset in 0..<count {
            guard let entry = randomPerimeterEntryPoint(state: &state) else { continue }
            let enemyID = trickleEnemyIDs[Int(nextRandom(modulus: UInt64(trickleEnemyIDs.count), state: &state))]
            state.threat.pendingSpawns.append(
                PendingEnemySpawn(
                    spawnTick: state.tick + UInt64(offset * 3),
                    enemyID: enemyID,
                    waveIndex: state.threat.waveIndex,
                    clusterID: 0,
                    entryPoint: entry,
                    spawnPosition: outsideSpawnPosition(for: entry, board: state.board)
                )
            )
        }
    }

    private func scheduleWaveSurgeSpawns(state: inout WorldState) {
        let waveIndex = state.threat.waveIndex
        let groups = groupsForWave(index: waveIndex, state: &state)
        guard !groups.isEmpty else { return }
        guard let clusters = makeSpawnClusters(state: &state), !clusters.isEmpty else { return }

        var clusterSpawnIndices = Array(repeating: 0, count: clusters.count)
        var ordering = 0

        for group in groups {
            for _ in 0..<group.count {
                let baseCluster = ordering % clusters.count
                var clusterIndex = baseCluster
                if clusters.count > 1 && nextRandom(modulus: 100, state: &state) < 20 {
                    let direction = nextRandom(modulus: 2, state: &state) == 0 ? -1 : 1
                    clusterIndex = (baseCluster + direction + clusters.count) % clusters.count
                }

                let cluster = clusters[clusterIndex]
                let spawnTick = state.tick
                    + group.delayTicks
                    + cluster.activationDelay
                    + UInt64(clusterSpawnIndices[clusterIndex] * 3)
                clusterSpawnIndices[clusterIndex] += 1

                state.threat.pendingSpawns.append(
                    PendingEnemySpawn(
                        spawnTick: spawnTick,
                        enemyID: group.enemyID,
                        waveIndex: waveIndex,
                        clusterID: cluster.id,
                        entryPoint: cluster.entryPoint,
                        spawnPosition: cluster.spawnPoint
                    )
                )
                ordering += 1
            }
        }
    }

    private func spawnEnemy(from spawn: PendingEnemySpawn, state: inout WorldState, context: SystemContext) {
        guard let enemyDef = enemyDefsByID[spawn.enemyID] else { return }

        let enemyID = state.entities.spawnEnemy(at: spawn.spawnPosition, health: enemyDef.health)
        state.combat.enemies[enemyID] = EnemyRuntime(
            id: enemyID,
            enemyID: enemyDef.id,
            archetype: enemyArchetype(for: enemyDef.id),
            moveEveryTicks: ticksPerMovement(speed: enemyDef.speed),
            baseDamage: enemyDef.baseDamage,
            rewardCurrency: max(1, enemyDef.threatCost / 2),
            behaviorModifier: enemyDef.behaviorModifier,
            wallDamageMultiplier: enemyDef.wallDamageMultiplier ?? 1.0,
            entryPoint: spawn.entryPoint
        )

        state.threat.telemetry.spawnedEnemiesByWave[spawn.waveIndex, default: 0] += 1
        context.emit(SimEvent(tick: state.tick, kind: .enemySpawned, entity: enemyID, value: enemyDef.health))
    }

    private func emitLifecycleEvents(state: inout WorldState, context: SystemContext) {
        if !state.run.runStartedEmitted {
            state.run.runStartedEmitted = true
            context.emit(SimEvent(tick: state.tick, kind: .runStarted))
        }
    }

    private func nextWaveGapTicks(state: WorldState) -> UInt64 {
        let compression = UInt64(max(0, state.threat.waveIndex)) * state.threat.waveGapCompressionTicks
        let compressed = state.threat.waveGapBaseTicks > compression
            ? state.threat.waveGapBaseTicks - compression
            : 0
        return max(state.threat.waveGapFloorTicks, compressed)
    }

    private func groupsForWave(index: Int, state: inout WorldState) -> [EnemyGroup] {
        if let authored = handAuthoredByIndex[index] {
            return authored.composition
        }
        return proceduralGroups(forWave: index, state: &state)
    }

    private func proceduralGroups(forWave index: Int, state: inout WorldState) -> [EnemyGroup] {
        let difficultyID = DifficultyID(rawValue: state.run.difficulty.rawValue) ?? .normal
        let difficultyMultiplier = proceduralConfig.difficultyMultipliers.value(for: difficultyID)

        let formula = proceduralConfig.budgetFormula
        let rawBudget = Double(formula.base)
            + (Double(formula.linear) * Double(index))
            + floor(formula.quadratic * Double(index * index))
        let budget = max(1, Int(floor(rawBudget * difficultyMultiplier)))

        guard let swarmling = enemyDefsByID["swarmling"] else { return [] }
        var counts: [EnemyID: Int] = [:]
        let swarmlingReserve = max(0, Int(Double(budget) * proceduralConfig.swarmlingReserveRatio))
        counts[swarmling.id] = swarmlingReserve / max(1, swarmling.threatCost)

        var remaining = budget - (counts[swarmling.id, default: 0] * swarmling.threatCost)
        let candidates = enemyDefsByID.values
            .filter { $0.id != "artillery_bug" && $0.id != swarmling.id && $0.minBudgetToSpawn <= budget }
            .sorted { $0.id < $1.id }

        var guardCounter = 0
        while remaining > 0, guardCounter < 4_096 {
            guardCounter += 1
            let affordable = candidates.filter { $0.threatCost <= remaining }
            guard !affordable.isEmpty else { break }
            let picked = affordable[Int(nextRandom(modulus: UInt64(affordable.count), state: &state))]
            counts[picked.id, default: 0] += 1
            remaining -= picked.threatCost
        }

        if remaining > 0 {
            counts[swarmling.id, default: 0] += remaining / max(1, swarmling.threatCost)
        }

        let idsInOrder = counts.keys.sorted { lhs, rhs in
            if lhs == swarmling.id { return true }
            if rhs == swarmling.id { return false }
            return lhs < rhs
        }

        return idsInOrder.compactMap { enemyID in
            let count = counts[enemyID, default: 0]
            guard count > 0 else { return nil }
            return EnemyGroup(enemyID: enemyID, count: count, delayTicks: 0)
        }
    }

    private func makeSpawnClusters(state: inout WorldState) -> [SpawnCluster]? {
        let perimeter = state.board.spawnPositions()
        guard !perimeter.isEmpty else { return nil }

        let desiredCount = 2 + Int(nextRandom(modulus: 3, state: &state))
        let clusterCount = max(1, min(desiredCount, perimeter.count))
        let minimumSeparation = max(1, perimeter.count / 6)

        var pickedIndices: [Int] = []
        var attempts = 0
        while pickedIndices.count < clusterCount && attempts < perimeter.count * 8 {
            attempts += 1
            let idx = Int(nextRandom(modulus: UInt64(perimeter.count), state: &state))
            let isFarEnough = pickedIndices.allSatisfy { chosen in
                circularIndexDistance(lhs: idx, rhs: chosen, count: perimeter.count) >= minimumSeparation
            }
            if isFarEnough {
                pickedIndices.append(idx)
            }
        }

        if pickedIndices.count < clusterCount {
            pickedIndices = stride(from: 0, to: perimeter.count, by: max(1, perimeter.count / clusterCount)).map { $0 }
            pickedIndices = Array(pickedIndices.prefix(clusterCount))
        }

        return pickedIndices.enumerated().map { clusterID, index in
            let entry = perimeter[index]
            return SpawnCluster(
                id: clusterID,
                entryPoint: entry,
                spawnPoint: outsideSpawnPosition(for: entry, board: state.board),
                activationDelay: nextRandom(modulus: 41, state: &state)
            )
        }
    }

    private func circularIndexDistance(lhs: Int, rhs: Int, count: Int) -> Int {
        let direct = abs(lhs - rhs)
        return min(direct, max(0, count - direct))
    }

    private func randomPerimeterEntryPoint(state: inout WorldState) -> GridPosition? {
        let perimeter = state.board.spawnPositions()
        guard !perimeter.isEmpty else { return nil }
        let index = Int(nextRandom(modulus: UInt64(perimeter.count), state: &state))
        return perimeter[index]
    }

    private func outsideSpawnPosition(for entryPoint: GridPosition, board: BoardState) -> GridPosition {
        let centerX = board.width / 2
        let centerY = board.height / 2
        let dx = entryPoint.x - centerX
        let dy = entryPoint.y - centerY

        if abs(dx) >= abs(dy) {
            let x = dx >= 0 ? board.width + 1 : -2
            return GridPosition(x: x, y: entryPoint.y, z: entryPoint.z)
        }

        let y = dy >= 0 ? board.height + 1 : -2
        return GridPosition(x: entryPoint.x, y: y, z: entryPoint.z)
    }

    private func nextRandom(modulus: UInt64, state: inout WorldState) -> UInt64 {
        let value = state.threat.deterministicRandomState == 0
            ? (state.run.seed ^ 0x9E37_79B9_7F4A_7C15)
            : state.threat.deterministicRandomState
        state.threat.deterministicRandomState = value &* 6364136223846793005 &+ 1442695040888963407
        return state.threat.deterministicRandomState % max(1, modulus)
    }

    private func ticksPerMovement(speed: Float) -> UInt64 {
        let clampedSpeed = max(0.05, Double(speed))
        let ticks = (20.0 / clampedSpeed).rounded()
        return UInt64(max(1, Int(ticks)))
    }

    private func enemyArchetype(for enemyID: EnemyID) -> EnemyArchetype {
        switch enemyID {
        case "swarmling":
            return .swarmling
        case "drone_scout":
            return .droneScout
        case "raider":
            return .raider
        case "breacher":
            return .breacher
        case "overseer":
            return .overseer
        default:
            return .droneScout
        }
    }

    public static var defaultEnemyDefinitions: [EnemyDef] {
        if let loaded = CanonicalBootstrapContent.bundle?.enemies, !loaded.isEmpty {
            return loaded
        }
        return [
            EnemyDef(id: "swarmling", health: 10, speed: 1.8, threatCost: 1, baseDamage: 5),
            EnemyDef(id: "drone_scout", health: 20, speed: 1.4, threatCost: 2, baseDamage: 8),
            EnemyDef(id: "raider", health: 45, speed: 1.0, threatCost: 5, baseDamage: 12, behaviorModifier: .structureSeeker, minBudgetToSpawn: 20),
            EnemyDef(id: "breacher", health: 70, speed: 0.9, threatCost: 8, baseDamage: 15, behaviorModifier: .wallBreaker, wallDamageMultiplier: 2.0, minBudgetToSpawn: 30),
            EnemyDef(id: "overseer", health: 140, speed: 0.65, threatCost: 14, baseDamage: 10, behaviorModifier: .auraBuffer, minBudgetToSpawn: 60)
        ]
    }

    public static var defaultWaveContent: WaveContentDef {
        CanonicalBootstrapContent.bundle?.waveContent ?? WaveContentDef(handAuthoredWaves: [])
    }
}

public struct EnemyMovementSystem: SimulationSystem {
    private static let wallBreachDetourThreshold = 4

    public init() {}

    public func update(state: inout WorldState, context: SystemContext) {
        guard !state.combat.enemies.isEmpty else { return }

        let pathfinder = Pathfinder()
        let map = buildNavigationMap(state: state)
        let flowField = buildFlowField(on: map, goal: state.combat.basePosition)
        let sortedEnemyIDs = state.combat.enemies.keys.sorted()
        let occupiedBlockingStructures = blockingStructureOccupancy(state: state)

        for enemyID in sortedEnemyIDs {
            guard let runtime = state.combat.enemies[enemyID] else { continue }
            guard let enemy = state.entities.entity(id: enemyID) else {
                state.combat.enemies.removeValue(forKey: enemyID)
                continue
            }

            let auraBuffed = hasOverseerAura(for: enemyID, state: state)
            let effectiveMoveEvery = adjustedMoveEvery(runtime.moveEveryTicks, auraBuffed: auraBuffed)
            guard state.tick % max(1, effectiveMoveEvery) == 0 else { continue }

            if !state.board.contains(enemy.position), let entryPoint = runtime.entryPoint {
                let nextOutsideStep = stepToward(from: enemy.position, to: entryPoint)
                state.entities.updatePosition(enemyID, to: nextOutsideStep)
                if nextOutsideStep == entryPoint {
                    var updated = runtime
                    updated.entryPoint = nil
                    state.combat.enemies[enemyID] = updated
                }
                context.emit(SimEvent(tick: state.tick, kind: .enemyMoved, entity: enemyID))
                continue
            }

            if enemy.position == state.combat.basePosition {
                applyBaseHit(state: &state, context: context, enemyID: enemyID, damage: effectiveDamage(for: runtime, againstWall: false, auraBuffed: auraBuffed))
                continue
            }

            if runtime.behaviorModifier == .structureSeeker,
               let raiderTarget = nearestReachableRaiderTarget(enemy: enemy, map: map, pathfinder: pathfinder, state: state) {
                if isAdjacent(enemy.position, to: raiderTarget.position) {
                    attackStructure(targetID: raiderTarget.id, runtime: runtime, auraBuffed: auraBuffed, state: &state, context: context)
                    continue
                }
                if let approach = nextStepTowardStructure(enemy: enemy, structure: raiderTarget, map: map, pathfinder: pathfinder) {
                    state.entities.updatePosition(enemyID, to: approach.step)
                    context.emit(SimEvent(tick: state.tick, kind: .enemyMoved, entity: enemyID))
                    continue
                }
            }

            if let breachTarget = preferredWallBreachTarget(
                enemy: enemy,
                map: map,
                flowField: flowField,
                pathfinder: pathfinder,
                state: state
            ) {
                if let step = breachTarget.nextStep {
                    state.entities.updatePosition(enemyID, to: step)
                    context.emit(SimEvent(tick: state.tick, kind: .enemyMoved, entity: enemyID))
                } else {
                    attackStructure(
                        targetID: breachTarget.target.id,
                        runtime: runtime,
                        auraBuffed: auraBuffed,
                        state: &state,
                        context: context
                    )
                }
                continue
            }

            if let next = nextFlowStep(from: enemy.position, map: map, flowField: flowField) {
                state.entities.updatePosition(enemyID, to: next)
                context.emit(SimEvent(tick: state.tick, kind: .enemyMoved, entity: enemyID))

                if next == state.combat.basePosition {
                    applyBaseHit(
                        state: &state,
                        context: context,
                        enemyID: enemyID,
                        damage: effectiveDamage(for: runtime, againstWall: false, auraBuffed: auraBuffed)
                    )
                }
                continue
            }

            if let adjacentTarget = preferredAdjacentTarget(enemy: enemy, runtime: runtime, occupancy: occupiedBlockingStructures, state: state) {
                attackStructure(targetID: adjacentTarget.id, runtime: runtime, auraBuffed: auraBuffed, state: &state, context: context)
                continue
            }

            if let fallbackTarget = nearestReachableStructureTarget(
                enemy: enemy,
                map: map,
                pathfinder: pathfinder,
                state: state
            ) {
                if let step = fallbackTarget.nextStep {
                    state.entities.updatePosition(enemyID, to: step)
                    context.emit(SimEvent(tick: state.tick, kind: .enemyMoved, entity: enemyID))
                } else {
                    attackStructure(
                        targetID: fallbackTarget.target.id,
                        runtime: runtime,
                        auraBuffed: auraBuffed,
                        state: &state,
                        context: context
                    )
                }
            }
        }
    }

    private func buildNavigationMap(state: WorldState) -> GridMap {
        PlacementValidator().navigationMap(for: state)
    }

    private func blockingStructureOccupancy(state: WorldState) -> [GridPosition: EntityID] {
        var occupancy: [GridPosition: EntityID] = [:]
        let structures = state.entities.all.filter { $0.category == .structure }.sorted { $0.id < $1.id }
        for structure in structures {
            guard let structureType = structure.structureType else { continue }
            guard structureType.blocksMovement else { continue }
            for cell in structureType.coveredCells(anchor: structure.position) {
                let key = GridPosition(x: cell.x, y: cell.y, z: 0)
                if occupancy[key] == nil {
                    occupancy[key] = structure.id
                }
            }
        }
        return occupancy
    }

    private func buildFlowField(on map: GridMap, goal: GridPosition) -> [GridPosition: Int] {
        guard let goalTile = map.tile(at: goal), goalTile.walkable else { return [:] }

        var distances: [GridPosition: Int] = [goal: 0]
        var queue: [GridPosition] = [goal]
        var index = 0

        while index < queue.count {
            let current = queue[index]
            index += 1
            let nextDistance = distances[current, default: 0] + 1

            let neighbors = [
                current.translated(byX: 1),
                current.translated(byX: -1),
                current.translated(byY: 1),
                current.translated(byY: -1)
            ]

            for neighbor in neighbors {
                guard distances[neighbor] == nil else { continue }
                guard let tile = map.tile(at: neighbor), tile.walkable else { continue }
                distances[neighbor] = nextDistance
                queue.append(neighbor)
            }
        }

        return distances
    }

    private func nextFlowStep(from position: GridPosition, map: GridMap, flowField: [GridPosition: Int]) -> GridPosition? {
        let current = GridPosition(x: position.x, y: position.y, z: 0)
        let currentDistance = flowField[current]
        var candidates: [(position: GridPosition, distance: Int)] = []

        let neighbors = [
            current.translated(byX: 1),
            current.translated(byX: -1),
            current.translated(byY: 1),
            current.translated(byY: -1)
        ]

        for neighbor in neighbors {
            guard let tile = map.tile(at: neighbor), tile.walkable else { continue }
            guard let neighborDistance = flowField[neighbor] else { continue }
            if let currentDistance {
                guard neighborDistance < currentDistance else { continue }
            }
            candidates.append((neighbor, neighborDistance))
        }

        guard !candidates.isEmpty else { return nil }
        let best = candidates.min { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            if lhs.position.y != rhs.position.y { return lhs.position.y < rhs.position.y }
            return lhs.position.x < rhs.position.x
        }
        return best?.position
    }

    private func nearestReachableRaiderTarget(
        enemy: Entity,
        map: GridMap,
        pathfinder: Pathfinder,
        state: WorldState
    ) -> Entity? {
        let candidates = state.entities.all.filter { entity in
            guard entity.category == .structure else { return false }
            guard let type = entity.structureType else { return false }
            guard type != .wall else { return false }
            return enemy.position.manhattanDistance(to: entity.position) <= 4
        }

        var best: (entity: Entity, pathLength: Int)?
        for candidate in candidates {
            guard let approach = nextStepTowardStructure(enemy: enemy, structure: candidate, map: map, pathfinder: pathfinder, returnPathLength: true) else {
                continue
            }
            let pathLength = approach.pathLength
            if let current = best {
                if pathLength < current.pathLength || (pathLength == current.pathLength && candidate.id < current.entity.id) {
                    best = (candidate, pathLength)
                }
            } else {
                best = (candidate, pathLength)
            }
        }
        return best?.entity
    }

    private func preferredWallBreachTarget(
        enemy: Entity,
        map: GridMap,
        flowField: [GridPosition: Int],
        pathfinder: Pathfinder,
        state: WorldState
    ) -> (target: Entity, nextStep: GridPosition?)? {
        let current = GridPosition(x: enemy.position.x, y: enemy.position.y, z: 0)
        guard let distanceToBase = flowField[current] else { return nil }
        guard let wallTarget = nearestReachableWallTarget(enemy: enemy, map: map, pathfinder: pathfinder, state: state) else {
            return nil
        }

        let detourDelta = distanceToBase - wallTarget.pathLength
        guard detourDelta >= Self.wallBreachDetourThreshold else { return nil }
        return (target: wallTarget.target, nextStep: wallTarget.nextStep)
    }

    private func nearestReachableWallTarget(
        enemy: Entity,
        map: GridMap,
        pathfinder: Pathfinder,
        state: WorldState
    ) -> (target: Entity, nextStep: GridPosition?, pathLength: Int)? {
        let candidates = state.entities.all.filter { entity in
            entity.category == .structure && entity.structureType == .wall
        }

        var best: (entity: Entity, nextStep: GridPosition?, pathLength: Int, directDistance: Int)?

        for candidate in candidates {
            let directDistance = enemy.position.manhattanDistance(to: candidate.position)
            let score: (entity: Entity, nextStep: GridPosition?, pathLength: Int, directDistance: Int)?

            if isAdjacent(enemy.position, toStructure: candidate) {
                score = (candidate, nil, 0, directDistance)
            } else if let approach = nextStepTowardStructure(
                enemy: enemy,
                structure: candidate,
                map: map,
                pathfinder: pathfinder,
                returnPathLength: true
            ) {
                let pathLength = max(0, approach.pathLength - 1)
                score = (candidate, approach.step, pathLength, directDistance)
            } else {
                score = nil
            }

            guard let score else { continue }
            if let current = best {
                let isBetterPath = score.pathLength < current.pathLength
                let isBetterDistance = score.pathLength == current.pathLength
                    && score.directDistance < current.directDistance
                let isBetterTieBreak = score.pathLength == current.pathLength
                    && score.directDistance == current.directDistance
                    && score.entity.id < current.entity.id
                if isBetterPath || isBetterDistance || isBetterTieBreak {
                    best = score
                }
            } else {
                best = score
            }
        }

        guard let best else { return nil }
        return (best.entity, best.nextStep, best.pathLength)
    }

    private func nearestReachableStructureTarget(
        enemy: Entity,
        map: GridMap,
        pathfinder: Pathfinder,
        state: WorldState
    ) -> (target: Entity, nextStep: GridPosition?)? {
        let candidates = state.entities.all.filter { entity in
            entity.category == .structure && entity.structureType != nil
        }

        var best: (entity: Entity, nextStep: GridPosition?, pathLength: Int, directDistance: Int)?

        for candidate in candidates {
            let directDistance = enemy.position.manhattanDistance(to: candidate.position)
            let score: (entity: Entity, nextStep: GridPosition?, pathLength: Int, directDistance: Int)?

            if isAdjacent(enemy.position, toStructure: candidate) {
                score = (candidate, nil, 0, directDistance)
            } else if let approach = nextStepTowardStructure(
                enemy: enemy,
                structure: candidate,
                map: map,
                pathfinder: pathfinder,
                returnPathLength: true
            ) {
                score = (candidate, approach.step, approach.pathLength, directDistance)
            } else {
                score = nil
            }

            guard let score else { continue }
            if let current = best {
                let isBetterPath = score.pathLength < current.pathLength
                let isBetterDistance = score.pathLength == current.pathLength
                    && score.directDistance < current.directDistance
                let isBetterTieBreak = score.pathLength == current.pathLength
                    && score.directDistance == current.directDistance
                    && score.entity.id < current.entity.id
                if isBetterPath || isBetterDistance || isBetterTieBreak {
                    best = score
                }
            } else {
                best = score
            }
        }

        guard let best else { return nil }
        return (best.entity, best.nextStep)
    }

    private func nextStepTowardStructure(
        enemy: Entity,
        structure: Entity,
        map: GridMap,
        pathfinder: Pathfinder,
        returnPathLength: Bool = false
    ) -> (step: GridPosition, pathLength: Int)? {
        guard let structureType = structure.structureType else { return nil }

        var best: (step: GridPosition, pathLength: Int)?
        let footprintCells = structureType.coveredCells(anchor: structure.position)
        for footprintCell in footprintCells {
            let neighbors = [
                GridPosition(x: footprintCell.x + 1, y: footprintCell.y),
                GridPosition(x: footprintCell.x - 1, y: footprintCell.y),
                GridPosition(x: footprintCell.x, y: footprintCell.y + 1),
                GridPosition(x: footprintCell.x, y: footprintCell.y - 1)
            ]
            for neighbor in neighbors {
                guard let tile = map.tile(at: neighbor), tile.walkable else { continue }
                guard let path = pathfinder.findPath(on: map, from: enemy.position, to: neighbor), path.count > 1 else { continue }
                let candidate = (path[1], path.count)
                if let current = best {
                    if candidate.1 < current.pathLength {
                        best = candidate
                    }
                } else {
                    best = candidate
                }
            }
        }

        guard let best else { return nil }
        return returnPathLength ? best : (best.step, 0)
    }

    private func preferredAdjacentTarget(
        enemy: Entity,
        runtime: EnemyRuntime,
        occupancy: [GridPosition: EntityID],
        state: WorldState
    ) -> Entity? {
        let adjacentCells = [
            enemy.position.translated(byX: 1),
            enemy.position.translated(byX: -1),
            enemy.position.translated(byY: 1),
            enemy.position.translated(byY: -1)
        ]

        let adjacentStructures = adjacentCells.compactMap { cell -> Entity? in
            let key = GridPosition(x: cell.x, y: cell.y, z: 0)
            guard let structureID = occupancy[key] else { return nil }
            return state.entities.entity(id: structureID)
        }

        guard !adjacentStructures.isEmpty else { return nil }

        if runtime.behaviorModifier == .wallBreaker,
           let wall = adjacentStructures.first(where: { $0.structureType == .wall }) {
            return wall
        }

        return adjacentStructures.min { lhs, rhs in
            let lDist = enemy.position.manhattanDistance(to: lhs.position)
            let rDist = enemy.position.manhattanDistance(to: rhs.position)
            if lDist == rDist {
                return lhs.id < rhs.id
            }
            return lDist < rDist
        }
    }

    private func isAdjacent(_ lhs: GridPosition, to rhs: GridPosition) -> Bool {
        abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y) == 1
    }

    private func isAdjacent(_ position: GridPosition, toStructure structure: Entity) -> Bool {
        guard let structureType = structure.structureType else { return false }
        return structureType.coveredCells(anchor: structure.position).contains { cell in
            abs(position.x - cell.x) + abs(position.y - cell.y) == 1
        }
    }

    private func hasOverseerAura(for enemyID: EntityID, state: WorldState) -> Bool {
        guard let enemy = state.entities.entity(id: enemyID) else { return false }
        return state.combat.enemies.values.contains { runtime in
            guard runtime.id != enemyID else { return false }
            guard runtime.behaviorModifier == .auraBuffer else { return false }
            guard let source = state.entities.entity(id: runtime.id) else { return false }
            return source.position.manhattanDistance(to: enemy.position) <= 4
        }
    }

    private func adjustedMoveEvery(_ moveEveryTicks: UInt64, auraBuffed: Bool) -> UInt64 {
        guard auraBuffed else { return max(1, moveEveryTicks) }
        let adjusted = Double(max(1, moveEveryTicks)) / 1.15
        return UInt64(max(1, Int(adjusted.rounded(.down))))
    }

    private func effectiveDamage(for runtime: EnemyRuntime, againstWall: Bool, auraBuffed: Bool) -> Int {
        var base = Double(max(1, runtime.baseDamage))
        if againstWall {
            base *= runtime.wallDamageMultiplier
        }
        if auraBuffed {
            base *= 1.25
        }
        return max(1, Int(base.rounded(.toNearestOrAwayFromZero)))
    }

    private func stepToward(from: GridPosition, to: GridPosition) -> GridPosition {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let stepX = dx == 0 ? 0 : (dx > 0 ? 1 : -1)
        let stepY = dy == 0 ? 0 : (dy > 0 ? 1 : -1)
        if abs(dx) >= abs(dy) {
            return from.translated(byX: stepX)
        }
        return from.translated(byY: stepY)
    }

    private func attackStructure(
        targetID: EntityID,
        runtime: EnemyRuntime,
        auraBuffed: Bool,
        state: inout WorldState,
        context: SystemContext
    ) {
        guard let target = state.entities.entity(id: targetID) else { return }
        let againstWall = target.structureType == .wall
        let damage = effectiveDamage(for: runtime, againstWall: againstWall, auraBuffed: auraBuffed)

        context.emit(SimEvent(tick: state.tick, kind: .structureDamaged, entity: targetID, value: damage))
        state.threat.telemetry.structureDamageEvents += 1

        state.entities.damage(targetID, amount: damage)
        let stillExists = state.entities.entity(id: targetID) != nil
        guard !stillExists else { return }

        context.emit(SimEvent(tick: state.tick, kind: .structureDestroyed, entity: targetID, value: damage))
        if target.structureType == .wall {
            destroyMountedTurrets(onWallID: targetID, state: &state)
            state.combat.wallNetworksDirty = true
        }

        if state.run.hqEntityID == targetID {
            state.run.phase = .gameOver
            if !state.run.gameOverEmitted {
                state.run.gameOverEmitted = true
                context.emit(SimEvent(tick: state.tick, kind: .gameOver, value: Int(min(state.tick, UInt64(Int.max)))))
            }
        }
    }

    private func destroyMountedTurrets(onWallID wallID: EntityID, state: inout WorldState) {
        let mountedTurrets = state.entities.structures(of: .turretMount).filter { $0.hostWallID == wallID }
        for turret in mountedTurrets {
            state.entities.remove(turret.id)
            state.combat.lastFireTickByTurret.removeValue(forKey: turret.id)
            state.economy.structureInputBuffers.removeValue(forKey: turret.id)
            state.economy.structureOutputBuffers.removeValue(forKey: turret.id)
        }
    }

    private func applyBaseHit(state: inout WorldState, context: SystemContext, enemyID: EntityID, damage: Int) {
        context.emit(SimEvent(tick: state.tick, kind: .enemyReachedBase, entity: enemyID, value: damage))
        state.entities.remove(enemyID)
        state.combat.enemies.removeValue(forKey: enemyID)

        guard let hqID = state.run.hqEntityID else { return }
        state.entities.damage(hqID, amount: max(1, damage))
        let hqHealth = state.entities.entity(id: hqID)?.health ?? 0
        if hqHealth == 0 {
            state.run.phase = .gameOver
            if !state.run.gameOverEmitted {
                state.run.gameOverEmitted = true
                context.emit(SimEvent(tick: state.tick, kind: .gameOver, value: Int(min(state.tick, UInt64(Int.max)))))
            }
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

            if consumeAmmo(for: turret.id, itemID: ammoItemID, state: &state) {
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
            state.threat.telemetry.dryFireEvents += dryFires
            context.emit(SimEvent(tick: state.tick, kind: .notEnoughAmmo, value: dryFires, itemID: itemID))
        }
    }

    private func consumeAmmo(for turretID: EntityID, itemID: ItemID, state: inout WorldState) -> Bool {
        if let turret = state.entities.entity(id: turretID),
           let hostWallID = turret.hostWallID {
            guard let networkID = state.combat.wallNetworkByWallEntityID[hostWallID],
                  var network = state.combat.wallNetworks[networkID] else {
                return false
            }

            let available = network.ammoPoolByItemID[itemID, default: 0]
            guard available > 0 else { return false }

            network.ammoPoolByItemID[itemID] = available - 1
            state.combat.wallNetworks[networkID] = network
            return true
        }

        if var localBuffer = state.economy.structureInputBuffers[turretID],
           let localAmmo = localBuffer[itemID],
           localAmmo > 0 {
            if localAmmo == 1 {
                localBuffer.removeValue(forKey: itemID)
            } else {
                localBuffer[itemID] = localAmmo - 1
            }
            state.economy.structureInputBuffers[turretID] = localBuffer
            return true
        }

        return false
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
