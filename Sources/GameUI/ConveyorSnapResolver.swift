import GameSimulation

/// Resolves auto-orientation for a new conveyor placement based on adjacent neighbors.
/// Pure function — no simulation dependency. Used in build-mode preview to suggest
/// input/output directions that connect with existing infrastructure.
public struct ConveyorSnapResolver: Sendable {
    public init() {}

    public struct SnapResult: Sendable, Hashable {
        public var inputDirection: CardinalDirection
        public var outputDirection: CardinalDirection
        public var hasConnection: Bool
    }

    /// Resolves the best orientation for a conveyor at `position` based on neighbors.
    ///
    /// - Parameters:
    ///   - position: The grid position where the conveyor will be placed.
    ///   - entities: The entity store to look up neighbors.
    ///   - conveyorIO: Conveyor I/O configurations for existing conveyors.
    ///   - fallbackOutput: Direction to use if no neighbor context (player's current rotation).
    /// - Returns: Resolved input/output directions.
    public func resolve(
        at position: GridPosition,
        entities: EntityStore,
        conveyorIO: [EntityID: ConveyorIOConfig],
        fallbackOutput: CardinalDirection = .east
    ) -> SnapResult {
        var candidates: [SnapCandidate] = []

        for direction in CardinalDirection.allCases {
            let neighborPos = position.translated(by: direction)
            guard let neighbor = entities.selectableEntity(at: neighborPos) else { continue }

            switch neighbor.structureType {
            case .conveyor:
                let io = conveyorIO[neighbor.id]
                    ?? ConveyorIOConfig.default(for: neighbor.rotation)
                evaluateConveyorNeighbor(
                    neighborIO: io,
                    neighborDirection: direction,
                    candidates: &candidates
                )

            case .splitter:
                evaluateSplitterNeighbor(
                    splitter: neighbor,
                    directionFromPlacement: direction,
                    candidates: &candidates
                )

            case .merger:
                evaluateMergerNeighbor(
                    merger: neighbor,
                    directionFromPlacement: direction,
                    candidates: &candidates
                )

            default:
                break
            }
        }

        // Pick best candidate
        if let best = candidates.sorted(by: { $0.priority > $1.priority }).first {
            return SnapResult(
                inputDirection: best.input,
                outputDirection: best.output,
                hasConnection: true
            )
        }

        // No neighbors — use fallback
        return SnapResult(
            inputDirection: fallbackOutput.opposite,
            outputDirection: fallbackOutput,
            hasConnection: false
        )
    }

    /// Checks if a proposed conveyor I/O at `position` forms a valid connection with an adjacent entity.
    public func isPortCompatible(
        conveyorInput: CardinalDirection,
        conveyorOutput: CardinalDirection,
        neighborEntity: Entity,
        neighborDirection: CardinalDirection,
        conveyorIO: [EntityID: ConveyorIOConfig]
    ) -> Bool {
        switch neighborEntity.structureType {
        case .conveyor:
            let io = conveyorIO[neighborEntity.id]
                ?? ConveyorIOConfig.default(for: neighborEntity.rotation)
            // Our output faces neighbor, and neighbor's input faces us
            if conveyorOutput == neighborDirection && io.inputDirection == neighborDirection.opposite {
                return true
            }
            // Neighbor's output faces us, and our input faces neighbor
            if io.outputDirection == neighborDirection.opposite && conveyorInput == neighborDirection {
                return true
            }
            return false

        case .splitter:
            let facing = neighborEntity.rotation.direction
            // Splitter input is from behind (facing.opposite)
            let splitterInputDir = facing.opposite
            // Splitter outputs are to left and right of facing
            let splitterOutputLeft = facing.left
            let splitterOutputRight = facing.right

            // Our output feeds into splitter's input port
            if conveyorOutput == neighborDirection {
                let splitterInputSide = neighborDirection.opposite
                if splitterInputSide == splitterInputDir { return true }
            }
            // Splitter output feeds into our input
            if conveyorInput == neighborDirection {
                let splitterOutputSide = neighborDirection.opposite
                if splitterOutputSide == splitterOutputLeft || splitterOutputSide == splitterOutputRight {
                    return true
                }
            }
            return false

        case .merger:
            let facing = neighborEntity.rotation.direction
            // Merger output is forward (facing)
            // Merger inputs are from left and right
            let mergerInputLeft = facing.left
            let mergerInputRight = facing.right

            // Our output feeds into merger's input port
            if conveyorOutput == neighborDirection {
                let mergerInputSide = neighborDirection.opposite
                if mergerInputSide == mergerInputLeft || mergerInputSide == mergerInputRight {
                    return true
                }
            }
            // Merger output feeds into our input
            if conveyorInput == neighborDirection {
                let mergerOutputSide = neighborDirection.opposite
                if mergerOutputSide == facing { return true }
            }
            return false

        default:
            return false
        }
    }

