import Combine
import Foundation
import GameSimulation

@MainActor
public final class GameRuntimeController: ObservableObject {
    @Published public private(set) var world: WorldState
    @Published public private(set) var latestEvents: [SimEvent]
    @Published public private(set) var highlightedCell: GridPosition?
    @Published public private(set) var placementResult: PlacementResult

    public let actor: PlayerID

    private let tickRate: UInt64
    private let engine: SimulationEngine
    private var tickTask: Task<Void, Never>?
    private let placementValidator = PlacementValidator()

    public init(
        initialWorld: WorldState = .bootstrap(),
        actor: PlayerID = PlayerID(1),
        tickRate: UInt64 = 20
    ) {
        self.world = initialWorld
        self.latestEvents = []
        self.highlightedCell = nil
        self.placementResult = .ok
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
        let anchorPosition = placementAnchor(for: structure, requestedPosition: position)
        highlightedCell = anchorPosition
        let coveredCells = structure.coveredCells(anchor: anchorPosition)
        guard let expansionInsets = world.board.plannedExpansion(for: coveredCells) else {
            placementResult = .outOfBounds
            return
        }

        var previewWorld = world
        previewWorld.applyBoardExpansion(expansionInsets)
        let adjustedPosition = anchorPosition.translated(byX: expansionInsets.left, byY: expansionInsets.top)
        let result = placementValidator.canPlace(structure, at: adjustedPosition, in: previewWorld)
        guard result == .ok else {
            placementResult = result
            return
        }

        placementResult = world.economy.canAfford(structure.buildCosts) ? .ok : .insufficientResources
    }

    public func clearPlacementPreview() {
        highlightedCell = nil
        placementResult = .ok
    }

    public func placeStructure(_ structure: StructureType, at position: GridPosition) {
        let anchorPosition = placementAnchor(for: structure, requestedPosition: position)
        previewPlacement(structure: structure, at: position)
        guard placementResult == .ok else { return }

        enqueue(
            payload: .placeStructure(
                BuildRequest(
                    structure: structure,
                    position: anchorPosition
                )
            )
        )
    }

    public func placePreviewedStructure(_ structure: StructureType) {
        guard placementResult == .ok, let anchorPosition = highlightedCell else { return }
        enqueue(
            payload: .placeStructure(
                BuildRequest(
                    structure: structure,
                    position: anchorPosition
                )
            )
        )
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
}
