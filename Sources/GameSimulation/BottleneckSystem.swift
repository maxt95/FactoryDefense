import Foundation
import GameContent

public struct BottleneckSystem: SimulationSystem {
    public let activationThresholdTicks: UInt64
    public let recoveryThresholdTicks: UInt64
    public let dryFireRateThreshold: Int
    public let spawnBacklogThreshold: Int
    public let wallNetworkAmmoWarningRatio: Double
    public let conveyorTicksPerTile: Int
    public let outputBufferCapacities: [StructureType: Int]

    public init(
        activationThresholdTicks: UInt64 = 6,
        recoveryThresholdTicks: UInt64 = 20,
        dryFireRateThreshold: Int = 1,
        spawnBacklogThreshold: Int = 10,
        wallNetworkAmmoWarningRatio: Double = 0.25,
        conveyorTicksPerTile: Int = 5,
        outputBufferCapacities: [StructureType: Int] = [
            .miner: 8,
            .smelter: 4,
            .assembler: 4,
            .ammoModule: 8,
            .storage: 24
        ]
    ) {
        self.activationThresholdTicks = activationThresholdTicks
        self.recoveryThresholdTicks = recoveryThresholdTicks
        self.dryFireRateThreshold = dryFireRateThreshold
        self.spawnBacklogThreshold = spawnBacklogThreshold
        self.wallNetworkAmmoWarningRatio = wallNetworkAmmoWarningRatio
        self.conveyorTicksPerTile = max(1, conveyorTicksPerTile)
        self.outputBufferCapacities = outputBufferCapacities
    }

    public func update(state: inout WorldState, context: SystemContext) {
        let tick = state.tick
        var rawConditions: [BottleneckSignalKey: RawCondition] = [:]

        detectAmmoDryFire(state: state, into: &rawConditions)
        detectInputStarved(state: state, into: &rawConditions)
        detectOutputBlocked(state: state, into: &rawConditions)
        detectPowerShortage(state: state, into: &rawConditions)
        detectMinerNoOre(state: state, into: &rawConditions)
        detectConveyorStall(state: state, into: &rawConditions)
        detectWallNetworkUnderfed(state: state, into: &rawConditions)
        detectSurgeBacklogHigh(state: state, into: &rawConditions)

        // Track dry fire delta for next tick
        state.bottleneck.previousDryFireEvents = state.threat.telemetry.dryFireEvents

        // Collect all keys that have hysteresis entries or raw conditions
        var allKeys = Set(rawConditions.keys)
        for key in state.bottleneck.hysteresis.keys {
            allKeys.insert(key)
        }

        var activatedSignals: [BottleneckSignal] = []
        var deactivatedKeys: [BottleneckSignalKey] = []
        var keysToRemove: [BottleneckSignalKey] = []

        for key in allKeys.sorted(by: { $0.kind.priority < $1.kind.priority }) {
            var hyst = state.bottleneck.hysteresis[key] ?? BottleneckSignalHysteresis()

            if let condition = rawConditions[key] {
                hyst.conditionMetTickCount += 1
                hyst.conditionClearedTickCount = 0

                if !hyst.isActive && hyst.conditionMetTickCount >= activationThresholdTicks {
                    hyst.isActive = true
                    let signal = BottleneckSignal(
                        kind: key.kind,
                        scope: key.scope,
                        severity: condition.severity,
                        firstTick: tick,
                        lastTick: tick,
                        entityID: condition.entityID,
                        networkID: condition.networkID,
                        itemID: condition.itemID,
                        detail: condition.detail
                    )
                    activatedSignals.append(signal)
                    state.bottleneck.telemetry.signalTransitionsByKind[key.kind, default: 0] += 1
                    context.emit(SimEvent(
                        tick: tick,
                        kind: .bottleneckActivated,
                        entity: condition.entityID,
                        itemID: condition.itemID,
                        reasonDetail: key.kind.rawValue
                    ))
                }
            } else {
                hyst.conditionClearedTickCount += 1
                hyst.conditionMetTickCount = 0

                if hyst.isActive && hyst.conditionClearedTickCount >= recoveryThresholdTicks {
                    hyst.isActive = false
                    deactivatedKeys.append(key)
                    state.bottleneck.telemetry.signalTransitionsByKind[key.kind, default: 0] += 1
                    context.emit(SimEvent(
                        tick: tick,
                        kind: .bottleneckDeactivated,
                        reasonDetail: key.kind.rawValue
                    ))
                }

                if !hyst.isActive && hyst.conditionClearedTickCount > recoveryThresholdTicks {
                    keysToRemove.append(key)
                }
            }

            state.bottleneck.hysteresis[key] = hyst
        }

        for key in keysToRemove {
            state.bottleneck.hysteresis.removeValue(forKey: key)
        }

        // Rebuild active signals list
        var newActiveSignals: [BottleneckSignal] = []

        // Keep existing active signals that weren't deactivated, updating lastTick
        let deactivatedSet = Set(deactivatedKeys)
        for var signal in state.bottleneck.activeSignals {
            let key = BottleneckSignalKey(kind: signal.kind, scope: signal.scope)
            if !deactivatedSet.contains(key) {
                if let hyst = state.bottleneck.hysteresis[key], hyst.isActive {
                    signal.lastTick = tick
                    // Update severity from raw condition if present
                    if let condition = rawConditions[key] {
                        signal.severity = condition.severity
                        signal.detail = condition.detail
                    }
                    newActiveSignals.append(signal)
                }
            }
        }

        // Add newly activated signals
        for signal in activatedSignals {
            let key = BottleneckSignalKey(kind: signal.kind, scope: signal.scope)
            if !newActiveSignals.contains(where: { $0.kind == key.kind && $0.scope == key.scope }) {
                newActiveSignals.append(signal)
            }
        }

        // Sort by priority
        newActiveSignals.sort { $0.kind.priority < $1.kind.priority }
        state.bottleneck.activeSignals = newActiveSignals

        // Update telemetry
        for signal in newActiveSignals {
            state.bottleneck.telemetry.signalActiveTicksByKind[signal.kind, default: 0] += 1
        }
        state.bottleneck.telemetry.maxConcurrentSignals = max(
            state.bottleneck.telemetry.maxConcurrentSignals,
            newActiveSignals.count
        )

        // Prune hysteresis for deleted entities
        pruneDeletedEntities(state: &state)
    }

