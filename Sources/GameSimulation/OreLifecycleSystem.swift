import Foundation
import GameContent

public struct OreLifecycleSystem: SimulationSystem {
    private let config: OrePatchesConfigDef

    public init(config: OrePatchesConfigDef? = nil) {
        self.config = config ?? (CanonicalBootstrapContent.bundle?.orePatches ?? .v1Default)
    }

    public func update(state: inout WorldState, context: SystemContext) {
        enqueueExhaustedPatches(state: &state)
        completeSurveys(state: &state, context: context)
        processRenewalsAtGapBoundary(state: &state, context: context)
    }

    private func enqueueExhaustedPatches(state: inout WorldState) {
        let sortedPatchIndices = state.orePatches.indices.sorted {
            state.orePatches[$0].id < state.orePatches[$1].id
        }
        var queuedPatchIDs = Set(state.oreLifecycle.renewalQueue.map(\.sourcePatchID))

        for patchIndex in sortedPatchIndices {
            var patch = state.orePatches[patchIndex]
            guard patch.isExhausted, !patch.renewalProcessed else { continue }

            let exhaustedAtTick = patch.exhaustedAtTick ?? state.tick
            patch.exhaustedAtTick = exhaustedAtTick
            patch.renewalProcessed = true
            state.orePatches[patchIndex] = patch

            if !queuedPatchIDs.contains(patch.id) {
                state.oreLifecycle.renewalQueue.append(
                    RenewalRequest(
                        sourcePatchID: patch.id,
                        oreType: patch.oreType,
                        exhaustedAtTick: exhaustedAtTick
                    )
                )
                queuedPatchIDs.insert(patch.id)
            }
        }
    }

    private func completeSurveys(state: inout WorldState, context: SystemContext) {
        let completedRings = state.oreLifecycle.surveyEndTickByRing
            .filter { $0.value <= state.tick }
            .map(\.key)
            .sorted()

        guard !completedRings.isEmpty else { return }

        for ringIndex in completedRings {
            guard state.oreLifecycle.ringStates[ringIndex] == .surveying else {
                state.oreLifecycle.surveyEndTickByRing.removeValue(forKey: ringIndex)
                continue
            }

            let revealedCount = revealRingPatches(
                ringIndex: ringIndex,
                state: &state
            )
            state.oreLifecycle.ringStates[ringIndex] = .revealed
            state.oreLifecycle.surveyEndTickByRing.removeValue(forKey: ringIndex)

            context.emit(
                SimEvent(
                    tick: state.tick,
                    kind: .ringRevealed,
                    value: ringIndex,
                    reasonDetail: "patches=\(revealedCount)"
                )
            )
        }
    }

    private func revealRingPatches(ringIndex: Int, state: inout WorldState) -> Int {
        guard let ring = ringDefinition(for: ringIndex) else { return 0 }

        let difficultyID = DifficultyID(rawValue: state.run.difficulty.rawValue) ?? .normal
        let patchCount = max(0, ring.patchCount.value(for: difficultyID))
        guard patchCount > 0 else { return 0 }

        let spacing = max(1, config.renewal.minSpacing)
        let base = state.board.basePosition
        let occupiedCells = occupiedCells(in: state)
        let existingPatchPositions = Set(state.orePatches.map { normalized($0.position) })

        let ringCandidates = candidateCells(in: state.board)
            .filter { candidate in
                let distance = chebyshevDistance(candidate, base)
                guard distance >= ring.minDistance && distance <= ring.maxDistance else { return false }
                guard !state.board.isRestricted(candidate), !state.board.isBlocked(candidate) else { return false }
                guard !occupiedCells.contains(candidate) else { return false }
                guard !existingPatchPositions.contains(candidate) else { return false }
                return true
            }

        let rankedCandidates = ringCandidates.sorted { lhs, rhs in
            let lhsHash = hash(seed: state.run.seed, values: [0xA0, UInt64(ringIndex), asUInt64(lhs.x), asUInt64(lhs.y)])
            let rhsHash = hash(seed: state.run.seed, values: [0xA0, UInt64(ringIndex), asUInt64(rhs.x), asUInt64(rhs.y)])
            if lhsHash == rhsHash {
                if lhs.x == rhs.x { return lhs.y < rhs.y }
                return lhs.x < rhs.x
            }
            return lhsHash > rhsHash
        }

        var selected: [GridPosition] = []
        for candidate in rankedCandidates {
            let farEnoughFromExisting = state.orePatches.allSatisfy {
                chebyshevDistance(normalized($0.position), candidate) >= spacing
            }
            guard farEnoughFromExisting else { continue }

            let farEnoughFromSelected = selected.allSatisfy {
                chebyshevDistance($0, candidate) >= spacing
            }
            guard farEnoughFromSelected else { continue }

            selected.append(candidate)
            if selected.count >= patchCount {
                break
            }
        }

        guard !selected.isEmpty else { return 0 }

        var revealed = 0
        for (offset, position) in selected.enumerated() {
            let oreType = rollOreType(seed: state.run.seed, ringIndex: ringIndex, offset: offset)
            let richness = rollRichness(seed: state.run.seed, ringIndex: ringIndex, offset: offset + 10_000)
            let totalOre = oreAmount(for: oreType, richness: richness)

            let patch = OrePatch(
                id: state.oreLifecycle.nextPatchID,
                oreType: oreType,
                richness: richness,
                position: position,
                revealRing: ringIndex,
                isRevealed: true,
                totalOre: totalOre,
                remainingOre: totalOre
            )
            state.oreLifecycle.nextPatchID += 1
            state.orePatches.append(patch)
            addRestrictedCellIfNeeded(position, board: &state.board)
            revealed += 1
        }
        return revealed
    }

