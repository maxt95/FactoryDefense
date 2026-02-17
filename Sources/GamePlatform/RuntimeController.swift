import Combine
import Foundation
import GameSimulation

@MainActor
public final class GameRuntimeController: ObservableObject {
    @Published public private(set) var world: WorldState
    @Published public private(set) var latestEvents: [SimEvent]
    @Published public private(set) var highlightedCell: GridPosition?
    @Published public private(set) var placementResult: PlacementResult
    @Published public private(set) var runSummary: RunSummarySnapshot?

    public let actor: PlayerID

    private let tickRate: UInt64
    private let engine: SimulationEngine
    private var tickTask: Task<Void, Never>?
    private let placementValidator = PlacementValidator()
    private var placementPreviewCache: PlacementPreviewCache?
    private var summaryCounters = SummaryCounters()

    public init(
        initialWorld: WorldState = .bootstrap(),
        actor: PlayerID = PlayerID(1),
        tickRate: UInt64 = 20
    ) {
        self.world = initialWorld
        self.latestEvents = []
        self.highlightedCell = nil
        self.placementResult = .ok
        self.runSummary = nil
        self.actor = actor
        self.tickRate = max(1, tickRate)
        self.engine = SimulationEngine(worldState: initialWorld, tickRate: max(1, tickRate))
    }

    deinit {
        tickTask?.cancel()
    }

