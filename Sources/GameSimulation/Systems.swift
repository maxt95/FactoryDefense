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
                            value: result.rawValue
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
                                value: PlacementResult.invalidMinerPlacement.rawValue
                            )
                        )
                        continue
                    }
                } else {
                    targetPatchID = nil
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
                let structureID = state.entities.spawnStructure(
                    request.structure,
                    at: placementPosition,
                    boundPatchID: targetPatchID
                )
                if let targetPatchID {
                    bindMiner(structureID, toPatchID: targetPatchID, state: &state)
                }
                context.emit(
                    SimEvent(
                        tick: state.tick,
                        kind: .structurePlaced,
                        entity: structureID
                    )
                )
            case .extract:
                // Extraction is deferred for v1; command retained for snapshot compatibility.
                continue
            case .triggerWave:
                state.threat.nextWaveTick = state.tick
            }
        }
    }

    private func bindMiner(_ minerID: EntityID, toPatchID patchID: Int, state: inout WorldState) {
        guard let patchIndex = state.orePatches.firstIndex(where: { $0.id == patchID }) else { return }
        state.orePatches[patchIndex].boundMinerID = minerID
        state.entities.updateBoundPatchID(minerID, to: patchID)
    }
}

public struct EconomySystem: SimulationSystem {
    private let recipesByID: [String: RecipeDef]
    private let minimumConstructionStock: [ItemID: Int]
    private let reserveProtectedRecipeIDs: Set<String>
    private let conveyorTicksPerTile: Int

    public init(
        recipes: [RecipeDef] = EconomySystem.defaultRecipes,
        minimumConstructionStock: [ItemID: Int] = EconomySystem.defaultMinimumConstructionStock,
        reserveProtectedRecipeIDs: Set<String> = EconomySystem.defaultReserveProtectedRecipeIDs,
        conveyorTicksPerTile: Int = 5
    ) {
        self.recipesByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        self.minimumConstructionStock = minimumConstructionStock
        self.reserveProtectedRecipeIDs = reserveProtectedRecipeIDs
        self.conveyorTicksPerTile = max(1, conveyorTicksPerTile)
    }

    public func update(state: inout WorldState, context: SystemContext) {
        let structures = state.entities.all.filter { $0.category == .structure }
        syncLogisticsRuntime(structures: structures, state: &state)
        syncOrePatchBindings(state: &state)

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
        pruneRuntimeState(for: structures, state: &state)

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
        let inventory = combinedInventory(for: structureID, state: state)
        for recipeID in prioritizedRecipeIDs {
            guard let recipe = recipesByID[recipeID] else { continue }
            guard recipe.inputs.allSatisfy({ inventory[$0.itemID, default: 0] >= $0.quantity }) else { continue }
            guard canRunRecipeWithoutBreachingConstructionStock(recipe: recipe, inventory: state.economy.inventories) else { continue }
            return recipe
        }
        return nil
    }

    private func combinedInventory(for structureID: EntityID, state: WorldState) -> [ItemID: Int] {
        var combined = state.economy.inventories
        for (itemID, quantity) in state.economy.structureInputBuffers[structureID, default: [:]] where quantity > 0 {
            combined[itemID, default: 0] += quantity
        }
        return combined
    }

