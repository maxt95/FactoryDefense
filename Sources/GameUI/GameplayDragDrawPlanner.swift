import GameSimulation

public struct GameplayDragDrawPlanner: Sendable {
    public init() {}

    public func supportsDragDraw(for structure: StructureType) -> Bool {
        switch structure {
        case .conveyor, .wall:
            return true
        default:
            return false
        }
    }

    public func dominantAxisPath(from start: GridPosition, to end: GridPosition) -> [GridPosition] {
        let dx = end.x - start.x
        let dy = end.y - start.y

        if abs(dx) >= abs(dy) {
            return linePath(
                origin: start,
                steps: abs(dx),
                deltaX: dx.signum(),
                deltaY: 0
            )
        }

        return linePath(
            origin: start,
            steps: abs(dy),
            deltaX: 0,
            deltaY: dy.signum()
        )
    }

    private func linePath(origin: GridPosition, steps: Int, deltaX: Int, deltaY: Int) -> [GridPosition] {
        guard steps > 0 else { return [origin] }
        var points: [GridPosition] = []
        points.reserveCapacity(steps + 1)
        for step in 0...steps {
            points.append(
                origin.translated(
                    byX: deltaX * step,
                    byY: deltaY * step
                )
            )
        }
        return points
    }
}
