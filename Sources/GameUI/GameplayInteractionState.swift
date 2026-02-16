import GameSimulation

public enum GameplayInteractionMode: String, CaseIterable, Identifiable, Sendable {
    case interact = "Interact"
    case build = "Build"

    public var id: Self { self }
}

public struct GameplayInteractionState: Sendable, Hashable {
    public var mode: GameplayInteractionMode

    public init(mode: GameplayInteractionMode = .interact) {
        self.mode = mode
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
            return
        }
        buildMenu.select(entryID: entryID)
        mode = .build
    }

    @discardableResult
    public mutating func completePlacementIfSuccessful(_ placementResult: PlacementResult) -> Bool {
        guard placementResult == .ok else { return false }
        mode = .interact
        return true
    }

    public mutating func enterBuildMode() {
        mode = .build
    }

    public mutating func exitBuildMode() {
        mode = .interact
    }
}