    private func processRenewalsAtGapBoundary(state: inout WorldState, context: SystemContext) {
        guard !state.threat.isWaveActive else { return }
        guard state.threat.waveIndex > 0 else { return }
        guard state.oreLifecycle.lastRenewalWaveProcessed < state.threat.waveIndex else { return }

        state.oreLifecycle.lastRenewalWaveProcessed = state.threat.waveIndex

        let difficultyID = DifficultyID(rawValue: state.run.difficulty.rawValue) ?? .normal
        let batchCap = max(1, config.renewal.batchCap.value(for: difficultyID))
        let maxActivePatches = max(1, config.renewal.maxActivePatches)

        var spawned = 0
        let maxAttempts = state.oreLifecycle.renewalQueue.count
        var attempts = 0
        while spawned < batchCap,
              attempts < maxAttempts,
              !state.oreLifecycle.renewalQueue.isEmpty,
              activePatchCount(state) < maxActivePatches {
            attempts += 1
            var request = state.oreLifecycle.renewalQueue.removeFirst()

            if shouldSkipRenewal(request: request, state: state) {
                request.skipCount += 1
                state.oreLifecycle.renewalQueue.append(request)
                continue
            }

            guard let spawnedPatch = spawnRenewalPatch(from: request, state: &state) else {
                state.oreLifecycle.renewalQueue.append(request)
                continue
            }

            spawned += 1
            context.emit(
                SimEvent(
                    tick: state.tick,
                    kind: .oreRenewalSpawned,
                    value: spawnedPatch.id,
                    itemID: spawnedPatch.oreType,
                    reasonDetail: "source=\(request.sourcePatchID)"
                )
            )
        }
    }

    private func shouldSkipRenewal(request: RenewalRequest, state: WorldState) -> Bool {
        guard state.run.difficulty == .hard else { return false }
        guard request.skipCount < config.renewal.hardMaxConsecutiveSkips else { return false }

        let roll = Int(
            hash(
                seed: state.run.seed,
                values: [
                    0xB0,
                    UInt64(max(0, state.threat.waveIndex)),
                    UInt64(max(0, request.sourcePatchID)),
                    UInt64(max(0, request.skipCount))
                ]
            ) % 100
        )
        return roll < config.renewal.hardSkipPercent
    }

