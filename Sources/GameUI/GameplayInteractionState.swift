import GameSimulation

public enum GameplayInteractionMode: String, CaseIterable, Identifiable, Sendable {
    case interact = "Interact"
    case build = "Build"
    case editBelts = "Edit Belts"
    case planBelt = "Plan Belt"

    public var id: Self { self }
}

public struct GameplayInteractionState: Sendable, Hashable {
    public var mode: GameplayInteractionMode
    public var pendingDemolishEntityID: EntityID?
    public var quickEditTarget: EntityID?
    public var dragDrawStart: GridPosition?
    public var dragDrawCurrent: GridPosition?
    public var dragPreviewPath: [GridPosition]
    public var dragPreviewCells: [DragPreviewCell]
    public var dragCellSequence: [GridPosition]
    public var flowBrush: FlowBrushState
    public var beltPlanner: BeltPlannerState

    public init(
        mode: GameplayInteractionMode = .interact,
        pendingDemolishEntityID: EntityID? = nil,
        quickEditTarget: EntityID? = nil,
        dragDrawStart: GridPosition? = nil,
        dragDrawCurrent: GridPosition? = nil,
        dragPreviewPath: [GridPosition] = [],
        dragPreviewCells: [DragPreviewCell] = [],
        dragCellSequence: [GridPosition] = [],
        flowBrush: FlowBrushState = FlowBrushState(),
        beltPlanner: BeltPlannerState = BeltPlannerState()
    ) {
        self.mode = mode
        self.pendingDemolishEntityID = pendingDemolishEntityID
        self.quickEditTarget = quickEditTarget
        self.dragDrawStart = dragDrawStart
        self.dragDrawCurrent = dragDrawCurrent
        self.dragPreviewPath = dragPreviewPath
        self.dragPreviewCells = dragPreviewCells
        self.dragCellSequence = dragCellSequence
        self.flowBrush = flowBrush
        self.beltPlanner = beltPlanner
    }

    public var isBuildMode: Bool {
        mode == .build
    }

    public func selectedStructure(from buildMenu: BuildMenuViewModel, fallback: StructureType = .wall) -> StructureType {
        buildMenu.selectedEntry()?.structure ?? fallback
    }

    public mutating func selectBuildEntry(_ entryID: String, in buildMenu: inout BuildMenuViewModel) {
        if buildMenu.selectedEntryID == entryID, mode == .build {
            mode = .interact
            cancelDragDraw()
            return
        }
        buildMenu.select(entryID: entryID)
        mode = .build
    }

    @discardableResult
    public mutating func completePlacementIfSuccessful(_ placementResult: PlacementResult) -> Bool {
        guard placementResult == .ok else { return false }
        mode = .interact
        cancelDragDraw()
        return true
    }

    public mutating func enterBuildMode() {
        mode = .build
    }

    public mutating func exitBuildMode() {
        mode = .interact
        cancelDragDraw()
        quickEditTarget = nil
        flowBrush = FlowBrushState()
        beltPlanner = BeltPlannerState()
    }

    public mutating func enterEditBeltsMode() {
        mode = .editBelts
        cancelDragDraw()
        quickEditTarget = nil
        beltPlanner = BeltPlannerState()
    }

    public mutating func exitEditBeltsMode() {
        mode = .interact
        flowBrush = FlowBrushState()
    }

    public mutating func enterPlanBeltMode() {
        mode = .planBelt
        cancelDragDraw()
        quickEditTarget = nil
        flowBrush = FlowBrushState()
    }

    public mutating func exitPlanBeltMode() {
        mode = .interact
        beltPlanner = BeltPlannerState()
    }

    public mutating func requestDemolish(entityID: EntityID) {
        pendingDemolishEntityID = entityID
    }

    public mutating func cancelDemolish() {
        pendingDemolishEntityID = nil
    }

    public mutating func confirmDemolish() -> EntityID? {
        let entityID = pendingDemolishEntityID
        pendingDemolishEntityID = nil
        return entityID
    }

    public var isDragDrawActive: Bool {
        dragDrawStart != nil
    }

    public mutating func beginDragDraw(at position: GridPosition) {
        dragDrawStart = position
        dragDrawCurrent = position
        dragPreviewPath = [position]
        dragCellSequence = [position]
    }

    public mutating func updateDragDraw(
        at position: GridPosition,
        using planner: GameplayDragDrawPlanner = GameplayDragDrawPlanner()
    ) {
        guard let start = dragDrawStart else { return }
        dragDrawCurrent = position
        dragPreviewPath = planner.dominantAxisPath(from: start, to: position)
    }

    /// Accumulates cells for conveyor smart-path drag. Rejects diagonal inputs
    /// at the source (cursor jumped diagonally due to fast movement) — those are
    /// never intentional belt directions. Cardinal gaps (skipped cells along one
    /// axis) are accepted and interpolated later by smartPath.
    public mutating func accumulateConveyorDragCell(
        _ position: GridPosition,
        using planner: GameplayDragDrawPlanner = GameplayDragDrawPlanner()
    ) {
        guard dragDrawStart != nil else { return }
        dragDrawCurrent = position
        if position != dragCellSequence.last {
            // Reject diagonal jumps — both axes changed simultaneously
            if let last = dragCellSequence.last {
                let dx = position.x - last.x
                let dy = position.y - last.y
                if dx != 0 && dy != 0 {
                    return // Diagonal; wait for a cardinal-adjacent cell
                }
            }
            dragCellSequence.append(position)
        }
        dragPreviewCells = planner.smartPath(cellSequence: dragCellSequence)
        dragPreviewPath = dragPreviewCells.map(\.position)
    }

    public mutating func cancelDragDraw() {
        dragDrawStart = nil
        dragDrawCurrent = nil
        dragPreviewPath = []
        dragPreviewCells = []
        dragCellSequence = []
    }

    public mutating func finishDragDraw(using planner: GameplayDragDrawPlanner = GameplayDragDrawPlanner()) -> [GridPosition] {
        guard let start = dragDrawStart else { return [] }
        let end = dragDrawCurrent ?? start
        let path = planner.dominantAxisPath(from: start, to: end)
        cancelDragDraw()
        return path
    }

    /// Finish a conveyor smart-path drag. Returns the resolved preview cells with I/O directions.
    public mutating func finishConveyorDragDraw(
        using planner: GameplayDragDrawPlanner = GameplayDragDrawPlanner()
    ) -> [DragPreviewCell] {
        let cells = planner.smartPath(cellSequence: dragCellSequence)
        cancelDragDraw()
        return cells
    }

    public func previewAffordableCount(for structure: StructureType, inventory: [String: Int]) -> Int {
        guard isDragDrawActive else { return 0 }

        let costs = structure.buildCosts.filter { $0.quantity > 0 }
        guard !costs.isEmpty else { return dragPreviewPath.count }

        var affordable = Int.max
        for cost in costs {
            let available = inventory[cost.itemID, default: 0]
            affordable = min(affordable, available / cost.quantity)
        }
        return max(0, affordable)
    }
}
