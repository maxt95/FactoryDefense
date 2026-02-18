import GameSimulation

public struct DragPreviewCell: Sendable, Hashable {
    public var position: GridPosition
    public var inputDirection: CardinalDirection
    public var outputDirection: CardinalDirection
    public var isCorner: Bool
    public var validationResult: PlacementResult

    public init(
        position: GridPosition,
        inputDirection: CardinalDirection,
        outputDirection: CardinalDirection,
        isCorner: Bool = false,
        validationResult: PlacementResult = .ok
    ) {
        self.position = position
        self.inputDirection = inputDirection
        self.outputDirection = outputDirection
        self.isCorner = isCorner
        self.validationResult = validationResult
    }
}