    private func spawnRenewalPatch(from request: RenewalRequest, state: inout WorldState) -> OrePatch? {
        let revealedRings = ringDefinitions
            .filter { state.oreLifecycle.ringStates[$0.index] == .revealed }
            .sorted { $0.index < $1.index }
        guard !revealedRings.isEmpty else { return nil }

        let base = normalized(state.board.basePosition)
        let occupied = occupiedCells(in: state)
        let patchPositions = Set(state.orePatches.map { normalized($0.position) })
        let spacing = max(1, config.renewal.minSpacing)
        let minDistanceFromBase = max(0, config.renewal.minDistanceFromBase)

        let candidates = candidateCells(in: state.board)
            .filter { candidate in
                let distance = chebyshevDistance(candidate, base)
                guard distance >= minDistanceFromBase else { return false }
                guard !state.board.isRestricted(candidate), !state.board.isBlocked(candidate) else { return false }
                guard !occupied.contains(candidate) else { return false }
                guard !patchPositions.contains(candidate) else { return false }
                guard revealedRings.contains(where: { distance >= $0.minDistance && distance <= $0.maxDistance }) else { return false }
                return state.orePatches.filter { !$0.isExhausted }.allSatisfy {
                    chebyshevDistance(normalized($0.position), candidate) >= spacing
                }
            }

        guard !candidates.isEmpty else { return nil }

        let maxDistanceFromEdge = [
            base.x,
            state.board.width - 1 - base.x,
            base.y,
            state.board.height - 1 - base.y
        ].max() ?? 1
        let maxDistance = Double(max(1, maxDistanceFromEdge))
        let ranked = candidates.sorted { lhs, rhs in
            let lhsScore = renewalScore(
                position: lhs,
                request: request,
                base: base,
                maxDistance: maxDistance,
                state: state
            )
            let rhsScore = renewalScore(
                position: rhs,
                request: request,
                base: base,
                maxDistance: maxDistance,
                state: state
            )
            if lhsScore == rhsScore {
                if lhs.x == rhs.x { return lhs.y < rhs.y }
                return lhs.x < rhs.x
            }
            return lhsScore > rhsScore
        }

        guard let selected = ranked.first else { return nil }
        let selectedDistance = chebyshevDistance(selected, base)
        let selectedRing = revealedRings.first(where: {
            selectedDistance >= $0.minDistance && selectedDistance <= $0.maxDistance
        })?.index ?? (revealedRings.last?.index ?? 0)
        let richnessRing = revealedRings.last?.index ?? 0
        let richness = rollRichness(
            seed: state.run.seed,
            ringIndex: richnessRing,
            offset: request.sourcePatchID + Int(state.tick % 10_000)
        )
        let totalOre = oreAmount(for: request.oreType, richness: richness)

        let patch = OrePatch(
            id: state.oreLifecycle.nextPatchID,
            oreType: request.oreType,
            richness: richness,
            position: selected,
            revealRing: selectedRing,
            isRevealed: true,
            totalOre: totalOre,
            remainingOre: totalOre
        )
        state.oreLifecycle.nextPatchID += 1
        state.orePatches.append(patch)
        addRestrictedCellIfNeeded(selected, board: &state.board)
        return patch
    }

    private func renewalScore(
        position: GridPosition,
        request: RenewalRequest,
        base: GridPosition,
        maxDistance: Double,
        state: WorldState
    ) -> Double {
        let distance = Double(chebyshevDistance(position, base))
        let normalizedDistance = min(1.0, max(0.0, distance / maxDistance))
        let edgeComponent = pow(normalizedDistance, max(0.1, config.renewal.edgeBiasPower))
        let jitter = unitInterval(
            hash(
                seed: state.run.seed,
                values: [
                    0xC0,
                    UInt64(max(0, request.sourcePatchID)),
                    asUInt64(position.x),
                    asUInt64(position.y),
                    UInt64(max(0, state.threat.waveIndex))
                ]
            )
        ) * 0.15
        return edgeComponent + jitter
    }

    private var ringDefinitions: [OreRingDef] {
        config.rings.sorted { $0.index < $1.index }
    }

    private func ringDefinition(for ringIndex: Int) -> OreRingDef? {
        ringDefinitions.first(where: { $0.index == ringIndex })
    }

    private func rollOreType(seed: RunSeed, ringIndex: Int, offset: Int) -> ItemID {
        let entries = config.oreTypes
            .filter { $0.rarityWeight > 0 }
            .sorted { $0.oreType < $1.oreType }
            .map { ($0.oreType, $0.rarityWeight) }
        guard !entries.isEmpty else { return "ore_iron" }

        let roll = unitInterval(
            hash(
                seed: seed,
                values: [
                    0xD0,
                    UInt64(max(0, ringIndex)),
                    UInt64(max(0, offset))
                ]
            )
        )
        return weightedPick(entries: entries, unitRoll: roll) ?? entries[0].0
    }