    // MARK: - Private

    private struct SnapCandidate {
        var input: CardinalDirection
        var output: CardinalDirection
        var priority: Int // Higher = better
    }

    private func evaluateConveyorNeighbor(
        neighborIO: ConveyorIOConfig,
        neighborDirection: CardinalDirection,
        candidates: inout [SnapCandidate]
    ) {
        // Case 1: Neighbor's output points toward us → we continue the run
        // Neighbor output == opposite of neighborDirection means it outputs toward our position
        if neighborIO.outputDirection == neighborDirection.opposite {
            // Continue the run: our input faces the neighbor, output continues forward
            candidates.append(SnapCandidate(
                input: neighborDirection,
                output: neighborDirection.opposite,
                priority: 10 // Highest: continuing a run
            ))
        }

        // Case 2: Neighbor's input points toward us → we feed into it
        if neighborIO.inputDirection == neighborDirection.opposite {
            // Feed into neighbor: our output faces the neighbor
            candidates.append(SnapCandidate(
                input: neighborDirection.opposite,
                output: neighborDirection,
                priority: 8
            ))
        }
    }

    private func evaluateSplitterNeighbor(
        splitter: Entity,
        directionFromPlacement: CardinalDirection,
        candidates: inout [SnapCandidate]
    ) {
        let facing = splitter.rotation.direction
        let splitterInputDir = facing.opposite
        let splitterOutputLeft = facing.left
        let splitterOutputRight = facing.right

        // The side of the splitter we're adjacent to
        let adjacentSide = directionFromPlacement.opposite

        // If we're adjacent to the splitter's input side, our output should face the splitter
        if adjacentSide == splitterInputDir {
            candidates.append(SnapCandidate(
                input: directionFromPlacement.opposite,
                output: directionFromPlacement,
                priority: 9
            ))
        }

        // If we're adjacent to a splitter output side, our input should face the splitter
        if adjacentSide == splitterOutputLeft || adjacentSide == splitterOutputRight {
            candidates.append(SnapCandidate(
                input: directionFromPlacement,
                output: directionFromPlacement.opposite,
                priority: 9
            ))
        }
    }

    private func evaluateMergerNeighbor(
        merger: Entity,
        directionFromPlacement: CardinalDirection,
        candidates: inout [SnapCandidate]
    ) {
        let facing = merger.rotation.direction
        let mergerOutputDir = facing
        let mergerInputLeft = facing.left
        let mergerInputRight = facing.right

        let adjacentSide = directionFromPlacement.opposite

        // If we're adjacent to the merger's output, our input should face the merger
        if adjacentSide == mergerOutputDir {
            candidates.append(SnapCandidate(
                input: directionFromPlacement,
                output: directionFromPlacement.opposite,
                priority: 9
            ))
        }

        // If we're adjacent to a merger input side, our output should face the merger
        if adjacentSide == mergerInputLeft || adjacentSide == mergerInputRight {
            candidates.append(SnapCandidate(
                input: directionFromPlacement.opposite,
                output: directionFromPlacement,
                priority: 9
            ))
        }
    }
}