    // MARK: - Detection Methods

    private func detectAmmoDryFire(state: WorldState, into conditions: inout [BottleneckSignalKey: RawCondition]) {
        guard state.threat.isWaveActive else { return }
        let delta = state.threat.telemetry.dryFireEvents - state.bottleneck.previousDryFireEvents
        guard delta >= dryFireRateThreshold else { return }

        let key = BottleneckSignalKey(kind: .ammoDryFire, scope: .global)
        let severity: BottleneckSignalSeverity = delta > dryFireRateThreshold ? .critical : .warn
        conditions[key] = RawCondition(
            severity: severity,
            detail: "\(delta) dry fires this tick"
        )
    }

    private func detectInputStarved(state: WorldState, into conditions: inout [BottleneckSignalKey: RawCondition]) {
        for (entityID, pinnedRecipeID) in state.economy.pinnedRecipeByStructure {
            guard state.economy.activeRecipeByStructure[entityID] == nil else { continue }
            guard let entity = state.entities.entity(id: entityID),
                  let structureType = entity.structureType else { continue }

            let key = BottleneckSignalKey(kind: .inputStarved, scope: .structure(entityID))
            let severity: BottleneckSignalSeverity =
                (structureType == .ammoModule && state.threat.isWaveActive) ? .critical : .warn
            conditions[key] = RawCondition(
                severity: severity,
                entityID: entityID,
                itemID: pinnedRecipeID,
                detail: "\(humanizedLabel(pinnedRecipeID)) missing inputs"
            )
        }
    }

    private func detectOutputBlocked(state: WorldState, into conditions: inout [BottleneckSignalKey: RawCondition]) {
        for (entityID, buffer) in state.economy.structureOutputBuffers {
            guard let entity = state.entities.entity(id: entityID),
                  let structureType = entity.structureType else { continue }
            let capacity = outputBufferCapacities[structureType, default: 0]
            guard capacity > 0 else { continue }

            let totalItems = buffer.values.reduce(0, +)
            guard totalItems >= capacity else { continue }

            // Only flag if the structure has work to do (pinned or active recipe, or is a miner)
            let hasWork = state.economy.pinnedRecipeByStructure[entityID] != nil
                || state.economy.activeRecipeByStructure[entityID] != nil
                || structureType == .miner
            guard hasWork else { continue }

            let key = BottleneckSignalKey(kind: .outputBlocked, scope: .structure(entityID))
            conditions[key] = RawCondition(
                severity: .warn,
                entityID: entityID,
                detail: "Output buffer \(totalItems)/\(capacity)"
            )
        }
    }

    private func detectPowerShortage(state: WorldState, into conditions: inout [BottleneckSignalKey: RawCondition]) {
        guard state.economy.powerDemand > state.economy.powerAvailable else { return }

        let deficit = state.economy.powerDemand - state.economy.powerAvailable
        let deficitRatio = state.economy.powerDemand > 0
            ? Double(deficit) / Double(state.economy.powerDemand)
            : 0
        let key = BottleneckSignalKey(kind: .powerShortage, scope: .global)
        let severity: BottleneckSignalSeverity = deficitRatio > 0.5 ? .critical : .warn
        conditions[key] = RawCondition(
            severity: severity,
            detail: "Demand \(state.economy.powerDemand) > Available \(state.economy.powerAvailable)"
        )
    }