    public func start() {
        guard tickTask == nil else { return }

        let intervalNS = UInt64(1_000_000_000 / max(1, tickRate))
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNS)
                guard let self else { return }
                _ = self.advanceTick()
            }
        }
    }

    public func stop() {
        tickTask?.cancel()
        tickTask = nil
    }

    @discardableResult
    public func advanceTick() -> [SimEvent] {
        let previousBoard = world.board
        let events = engine.step()
        world = engine.worldState
        latestEvents = events
        consumeSummaryEvents(events)
        if world.board != previousBoard {
            clearPlacementPreview()
        }
        return events
    }

    public func advanceTicks(_ ticks: Int) {
        guard ticks > 0 else { return }
        for _ in 0..<ticks {
            _ = advanceTick()
        }
    }

    public func previewPlacement(structure: StructureType, at position: GridPosition) {
        let cacheKey = PlacementPreviewCache.Key(
            structure: structure,
            requestedPosition: position,
            tick: world.tick
        )
        if let cached = placementPreviewCache, cached.key == cacheKey {
            highlightedCell = cached.highlightedCell
            placementResult = cached.result
            return
        }

        let anchorPosition = placementAnchor(for: structure, requestedPosition: position)
        highlightedCell = anchorPosition
        let coveredCells = structure.coveredCells(anchor: anchorPosition)
        guard let expansionInsets = world.board.plannedExpansion(for: coveredCells) else {
            placementResult = .outOfBounds
            placementPreviewCache = PlacementPreviewCache(
                key: cacheKey,
                highlightedCell: anchorPosition,
                result: .outOfBounds
            )
            return
        }

        var previewWorld = world
        previewWorld.applyBoardExpansion(expansionInsets)
        let adjustedPosition = anchorPosition.translated(byX: expansionInsets.left, byY: expansionInsets.top)
        let result = placementValidator.canPlace(structure, at: adjustedPosition, in: previewWorld)
        guard result == .ok else {
            placementResult = result
            placementPreviewCache = PlacementPreviewCache(
                key: cacheKey,
                highlightedCell: anchorPosition,
                result: result
            )
            return
        }

        let affordabilityResult: PlacementResult = world.economy.canAfford(structure.buildCosts) ? .ok : .insufficientResources
        placementResult = affordabilityResult
        placementPreviewCache = PlacementPreviewCache(
            key: cacheKey,
            highlightedCell: anchorPosition,
            result: affordabilityResult
        )
    }

    public func clearPlacementPreview() {
        highlightedCell = nil
        placementResult = .ok
        placementPreviewCache = nil
    }

    public func placeStructure(
        _ structure: StructureType,
        at position: GridPosition,
        rotation: Rotation = .north,
        targetPatchID: Int? = nil
    ) {
        let anchorPosition = placementAnchor(for: structure, requestedPosition: position)
        previewPlacement(structure: structure, at: position)
        guard placementResult == .ok else { return }

        enqueue(
            payload: .placeStructure(
                BuildRequest(
                    structure: structure,
                    position: anchorPosition,
                    rotation: rotation,
                    targetPatchID: targetPatchID
                )
            )
        )
    }

    public func placePreviewedStructure(
        _ structure: StructureType,
        rotation: Rotation = .north,
        targetPatchID: Int? = nil
    ) {
        guard placementResult == .ok, let anchorPosition = highlightedCell else { return }
        enqueue(
            payload: .placeStructure(
                BuildRequest(
                    structure: structure,
                    position: anchorPosition,
                    rotation: rotation,
                    targetPatchID: targetPatchID
                )
            )
        )
    }

    public func placeConveyor(at position: GridPosition, direction: CardinalDirection) {
        enqueue(payload: .placeConveyor(position: position, direction: direction))
    }

    public func configureConveyorIO(
        entityID: EntityID,
        inputDirection: CardinalDirection,
        outputDirection: CardinalDirection
    ) {
        enqueue(
            payload: .configureConveyorIO(
                entityID: entityID,
                inputDirection: inputDirection,
                outputDirection: outputDirection
            )
        )
    }

    public func placeStructurePath(
        _ structure: StructureType,
        along points: [GridPosition],
        rotation: Rotation = .north,
        targetPatchID: Int? = nil
    ) {
        guard !points.isEmpty else { return }

        var simulatedWorld = world
        var placedAny = false

        for position in points {
            let anchorPosition = placementAnchor(for: structure, requestedPosition: position)
            let coveredCells = structure.coveredCells(anchor: anchorPosition)
            guard let expansionInsets = simulatedWorld.board.plannedExpansion(for: coveredCells) else {
                continue
            }

            let placementAnchor = anchorPosition.translated(byX: expansionInsets.left, byY: expansionInsets.top)
            var previewState = simulatedWorld
            previewState.applyBoardExpansion(expansionInsets)
            let result = placementValidator.canPlace(
                structure,
                at: placementAnchor,
                targetPatchID: targetPatchID,
                in: previewState
            )
            guard result == .ok else {
                continue
            }

            guard simulatedWorld.economy.canAfford(structure.buildCosts) else {
                placementResult = .insufficientResources
                break
            }

            enqueue(
                payload: .placeStructure(
                    BuildRequest(
                        structure: structure,
                        position: anchorPosition,
                        rotation: rotation,
                        targetPatchID: targetPatchID
                    )
                )
            )

            simulatedWorld.applyBoardExpansion(expansionInsets)
            let placedPosition = GridPosition(
                x: placementAnchor.x,
                y: placementAnchor.y,
                z: simulatedWorld.board.elevation(at: placementAnchor)
            )
            simulatedWorld.entities.spawnStructure(
                structure,
                at: placedPosition,
                rotation: rotation,
                boundPatchID: targetPatchID
            )
            _ = simulatedWorld.economy.consume(costs: structure.buildCosts)
            placedAny = true
        }

        if placedAny {
            placementResult = .ok
        }
    }

    public func removeStructure(entityID: EntityID) {
        enqueue(payload: .removeStructure(entityID: entityID))
    }

    public func rotateBuilding(entityID: EntityID) {
        enqueue(payload: .rotateBuilding(entityID: entityID))
    }

    public func pinRecipe(entityID: EntityID, recipeID: String) {
        enqueue(payload: .pinRecipe(entityID: entityID, recipeID: recipeID))
    }

    public func triggerWave() {
        enqueue(payload: .triggerWave)
    }

    public func enqueue(payload: CommandPayload) {
        let command = PlayerCommand(
            tick: world.tick,
            actor: actor,
            payload: payload
        )
        engine.enqueue(command)
    }

    public func apply(
        input event: InputEvent,
        mapper: InputMapper = DefaultInputMapper()
    ) {
        guard let command = mapper.map(event: event, tick: world.tick, actor: actor) else {
            return
        }
        engine.enqueue(command)
    }

    private func placementAnchor(for structure: StructureType, requestedPosition: GridPosition) -> GridPosition {
        let footprint = structure.footprint
        return requestedPosition.translated(
            byX: footprint.width - 1,
            byY: footprint.height - 1
        )
    }

    public func snapshot() -> WorldSnapshot {
        engine.makeSnapshot()
    }

    private func consumeSummaryEvents(_ events: [SimEvent]) {
        for event in events {
            switch event.kind {
            case .enemyDestroyed:
                summaryCounters.enemiesDestroyed += 1
            case .structurePlaced:
                summaryCounters.structuresBuilt += 1
            case .ammoSpent:
                summaryCounters.ammoSpent += max(0, event.value ?? 0)
            case .gameOver:
                guard runSummary == nil else { continue }
                let finalTick: UInt64
                if let tickValue = event.value, tickValue >= 0 {
                    finalTick = UInt64(tickValue)
                } else {
                    finalTick = event.tick
                }

                runSummary = RunSummarySnapshot(
                    finalTick: finalTick,
                    wavesSurvived: world.threat.waveIndex,
                    enemiesDestroyed: summaryCounters.enemiesDestroyed,
                    structuresBuilt: summaryCounters.structuresBuilt,
                    ammoSpent: summaryCounters.ammoSpent
                )
                stop()
            default:
                continue
            }
        }
    }
}

private struct SummaryCounters {
    var enemiesDestroyed: Int = 0
    var structuresBuilt: Int = 0
    var ammoSpent: Int = 0
}

private struct PlacementPreviewCache {
    struct Key: Hashable {
        var structure: StructureType
        var requestedPosition: GridPosition
        var tick: UInt64
    }

    var key: Key
    var highlightedCell: GridPosition
    var result: PlacementResult
}