    private func canAffordRecipeInputs(_ inputs: [ItemStack], structureID: EntityID, state: WorldState) -> Bool {
        let localBuffer = state.economy.structureInputBuffers[structureID, default: [:]]
        for input in inputs {
            let local = localBuffer[input.itemID, default: 0]
            let global = state.economy.inventories[input.itemID, default: 0]
            if local + global < input.quantity {
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
            var remaining = input.quantity
            let localAvailable = localBuffer[input.itemID, default: 0]
            if localAvailable > 0 {
                let localConsumption = min(localAvailable, remaining)
                localBuffer[input.itemID] = localAvailable - localConsumption
                if localBuffer[input.itemID] == 0 {
                    localBuffer.removeValue(forKey: input.itemID)
                }
                remaining -= localConsumption
            }

            if remaining > 0 {
                _ = state.economy.consume(itemID: input.itemID, quantity: remaining)
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
            if inputBufferCapacity(for: structureType) > 0 {
                _ = state.economy.structureInputBuffers[structureID, default: [:]]
            } else {
                state.economy.structureInputBuffers.removeValue(forKey: structureID)
            }

            if outputBufferCapacity(for: structureType) > 0 {
                _ = state.economy.structureOutputBuffers[structureID, default: [:]]
            } else {
                state.economy.structureOutputBuffers.removeValue(forKey: structureID)
            }

            if structureType != .conveyor {
                state.economy.conveyorPayloadByEntity.removeValue(forKey: structureID)
            }
        }

        let validStructureIDs = Set(structureTypesByID.keys)
        state.economy.structureInputBuffers = state.economy.structureInputBuffers.filter { validStructureIDs.contains($0.key) }
        state.economy.structureOutputBuffers = state.economy.structureOutputBuffers.filter { validStructureIDs.contains($0.key) }
        state.economy.conveyorPayloadByEntity = state.economy.conveyorPayloadByEntity.filter {
            structureTypesByID[$0.key] == .conveyor
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
        let conveyors = structures
            .filter { $0.structureType == .conveyor }
            .sorted { lhs, rhs in
                if lhs.position.x != rhs.position.x { return lhs.position.x > rhs.position.x }
                if lhs.position.y != rhs.position.y { return lhs.position.y < rhs.position.y }
                return lhs.id < rhs.id
            }

        guard !conveyors.isEmpty else { return }

        var conveyorsByPosition: [GridPosition: EntityID] = [:]
        for conveyor in conveyors {
            if conveyorsByPosition[conveyor.position] == nil {
                conveyorsByPosition[conveyor.position] = conveyor.id
            }
        }

        var structuresByPosition: [GridPosition: Entity] = [:]
        for structure in structures.sorted(by: { $0.id < $1.id }) {
            if structuresByPosition[structure.position] == nil {
                structuresByPosition[structure.position] = structure
            }
        }

        for conveyor in conveyors {
            guard var payload = state.economy.conveyorPayloadByEntity[conveyor.id] else { continue }
            payload.progressTicks = min(conveyorTicksPerTile, payload.progressTicks + 1)
            state.economy.conveyorPayloadByEntity[conveyor.id] = payload
        }

        for conveyor in conveyors {
            guard let payload = state.economy.conveyorPayloadByEntity[conveyor.id] else { continue }
            guard payload.progressTicks >= conveyorTicksPerTile else { continue }

            let targetPosition = conveyor.position.translated(byX: 1)

            if let targetConveyorID = conveyorsByPosition[targetPosition],
               state.economy.conveyorPayloadByEntity[targetConveyorID] == nil {
                state.economy.conveyorPayloadByEntity[targetConveyorID] = ConveyorPayload(itemID: payload.itemID, progressTicks: 0)
                state.economy.conveyorPayloadByEntity.removeValue(forKey: conveyor.id)
                continue
            }

            if let targetStructure = structuresByPosition[targetPosition],
               let targetType = targetStructure.structureType,
               enqueueInputItem(itemID: payload.itemID, structureID: targetStructure.id, structureType: targetType, state: &state) {
                state.economy.conveyorPayloadByEntity.removeValue(forKey: conveyor.id)
            }
        }
    }

    private func drainStructureOutputBuffers(structures: [Entity], state: inout WorldState) {
        var conveyorsByPosition: [GridPosition: EntityID] = [:]
        var structuresByPosition: [GridPosition: Entity] = [:]
        for structure in structures.sorted(by: { $0.id < $1.id }) {
            if structuresByPosition[structure.position] == nil {
                structuresByPosition[structure.position] = structure
            }
            if structure.structureType == .conveyor, conveyorsByPosition[structure.position] == nil {
                conveyorsByPosition[structure.position] = structure.id
            }
        }

        for structure in structures.sorted(by: { $0.id < $1.id }) {
            guard let structureType = structure.structureType else { continue }
            guard outputBufferCapacity(for: structureType) > 0 else { continue }
            guard !(state.economy.structureOutputBuffers[structure.id, default: [:]].isEmpty) else { continue }

            let outputTarget = structure.position.translated(byX: 1)

            if let conveyorID = conveyorsByPosition[outputTarget] {
                guard state.economy.conveyorPayloadByEntity[conveyorID] == nil else { continue }
                guard let itemID = popFirstOutputItem(structureID: structure.id, state: &state) else { continue }
                state.economy.conveyorPayloadByEntity[conveyorID] = ConveyorPayload(itemID: itemID, progressTicks: 0)
                continue
            }

            if let targetStructure = structuresByPosition[outputTarget],
               let targetType = targetStructure.structureType,
               let itemID = popFirstOutputItem(structureID: structure.id, state: &state) {
                if enqueueInputItem(itemID: itemID, structureID: targetStructure.id, structureType: targetType, state: &state) {
                    continue
                }

                var outputBuffer = state.economy.structureOutputBuffers[structure.id, default: [:]]
                outputBuffer[itemID, default: 0] += 1
                state.economy.structureOutputBuffers[structure.id] = outputBuffer
                continue
            }

            flushAllOutputToGlobalInventory(structureID: structure.id, state: &state)
        }
    }

    private func flushAllOutputToGlobalInventory(structureID: EntityID, state: inout WorldState) {
        let outputBuffer = state.economy.structureOutputBuffers[structureID, default: [:]]
        guard !outputBuffer.isEmpty else { return }

        for itemID in outputBuffer.keys.sorted() {
            let quantity = outputBuffer[itemID, default: 0]
            if quantity > 0 {
                state.economy.add(itemID: itemID, quantity: quantity)
            }
        }
        state.economy.structureOutputBuffers[structureID] = [:]
    }

    private func popFirstOutputItem(structureID: EntityID, state: inout WorldState) -> ItemID? {
        var outputBuffer = state.economy.structureOutputBuffers[structureID, default: [:]]
        guard let itemID = outputBuffer.keys.sorted().first else { return nil }
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

    @discardableResult
    private func enqueueInputItem(
        itemID: ItemID,
        structureID: EntityID,
        structureType: StructureType,
        state: inout WorldState
    ) -> Bool {
        let capacity = inputBufferCapacity(for: structureType)
        guard capacity > 0 else { return false }
        guard acceptsInput(itemID: itemID, structureType: structureType) else { return false }

        var inputBuffer = state.economy.structureInputBuffers[structureID, default: [:]]
        let current = inputBuffer.values.reduce(0, +)
        guard current < capacity else { return false }

        inputBuffer[itemID, default: 0] += 1
        state.economy.structureInputBuffers[structureID] = inputBuffer
        return true
    }

    private func acceptsInput(itemID: ItemID, structureType: StructureType) -> Bool {
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
        state.economy.productionProgressByStructure = state.economy.productionProgressByStructure.filter { validStructureIDs.contains($0.key) }
        state.economy.structureInputBuffers = state.economy.structureInputBuffers.filter { validStructureIDs.contains($0.key) }
        state.economy.structureOutputBuffers = state.economy.structureOutputBuffers.filter { validStructureIDs.contains($0.key) }
        state.economy.conveyorPayloadByEntity = state.economy.conveyorPayloadByEntity.filter { validStructureIDs.contains($0.key) }
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

        if state.tick >= state.threat.nextTrickleTick {
            spawnTrickleEnemies(state: &state, context: context)
            state.threat.nextTrickleTick = state.tick + state.threat.trickleIntervalTicks
        }

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
            state.threat.nextWaveTick = state.tick + nextWaveGapTicks(state: state)
            context.emit(SimEvent(tick: state.tick, kind: .waveEnded, value: state.threat.waveIndex))

            if state.threat.waveIndex % state.threat.milestoneEvery == 0,
               state.threat.waveIndex != state.threat.lastMilestoneWave {
                state.threat.lastMilestoneWave = state.threat.waveIndex
                let milestoneReward = state.threat.waveIndex * 10
                state.economy.currency += milestoneReward
                context.emit(SimEvent(tick: state.tick, kind: .milestoneReached, value: state.threat.waveIndex))
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
            let damage = isRaider ? 12 : 8
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

    private func spawnTrickleEnemies(state: inout WorldState, context: SystemContext) {
        let minCount = max(1, state.threat.trickleMinCount)
        let maxCount = max(minCount, state.threat.trickleMaxCount)
        let span = maxCount - minCount + 1
        let count = minCount + deterministicRoll(tick: state.tick, wave: state.threat.waveIndex, modulus: UInt64(span))

        for offset in 0..<count {
            let roll = deterministicRoll(
                tick: state.tick + UInt64(offset),
                wave: state.threat.waveIndex + offset,
                modulus: 4
            )
            let spawnRaiderOnHard = state.run.difficulty == .hard && roll == 0
            let archetype: EnemyArchetype = spawnRaiderOnHard ? .raider : .scout
            let health = spawnRaiderOnHard ? 45 : 20
            let moveEveryTicks: UInt64 = spawnRaiderOnHard ? 6 : 8
            let damage = spawnRaiderOnHard ? 12 : 8
            let reward = spawnRaiderOnHard ? 3 : 1

            spawnEnemy(
                state: &state,
                context: context,
                wave: state.threat.waveIndex,
                index: offset + 100,
                archetype: archetype,
                health: health,
                moveEveryTicks: moveEveryTicks,
                baseDamage: damage,
                rewardCurrency: reward
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

    private func deterministicRoll(tick: UInt64, wave: Int, modulus: UInt64) -> Int {
        let seed = tick &* 1_103_515_245 &+ UInt64(max(0, wave) &* 12_345) &+ 0x9E3779B97F4A7C15
        return Int(seed % max(1, modulus))
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
            context.emit(SimEvent(tick: state.tick, kind: .notEnoughAmmo, value: dryFires, itemID: itemID))
        }
    }

    private func consumeAmmo(for turretID: EntityID, itemID: ItemID, state: inout WorldState) -> Bool {
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

        return state.economy.consume(itemID: itemID, quantity: 1)
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
