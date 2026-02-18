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

    /// Straight-line path along the dominant axis. Used for walls and as a fallback.
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

    /// Smart path for conveyors that tracks actual cell sequence and auto-inserts corners.
    /// Pipeline: dedup → interpolate gaps → remove zigzag spikes → assign I/O directions.
    public func smartPath(cellSequence: [GridPosition]) -> [DragPreviewCell] {
        let deduped = deduplicateAndRubberBand(cellSequence)
        let interpolated = ensureCardinalAdjacency(deduped)
        let cleaned = removeZigzags(interpolated)
        return Self.assignDirections(to: cleaned)
    }

    /// Assigns input/output directions to a sequence of grid positions.
    /// Shared between smartPath and BeltPlannerState.
    public static func assignDirections(to positions: [GridPosition]) -> [DragPreviewCell] {
        guard !positions.isEmpty else { return [] }
        guard positions.count > 1 else {
            return [DragPreviewCell(
                position: positions[0],
                inputDirection: .west,
                outputDirection: .east
            )]
        }

        var cells: [DragPreviewCell] = []
        cells.reserveCapacity(positions.count)

        for i in 0..<positions.count {
            let current = positions[i]
            let inputDir: CardinalDirection
            let outputDir: CardinalDirection

            if i == 0 {
                // First cell: output toward next, input from opposite
                let dirToNext = cardinalDirection(from: current, to: positions[i + 1]) ?? .east
                outputDir = dirToNext
                inputDir = dirToNext.opposite
            } else if i == positions.count - 1 {
                // Last cell: input from previous direction, output continues forward
                let dirFromPrev = cardinalDirection(from: positions[i - 1], to: current) ?? .east
                inputDir = dirFromPrev.opposite
                outputDir = dirFromPrev
            } else {
                // Middle cell: input from previous, output toward next
                let dirFromPrev = cardinalDirection(from: positions[i - 1], to: current) ?? .east
                let dirToNext = cardinalDirection(from: current, to: positions[i + 1]) ?? .east
                inputDir = dirFromPrev.opposite
                outputDir = dirToNext
            }

            let isCorner = inputDir != outputDir.opposite
            cells.append(DragPreviewCell(
                position: current,
                inputDirection: inputDir,
                outputDirection: outputDir,
                isCorner: isCorner
            ))
        }
        return cells
    }

    // MARK: - Private

    /// Fills in gaps between non-cardinally-adjacent cells. When the mouse moves
    /// fast enough to skip cells (diagonal jump), we interpolate intermediate cells
    /// by preferring the axis that continues the previous movement direction.
    private func ensureCardinalAdjacency(_ positions: [GridPosition]) -> [GridPosition] {
        guard positions.count >= 2 else { return positions }

        var result: [GridPosition] = [positions[0]]
        result.reserveCapacity(positions.count)

        for i in 1..<positions.count {
            let prev = result.last!
            let next = positions[i]
            let dx = next.x - prev.x
            let dy = next.y - prev.y

            // Already cardinally adjacent (or same cell)
            if (abs(dx) + abs(dy)) <= 1 {
                if prev != next {
                    result.append(next)
                }
                continue
            }

            // Need interpolation. Determine which axis to traverse first
            // by looking at the previous movement direction to maintain continuity.
            let prevDir: CardinalDirection?
            if result.count >= 2 {
                prevDir = cardinalDirection(from: result[result.count - 2], to: prev)
            } else {
                prevDir = nil
            }

            let xFirst: Bool
            if let dir = prevDir {
                // Continue on the same axis as the previous step
                xFirst = (dir == .east || dir == .west)
            } else {
                // No previous direction — prefer the longer axis
                xFirst = abs(dx) >= abs(dy)
            }

            if xFirst {
                // Walk X first, then Y
                let stepX = dx == 0 ? 0 : (dx > 0 ? 1 : -1)
                let stepY = dy == 0 ? 0 : (dy > 0 ? 1 : -1)
                var cx = prev.x
                var cy = prev.y
                while cx != next.x {
                    cx += stepX
                    result.append(GridPosition(x: cx, y: cy))
                }
                while cy != next.y {
                    cy += stepY
                    result.append(GridPosition(x: cx, y: cy))
                }
            } else {
                // Walk Y first, then X
                let stepX = dx == 0 ? 0 : (dx > 0 ? 1 : -1)
                let stepY = dy == 0 ? 0 : (dy > 0 ? 1 : -1)
                var cx = prev.x
                var cy = prev.y
                while cy != next.y {
                    cy += stepY
                    result.append(GridPosition(x: cx, y: cy))
                }
                while cx != next.x {
                    cx += stepX
                    result.append(GridPosition(x: cx, y: cy))
                }
            }
        }
        return result
    }

    /// Removes zigzag spikes caused by cursor jitter. A zigzag is 4 consecutive
    /// cells A-B-C-D where A and D are exactly 1 cardinal step apart — meaning
    /// B and C are a needless 2-cell perpendicular detour. Collapse to A-D.
    /// Also removes 1-cell dead-end spikes where removing the middle cell
    /// leaves its neighbors still adjacent.
    /// Repeats until stable since removing one zigzag can reveal another.
    private func removeZigzags(_ positions: [GridPosition]) -> [GridPosition] {
        var result = positions
        var changed = true

        while changed {
            changed = false

            // Pass 1: Remove 2-cell zigzags (A-B-C-D where A→D is 1 cardinal step)
            var i = 0
            var cleaned: [GridPosition] = []
            cleaned.reserveCapacity(result.count)

            while i < result.count {
                if i + 3 < result.count {
                    let a = result[i]
                    let d = result[i + 3]
                    let dist = abs(d.x - a.x) + abs(d.y - a.y)
                    if dist == 1 {
                        // A and D are 1 step apart — B,C are a zigzag detour
                        cleaned.append(a)
                        i += 3 // skip B and C, loop will append D next
                        changed = true
                        continue
                    }
                }
                cleaned.append(result[i])
                i += 1
            }
            result = cleaned

            // Pass 2: Remove 1-cell spikes where a single cell juts perpendicular
            // and immediately returns. Pattern: 3 cells A-B-C where A and C are the
            // same position or where direction A→B reverses as B→C (U-turn).
            cleaned = []
            cleaned.reserveCapacity(result.count)
            i = 0
            while i < result.count {
                if i > 0 && i + 1 < result.count {
                    let prev = result[i - 1]
                    let curr = result[i]
                    let next = result[i + 1]
                    if let d1 = cardinalDirection(from: prev, to: curr),
                       let d2 = cardinalDirection(from: curr, to: next),
                       d1 == d2.opposite {
                        // U-turn: skip this cell
                        changed = true
                        i += 1
                        continue
                    }
                }
                cleaned.append(result[i])
                i += 1
            }
            result = cleaned
        }

        return result
    }

    private func deduplicateAndRubberBand(_ sequence: [GridPosition]) -> [GridPosition] {
        var result: [GridPosition] = []
        var visited = Set<GridPosition>()

        for position in sequence {
            // Skip consecutive duplicates
            if position == result.last { continue }

            // Rubber-band: if we return to a visited cell, truncate back
            if let existingIndex = result.firstIndex(of: position) {
                // Remove everything after the existing occurrence
                let removed = result[(existingIndex + 1)...]
                for pos in removed {
                    visited.remove(pos)
                }
                result = Array(result[...existingIndex])
            } else {
                result.append(position)
                visited.insert(position)
            }
        }
        return result
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