    private func detectMinerNoOre(state: WorldState, into conditions: inout [BottleneckSignalKey: RawCondition]) {
        let miners = state.entities.structures(of: .miner)
        for miner in miners {
            let hasOre: Bool
            if let patchID = miner.boundPatchID {
                hasOre = state.orePatches.first(where: { $0.id == patchID })?.isExhausted == false
            } else {
                hasOre = false
            }

            guard !hasOre else { continue }

            let key = BottleneckSignalKey(kind: .minerNoOre, scope: .structure(miner.id))
            conditions[key] = RawCondition(
                severity: .warn,
                entityID: miner.id,
                detail: miner.boundPatchID == nil ? "No ore patch bound" : "Ore patch exhausted"
            )
        }
    }

    private func detectConveyorStall(state: WorldState, into conditions: inout [BottleneckSignalKey: RawCondition]) {
        for (entityID, payload) in state.economy.conveyorPayloadByEntity {
            guard payload.progressTicks >= conveyorTicksPerTile else { continue }

            let key = BottleneckSignalKey(kind: .conveyorStall, scope: .structure(entityID))
            conditions[key] = RawCondition(
                severity: .info,
                entityID: entityID,
                itemID: payload.itemID,
                detail: "\(humanizedLabel(payload.itemID)) stalled at \(payload.progressTicks) ticks"
            )
        }
    }

    private func detectWallNetworkUnderfed(state: WorldState, into conditions: inout [BottleneckSignalKey: RawCondition]) {
        for (networkID, network) in state.combat.wallNetworks {
            guard network.capacity > 0 else { continue }
            // Only flag networks that have turrets (walls with turret mounts)
            let hasTurrets = network.wallEntityIDs.contains { wallID in
                state.entities.structures(of: .turretMount).contains { $0.hostWallID == wallID }
            }
            guard hasTurrets else { continue }

            let totalAmmo = network.ammoPoolByItemID.values.reduce(0, +)
            let ratio = Double(totalAmmo) / Double(network.capacity)
            guard ratio <= wallNetworkAmmoWarningRatio else { continue }

            let key = BottleneckSignalKey(kind: .wallNetworkUnderfed, scope: .network(networkID))
            let severity: BottleneckSignalSeverity =
                (totalAmmo == 0 && state.threat.isWaveActive) ? .critical : .warn
            conditions[key] = RawCondition(
                severity: severity,
                networkID: networkID,
                detail: "Ammo \(totalAmmo)/\(network.capacity)"
            )
        }
    }

    private func detectSurgeBacklogHigh(state: WorldState, into conditions: inout [BottleneckSignalKey: RawCondition]) {
        guard state.threat.isWaveActive else { return }
        let backlog = state.threat.telemetry.queuedSpawnBacklog
        guard backlog > spawnBacklogThreshold else { return }

        let key = BottleneckSignalKey(kind: .surgeBacklogHigh, scope: .global)
        let severity: BottleneckSignalSeverity = backlog > spawnBacklogThreshold * 2 ? .critical : .warn
        conditions[key] = RawCondition(
            severity: severity,
            detail: "\(backlog) enemies queued"
        )
    }

    // MARK: - Helpers

    private func pruneDeletedEntities(state: inout WorldState) {
        let keysToRemove = state.bottleneck.hysteresis.keys.filter { key in
            switch key.scope {
            case .structure(let entityID):
                return state.entities.entity(id: entityID) == nil
            case .network(let networkID):
                return state.combat.wallNetworks[networkID] == nil
            case .global:
                return false
            }
        }
        for key in keysToRemove {
            state.bottleneck.hysteresis.removeValue(forKey: key)
        }
        state.bottleneck.activeSignals.removeAll { signal in
            let key = BottleneckSignalKey(kind: signal.kind, scope: signal.scope)
            return keysToRemove.contains(key)
        }
    }

    private func humanizedLabel(_ value: String) -> String {
        value
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

// Internal type for collecting raw detection results before hysteresis
private struct RawCondition {
    var severity: BottleneckSignalSeverity
    var entityID: EntityID?
    var networkID: Int?
    var itemID: ItemID?
    var detail: String?

    init(
        severity: BottleneckSignalSeverity,
        entityID: EntityID? = nil,
        networkID: Int? = nil,
        itemID: ItemID? = nil,
        detail: String? = nil
    ) {
        self.severity = severity
        self.entityID = entityID
        self.networkID = networkID
        self.itemID = itemID
        self.detail = detail
    }
}
