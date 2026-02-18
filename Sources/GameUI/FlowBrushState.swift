import GameSimulation

public struct FlowBrushState: Sendable, Hashable {
    public var isActive: Bool
    public var strokeCells: [GridPosition]
    public var proposedChanges: [FlowBrushChange]

    public init(
        isActive: Bool = false,
        strokeCells: [GridPosition] = [],
        proposedChanges: [FlowBrushChange] = []
    ) {
        self.isActive = isActive
        self.strokeCells = strokeCells
        self.proposedChanges = proposedChanges
    }

    public mutating func beginStroke(at position: GridPosition) {
        isActive = true
        strokeCells = [position]
        proposedChanges = []
    }

    public mutating func extendStroke(to position: GridPosition) {
        guard isActive else { return }
        if let lastIndex = strokeCells.lastIndex(of: position) {
            // Rubber-band: truncate back to previously visited cell
            strokeCells = Array(strokeCells[...lastIndex])
        } else {
            strokeCells.append(position)
        }
        recomputeProposedChanges()
    }

    public mutating func finishStroke() -> [FlowBrushChange] {
        let changes = proposedChanges
        isActive = false
        strokeCells = []
        proposedChanges = []
        return changes
    }

    public mutating func cancelStroke() {
        isActive = false
        strokeCells = []
        proposedChanges = []
    }

    private mutating func recomputeProposedChanges() {
        guard strokeCells.count >= 2 else {
            proposedChanges = []
            return
        }

        var changes: [FlowBrushChange] = []
        for i in 0..<strokeCells.count {
            let current = strokeCells[i]

            let inputDir: CardinalDirection
            let outputDir: CardinalDirection

            if i == 0 {
                // First cell: input = opposite of direction toward next cell
                let dirToNext = cardinalDirection(from: current, to: strokeCells[i + 1])
                guard let dir = dirToNext else { continue }
                outputDir = dir
                inputDir = dir.opposite
            } else if i == strokeCells.count - 1 {
                // Last cell: output = same as direction from previous cell
                let dirFromPrev = cardinalDirection(from: strokeCells[i - 1], to: current)
                guard let dir = dirFromPrev else { continue }
                inputDir = dir.opposite
                outputDir = dir
            } else {
                let dirFromPrev = cardinalDirection(from: strokeCells[i - 1], to: current)
                let dirToNext = cardinalDirection(from: current, to: strokeCells[i + 1])
                guard let fromDir = dirFromPrev, let toDir = dirToNext else { continue }
                inputDir = fromDir.opposite
                outputDir = toDir
            }

            changes.append(FlowBrushChange(
                position: current,
                newInput: inputDir,
                newOutput: outputDir
            ))
        }
        proposedChanges = changes
    }
}

public struct FlowBrushChange: Sendable, Hashable {
    public var position: GridPosition
    public var newInput: CardinalDirection
    public var newOutput: CardinalDirection

    public init(position: GridPosition, newInput: CardinalDirection, newOutput: CardinalDirection) {
        self.position = position
        self.newInput = newInput
        self.newOutput = newOutput
    }
}

func cardinalDirection(from a: GridPosition, to b: GridPosition) -> CardinalDirection? {
    let dx = b.x - a.x
    let dy = b.y - a.y
    if dx == 1 && dy == 0 { return .east }
    if dx == -1 && dy == 0 { return .west }
    if dx == 0 && dy == 1 { return .south }
    if dx == 0 && dy == -1 { return .north }
    return nil
}
