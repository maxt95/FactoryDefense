import GameSimulation

public enum GameplayInteractionMode: String, CaseIterable, Identifiable, Sendable {
    case interact = "Interact"
    case build = "Build"

    public var id: Self { self }
}

public struct GameplayInteractionState: Sendable, Hashable {
    public var mode: GameplayInteractionMode
    public var pendingDemolishEntityID: EntityID?
    public var dragDrawStart: GridPosition?
    public var dragDrawCurrent: GridPosition?
    public var dragPreviewPath: [GridPosition]

    public init(
        mode: GameplayInteractionMode = .interact,
        pendingDemolishEntityID: EntityID? = nil,
        dragDrawStart: GridPosition? = nil,
        dragDrawCurrent: GridPosition? = nil,
        dragPreviewPath: [GridPosition] = []
    ) {
        self.mode = mode
        self.pendingDemolishEntityID = pendingDemolishEntityID
        self.dragDrawStart = dragDrawStart
        self.dragDrawCurrent = dragDrawCurrent
        self.dragPreviewPath = dragPreviewPath
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
    }

    public mutating func updateDragDraw(
        at position: GridPosition,
        using planner: GameplayDragDrawPlanner = GameplayDragDrawPlanner()
    ) {
        guard let start = dragDrawStart else { return }
        dragDrawCurrent = position
        dragPreviewPath = planner.dominantAxisPath(from: start, to: position)
    }

    public mutating func cancelDragDraw() {
        dragDrawStart = nil
        dragDrawCurrent = nil
        dragPreviewPath = []
    }

    public mutating func finishDragDraw(using planner: GameplayDragDrawPlanner = GameplayDragDrawPlanner()) -> [GridPosition] {
        guard let start = dragDrawStart else { return [] }
        let end = dragDrawCurrent ?? start
        let path = planner.dominantAxisPath(from: start, to: end)
        cancelDragDraw()
        return path
    }
}