    private func rollRichness(seed: RunSeed, ringIndex: Int, offset: Int) -> OrePatchRichness {
        guard let ring = ringDefinition(for: ringIndex) else { return .normal }
        let entries: [(OrePatchRichness, Double)] = [
            (.poor, max(0, ring.richnessWeights.poor)),
            (.normal, max(0, ring.richnessWeights.normal)),
            (.rich, max(0, ring.richnessWeights.rich))
        ]
        let roll = unitInterval(
            hash(
                seed: seed,
                values: [
                    0xE0,
                    UInt64(max(0, ringIndex)),
                    UInt64(max(0, offset))
                ]
            )
        )
        return weightedPick(entries: entries, unitRoll: roll) ?? .normal
    }

    private func oreAmount(for oreType: ItemID, richness: OrePatchRichness) -> Int {
        if let definition = config.oreTypes.first(where: { $0.oreType == oreType }) {
            switch richness {
            case .poor:
                return max(1, definition.amounts.poor)
            case .normal:
                return max(1, definition.amounts.normal)
            case .rich:
                return max(1, definition.amounts.rich)
            }
        }
        switch (oreType, richness) {
        case ("ore_iron", .poor): return 300
        case ("ore_iron", .normal): return 500
        case ("ore_iron", .rich): return 800
        case ("ore_copper", .poor): return 200
        case ("ore_copper", .normal): return 400
        case ("ore_copper", .rich): return 650
        case ("ore_coal", .poor): return 150
        case ("ore_coal", .normal): return 300
        case ("ore_coal", .rich): return 500
        default: return 300
        }
    }

    private func activePatchCount(_ state: WorldState) -> Int {
        state.orePatches.reduce(into: 0) { count, patch in
            if !patch.isExhausted { count += 1 }
        }
    }

    private func candidateCells(in board: BoardState) -> [GridPosition] {
        var cells: [GridPosition] = []
        cells.reserveCapacity(max(1, board.width * board.height))
        for y in 0..<board.height {
            for x in 0..<board.width {
                cells.append(GridPosition(x: x, y: y, z: 0))
            }
        }
        return cells
    }

    private func occupiedCells(in state: WorldState) -> Set<GridPosition> {
        var occupied: Set<GridPosition> = []

        for entity in state.entities.all where entity.category != .projectile {
            let position = normalized(entity.position)
            if entity.category == .structure, let structureType = entity.structureType {
                for cell in structureType.coveredCells(anchor: entity.position) {
                    occupied.insert(normalized(cell))
                }
            } else {
                occupied.insert(position)
            }
        }
        return occupied
    }

    private func addRestrictedCellIfNeeded(_ position: GridPosition, board: inout BoardState) {
        guard !board.restrictedCells.contains(where: { $0.x == position.x && $0.y == position.y }) else { return }
        board.restrictedCells.append(normalized(position))
    }

    private func chebyshevDistance(_ lhs: GridPosition, _ rhs: GridPosition) -> Int {
        max(abs(lhs.x - rhs.x), abs(lhs.y - rhs.y))
    }

    private func normalized(_ position: GridPosition) -> GridPosition {
        GridPosition(x: position.x, y: position.y, z: 0)
    }

    private func unitInterval(_ value: UInt64) -> Double {
        Double(value & 0xFFFF_FFFF) / Double(UInt32.max)
    }

    private func hash(seed: UInt64, values: [UInt64]) -> UInt64 {
        var state = seed == 0 ? 0xA076_1D64_78BD_642F : seed
        for value in values {
            state ^= mix(value &+ 0x9E37_79B9_7F4A_7C15)
            state = mix(state)
        }
        return state
    }

    private func mix(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    private func asUInt64(_ value: Int) -> UInt64 {
        UInt64(bitPattern: Int64(value))
    }

    private func weightedPick<T>(entries: [(T, Double)], unitRoll: Double) -> T? {
        let totalWeight = entries.reduce(0.0) { partial, entry in
            partial + max(0.0, entry.1)
        }
        guard totalWeight > 0 else { return nil }

        var target = max(0.0, min(1.0, unitRoll)) * totalWeight
        for entry in entries {
            let weight = max(0.0, entry.1)
            if target < weight {
                return entry.0
            }
            target -= weight
        }
        return entries.last?.0
    }
}
