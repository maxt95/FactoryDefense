import GameSimulation

public enum BeltPlannerVariant: String, CaseIterable, Sendable, Hashable {
    case hFirst = "H-first"
    case vFirst = "V-first"

    public func next() -> BeltPlannerVariant {
        switch self {
        case .hFirst: return .vFirst
        case .vFirst: return .hFirst
        }
    }
}

public struct BeltPlannerState: Sendable, Hashable {
    public var isActive: Bool
    public var startPin: GridPosition?
    public var endPin: GridPosition?
    public var selectedVariant: BeltPlannerVariant
    public var previewPath: [DragPreviewCell]

    public init(
        isActive: Bool = false,
        startPin: GridPosition? = nil,
        endPin: GridPosition? = nil,
        selectedVariant: BeltPlannerVariant = .hFirst,
        previewPath: [DragPreviewCell] = []
    ) {
        self.isActive = isActive
        self.startPin = startPin
        self.endPin = endPin
        self.selectedVariant = selectedVariant
        self.previewPath = previewPath
    }

    public mutating func setStart(_ position: GridPosition) {
        isActive = true
        startPin = position
        endPin = nil
        selectedVariant = .hFirst
        previewPath = []
    }

    public mutating func setEnd(_ position: GridPosition) {
        endPin = position
        recomputePath()
    }

    public mutating func cycleVariant() {
        selectedVariant = selectedVariant.next()
        recomputePath()
    }

    public mutating func confirm() -> [DragPreviewCell] {
        let path = previewPath
        reset()
        return path
    }

    public mutating func reset() {
        isActive = false
        startPin = nil
        endPin = nil
        selectedVariant = .hFirst
        previewPath = []
    }

    private mutating func recomputePath() {
        guard let start = startPin, let end = endPin else {
            previewPath = []
            return
        }
        previewPath = Self.manhattanPath(from: start, to: end, variant: selectedVariant)
    }

    public static func manhattanPath(
        from start: GridPosition,
        to end: GridPosition,
        variant: BeltPlannerVariant
    ) -> [DragPreviewCell] {
        guard start != end else {
            return [DragPreviewCell(
                position: start,
                inputDirection: .west,
                outputDirection: .east
            )]
        }

        var positions: [GridPosition] = []

        let dx = end.x - start.x
        let dy = end.y - start.y

        switch variant {
        case .hFirst:
            // Horizontal segment first, then vertical
            if dx != 0 {
                let stepX = dx > 0 ? 1 : -1
                for i in 0...abs(dx) {
                    positions.append(GridPosition(x: start.x + stepX * i, y: start.y))
                }
            } else {
                positions.append(start)
            }
            if dy != 0 {
                let stepY = dy > 0 ? 1 : -1
                let startY = dx != 0 ? 1 : 1
                for i in startY...abs(dy) {
                    positions.append(GridPosition(x: end.x, y: start.y + stepY * i))
                }
            }

        case .vFirst:
            // Vertical segment first, then horizontal
            if dy != 0 {
                let stepY = dy > 0 ? 1 : -1
                for i in 0...abs(dy) {
                    positions.append(GridPosition(x: start.x, y: start.y + stepY * i))
                }
            } else {
                positions.append(start)
            }
            if dx != 0 {
                let stepX = dx > 0 ? 1 : -1
                let startX = dy != 0 ? 1 : 1
                for i in startX...abs(dx) {
                    positions.append(GridPosition(x: start.x + stepX * i, y: end.y))
                }
            }
        }

        return GameplayDragDrawPlanner.assignDirections(to: positions)
    }
}
