import Combine
import Foundation
import GameContent
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

        let result: PlacementResult
        if expansionInsets.isEmpty {
            result = placementValidator.canPlace(structure, at: anchorPosition, in: world)
        } else {
            var previewWorld = world
            previewWorld.applyBoardExpansion(expansionInsets)
            let adjustedPosition = anchorPosition.translated(byX: expansionInsets.left, byY: expansionInsets.top)
            result = placementValidator.canPlace(structure, at: adjustedPosition, in: previewWorld)
        }
        guard result == .ok else {
            placementResult = result
            placementPreviewCache = PlacementPreviewCache(
                key: cacheKey,
                highlightedCell: anchorPosition,
                result: result
            )
            return
        }

        let affordabilityResult: PlacementResult = Self.canAfford(
            costs: structure.buildCosts,
            from: world.aggregatedPhysicalInventory()
        ) ? .ok : .insufficientResources
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

    /// Places conveyors along a smart path with per-cell I/O directions.
    /// Emits placeConveyor for each cell, plus configureConveyorIO for non-default I/O.
    /// Endpoints are auto-snapped to connect with adjacent existing infrastructure.
    public func placeConveyorPath(_ cells: [ConveyorPlacementCell]) {
        guard !cells.isEmpty else { return }

        var adjustedCells = cells
        snapPathEndpoints(&adjustedCells, in: world)

        var simulatedWorld = world
        var simulatedInventory = simulatedWorld.aggregatedPhysicalInventory()

        for cell in adjustedCells {
            let structure = StructureType.conveyor
            let anchorPosition = placementAnchor(for: structure, requestedPosition: cell.position)
            let coveredCells = structure.coveredCells(anchor: anchorPosition)
            guard let expansionInsets = simulatedWorld.board.plannedExpansion(for: coveredCells) else {
                continue
            }

            let placementAnchor = anchorPosition.translated(byX: expansionInsets.left, byY: expansionInsets.top)
            var previewState = simulatedWorld
            previewState.applyBoardExpansion(expansionInsets)
            let result = placementValidator.canPlace(structure, at: placementAnchor, in: previewState)
            guard result == .ok else { continue }

            guard Self.canAfford(costs: structure.buildCosts, from: simulatedInventory) else {
                placementResult = .insufficientResources
                break
            }

            // Place the conveyor with I/O bundled atomically — avoids entity ID
            // prediction failures caused by command sort reordering.
            enqueue(payload: .placeConveyor(
                position: cell.position,
                direction: cell.outputDirection,
                inputDirection: cell.inputDirection,
                outputDirection: cell.outputDirection
            ))

            simulatedWorld.applyBoardExpansion(expansionInsets)
            let placedPosition = GridPosition(
                x: placementAnchor.x,
                y: placementAnchor.y,
                z: simulatedWorld.board.elevation(at: placementAnchor)
            )
            simulatedWorld.entities.spawnStructure(structure, at: placedPosition, rotation: .north)
            Self.consume(costs: structure.buildCosts, from: &simulatedInventory)
        }
    }

    public func placeStructurePath(
        _ structure: StructureType,
        along points: [GridPosition],
        rotation: Rotation = .north,
        targetPatchID: Int? = nil
    ) {
        guard !points.isEmpty else { return }

        var simulatedWorld = world
        var simulatedInventory = simulatedWorld.aggregatedPhysicalInventory()
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

            guard Self.canAfford(costs: structure.buildCosts, from: simulatedInventory) else {
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
            Self.consume(costs: structure.buildCosts, from: &simulatedInventory)
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

    private static func canAfford(costs: [ItemStack], from inventory: [ItemID: Int]) -> Bool {
        costs.allSatisfy { inventory[$0.itemID, default: 0] >= $0.quantity }
    }

    private static func consume(costs: [ItemStack], from inventory: inout [ItemID: Int]) {
        for cost in costs where cost.quantity > 0 {
            let current = inventory[cost.itemID, default: 0]
            let updated = max(0, current - cost.quantity)
            if updated == 0 {
                inventory.removeValue(forKey: cost.itemID)
            } else {
                inventory[cost.itemID] = updated
            }
        }
    }

    public func deductFromInputBuffer(entityID: EntityID, costs: [ItemStack]) -> Bool {
        var buffer = engine.worldState.economy.structureInputBuffers[entityID, default: [:]]
        for cost in costs {
            guard buffer[cost.itemID, default: 0] >= cost.quantity else { return false }
        }
        for cost in costs {
            buffer[cost.itemID, default: 0] -= cost.quantity
            if buffer[cost.itemID, default: 0] <= 0 {
                buffer.removeValue(forKey: cost.itemID)
            }
        }
        engine.worldState.economy.structureInputBuffers[entityID] = buffer
        engine.worldState.rebuildAggregatedInventory()
        world = engine.worldState
        return true
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

// MARK: - Conveyor Endpoint Snapping

extension GameRuntimeController {
    /// Adjusts the first and last cells of a conveyor path to connect with
    /// adjacent existing infrastructure (conveyors, buildings, splitters, mergers).
    func snapPathEndpoints(_ cells: inout [ConveyorPlacementCell], in world: WorldState) {
        guard !cells.isEmpty else { return }

        let pathPositions = Set(cells.map(\.position))

        // Snap first cell's input to an adjacent feeder (if the default doesn't already connect)
        snapFirstCellInput(&cells, pathPositions: pathPositions, world: world)

        // Snap last cell's output to an adjacent receiver (if the default doesn't already connect)
        snapLastCellOutput(&cells, pathPositions: pathPositions, world: world)
    }

    private func snapFirstCellInput(
        _ cells: inout [ConveyorPlacementCell],
        pathPositions: Set<GridPosition>,
        world: WorldState
    ) {
        let firstCell = cells[0]

        // Check if the current input direction already connects to a feeding neighbor
        if neighborFeedsToward(
            cellPosition: firstCell.position,
            fromDirection: firstCell.inputDirection,
            pathPositions: pathPositions,
            world: world
        ) {
            return // Already connected
        }

        // Look for a neighbor that feeds toward us from a different direction
        for direction in CardinalDirection.allCases {
            if direction == firstCell.inputDirection { continue } // Already checked
            if direction == firstCell.outputDirection { continue } // Can't receive from output side

            if neighborFeedsToward(
                cellPosition: firstCell.position,
                fromDirection: direction,
                pathPositions: pathPositions,
                world: world
            ) {
                cells[0].inputDirection = direction
                cells[0].isCorner = cells[0].inputDirection != cells[0].outputDirection.opposite
                return
            }
        }
    }

    private func snapLastCellOutput(
        _ cells: inout [ConveyorPlacementCell],
        pathPositions: Set<GridPosition>,
        world: WorldState
    ) {
        let lastIdx = cells.count - 1
        let lastCell = cells[lastIdx]

        // Check if the current output direction already connects to a receiving neighbor
        if neighborAcceptsFrom(
            cellPosition: lastCell.position,
            towardDirection: lastCell.outputDirection,
            pathPositions: pathPositions,
            world: world
        ) {
            return // Already connected
        }

        // Look for a neighbor that accepts items from us in a different direction
        for direction in CardinalDirection.allCases {
            if direction == lastCell.outputDirection { continue } // Already checked
            if direction == lastCell.inputDirection { continue } // Can't output toward input side

            if neighborAcceptsFrom(
                cellPosition: lastCell.position,
                towardDirection: direction,
                pathPositions: pathPositions,
                world: world
            ) {
                cells[lastIdx].outputDirection = direction
                cells[lastIdx].isCorner = cells[lastIdx].inputDirection != cells[lastIdx].outputDirection.opposite
                return
            }
        }
    }

    /// Checks if there's a neighbor at `cellPosition.translated(by: fromDirection)` that
    /// outputs toward `cellPosition` (i.e., could feed items into a conveyor here).
    private func neighborFeedsToward(
        cellPosition: GridPosition,
        fromDirection: CardinalDirection,
        pathPositions: Set<GridPosition>,
        world: WorldState
    ) -> Bool {
        let neighborPos = cellPosition.translated(by: fromDirection)
        guard !pathPositions.contains(neighborPos) else { return false }
        guard let neighbor = world.entities.selectableEntity(at: neighborPos),
              let structType = neighbor.structureType else { return false }

        // The neighbor is in `fromDirection` from us. For it to feed us,
        // it must output in the opposite direction (toward us).
        let dirFromNeighborToUs = fromDirection.opposite

        switch structType {
        case .conveyor:
            let io = world.economy.conveyorIOByEntity[neighbor.id]
                ?? ConveyorIOConfig.default(for: neighbor.rotation)
            return io.outputDirection == dirFromNeighborToUs

        case .splitter:
            // Splitter outputs go to facing.left and facing.right
            let facing = neighbor.rotation.direction
            return dirFromNeighborToUs == facing.left || dirFromNeighborToUs == facing.right

        case .merger:
            // Merger output goes forward (facing direction)
            return dirFromNeighborToUs == neighbor.rotation.direction

        case .miner, .smelter, .assembler, .ammoModule, .storage, .hq, .powerPlant:
            // Buildings output in all directions
            return true

        case .researchCenter:
            // Research Centers are input-only, never feed items out
            return false

        default:
            return false
        }
    }

    /// Checks if there's a neighbor at `cellPosition.translated(by: towardDirection)` that
    /// accepts items from `cellPosition` (i.e., has an input port facing us).
    private func neighborAcceptsFrom(
        cellPosition: GridPosition,
        towardDirection: CardinalDirection,
        pathPositions: Set<GridPosition>,
        world: WorldState
    ) -> Bool {
        let neighborPos = cellPosition.translated(by: towardDirection)
        guard !pathPositions.contains(neighborPos) else { return false }
        guard let neighbor = world.entities.selectableEntity(at: neighborPos),
              let structType = neighbor.structureType else { return false }

        // The neighbor is in `towardDirection` from us. For it to accept from us,
        // it must have an input facing toward us (i.e., facing towardDirection.opposite).
        let dirFromNeighborToUs = towardDirection.opposite

        switch structType {
        case .conveyor:
            let io = world.economy.conveyorIOByEntity[neighbor.id]
                ?? ConveyorIOConfig.default(for: neighbor.rotation)
            return io.inputDirection == dirFromNeighborToUs

        case .splitter:
            // Splitter input is from behind (facing.opposite)
            return dirFromNeighborToUs == neighbor.rotation.direction.opposite

        case .merger:
            // Merger inputs come from facing.left and facing.right
            let facing = neighbor.rotation.direction
            return dirFromNeighborToUs == facing.left || dirFromNeighborToUs == facing.right

        case .miner, .smelter, .assembler, .ammoModule, .storage, .hq, .powerPlant, .researchCenter:
            // Buildings accept from all directions
            return true

        default:
            return false
        }
    }
}

private struct SummaryCounters {
    var enemiesDestroyed: Int = 0
    var structuresBuilt: Int = 0
    var ammoSpent: Int = 0
}

/// Lightweight cell data for conveyor path placement, usable without GameUI dependency.
public struct ConveyorPlacementCell: Sendable {
    public var position: GridPosition
    public var inputDirection: CardinalDirection
    public var outputDirection: CardinalDirection
    public var isCorner: Bool

    public init(
        position: GridPosition,
        inputDirection: CardinalDirection,
        outputDirection: CardinalDirection,
        isCorner: Bool = false
    ) {
        self.position = position
        self.inputDirection = inputDirection
        self.outputDirection = outputDirection
        self.isCorner = isCorner
    }
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
