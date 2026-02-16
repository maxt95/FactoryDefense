import Foundation

public enum ContentValidationError: Error, Equatable, Sendable {
    case missingReference(owner: String, reference: String)
    case circularRecipeDependency([String])
    case invalidWaveComposition(waveIndex: Int, reason: String)
    case unreachableTechNode(String)
    case invalidBoard(reason: String)
}

public struct ContentValidator {
    public init() {}

    public func validate(bundle: GameContentBundle) -> [ContentValidationError] {
        var errors: [ContentValidationError] = []
        errors += validateReferences(bundle: bundle)
        errors += validateWaves(bundle: bundle)
        errors += validateRecipeCycles(bundle: bundle)
        errors += validateTechReachability(bundle: bundle)
        errors += validateBoard(bundle.board)
        return errors
    }

    private func validateReferences(bundle: GameContentBundle) -> [ContentValidationError] {
        var errors: [ContentValidationError] = []

        for recipe in bundle.recipes {
            for input in recipe.inputs where !bundle.itemIDs.contains(input.itemID) {
                errors.append(.missingReference(owner: "recipe:\(recipe.id)", reference: input.itemID))
            }
            for output in recipe.outputs where !bundle.itemIDs.contains(output.itemID) {
                errors.append(.missingReference(owner: "recipe:\(recipe.id)", reference: output.itemID))
            }
        }

        for wave in bundle.waves {
            for group in wave.composition where !bundle.enemyIDs.contains(group.enemyID) {
                errors.append(.missingReference(owner: "wave:\(wave.index)", reference: group.enemyID))
            }
        }

        for node in bundle.techNodes {
            for prereq in node.prerequisites where !bundle.techNodeIDs.contains(prereq) {
                errors.append(.missingReference(owner: "tech:\(node.id)", reference: prereq))
            }
            for unlock in node.unlocks where !bundle.techNodeIDs.contains(unlock) {
                errors.append(.missingReference(owner: "tech:\(node.id)", reference: unlock))
            }
            for cost in node.costs where !bundle.itemIDs.contains(cost.itemID) {
                errors.append(.missingReference(owner: "tech:\(node.id)", reference: cost.itemID))
            }
        }

        return errors
    }

    private func validateWaves(bundle: GameContentBundle) -> [ContentValidationError] {
        var errors: [ContentValidationError] = []
        let enemyByID = Dictionary(uniqueKeysWithValues: bundle.enemies.map { ($0.id, $0) })

        for wave in bundle.waves {
            if wave.composition.isEmpty {
                errors.append(.invalidWaveComposition(waveIndex: wave.index, reason: "empty composition"))
                continue
            }

            var totalThreat = 0
            for group in wave.composition {
                guard let enemy = enemyByID[group.enemyID] else {
                    continue
                }
                totalThreat += enemy.threatCost * group.count
            }

            if totalThreat > wave.spawnBudget {
                errors.append(
                    .invalidWaveComposition(
                        waveIndex: wave.index,
                        reason: "threat \(totalThreat) exceeds budget \(wave.spawnBudget)"
                    )
                )
            }
        }

        return errors
    }

    private func validateRecipeCycles(bundle: GameContentBundle) -> [ContentValidationError] {
        var producersByItem: [ItemID: Set<String>] = [:]
        for recipe in bundle.recipes {
            for output in recipe.outputs {
                producersByItem[output.itemID, default: []].insert(recipe.id)
            }
        }

        var graph: [String: Set<String>] = [:]
        for recipe in bundle.recipes {
            var dependencies: Set<String> = []
            for input in recipe.inputs {
                let producers = producersByItem[input.itemID] ?? []
                for producer in producers where producer != recipe.id {
                    dependencies.insert(producer)
                }
            }
            graph[recipe.id] = dependencies
        }

        enum VisitState {
            case unvisited
            case visiting
            case visited
        }

        var state: [String: VisitState] = [:]
        for recipe in bundle.recipes {
            state[recipe.id] = .unvisited
        }

        var stack: [String] = []

        func dfs(_ node: String) -> [String]? {
            state[node] = .visiting
            stack.append(node)

            for neighbor in graph[node, default: []] {
                switch state[neighbor] ?? .unvisited {
                case .unvisited:
                    if let cycle = dfs(neighbor) {
                        return cycle
                    }
                case .visiting:
                    if let index = stack.firstIndex(of: neighbor) {
                        return Array(stack[index...])
                    }
                case .visited:
                    break
                }
            }

            _ = stack.popLast()
            state[node] = .visited
            return nil
        }

        for node in graph.keys where state[node] == .unvisited {
            if let cycle = dfs(node), !cycle.isEmpty {
                return [.circularRecipeDependency(cycle)]
            }
        }

        return []
    }

    private func validateTechReachability(bundle: GameContentBundle) -> [ContentValidationError] {
        let byID = Dictionary(uniqueKeysWithValues: bundle.techNodes.map { ($0.id, $0) })
        let roots = bundle.techNodes.filter { $0.prerequisites.isEmpty }

        var visited: Set<UnlockID> = Set(roots.map(\.id))
        var queue: [UnlockID] = Array(visited)

        while let current = queue.first {
            queue.removeFirst()
            guard let node = byID[current] else { continue }
            for unlocked in node.unlocks where !visited.contains(unlocked) {
                visited.insert(unlocked)
                queue.append(unlocked)
            }
        }

        return bundle.techNodes
            .map(\.id)
            .filter { !visited.contains($0) }
            .map(ContentValidationError.unreachableTechNode)
    }

    private func validateBoard(_ board: BoardDef) -> [ContentValidationError] {
        var errors: [ContentValidationError] = []

        if board.width <= 0 || board.height <= 0 {
            errors.append(.invalidBoard(reason: "board dimensions must be positive"))
            return errors
        }

        func isInBounds(_ point: BoardPointDef) -> Bool {
            point.x >= 0 && point.x < board.width && point.y >= 0 && point.y < board.height
        }

        if !isInBounds(board.basePosition) {
            errors.append(.invalidBoard(reason: "base position is out of bounds"))
        }

        if board.spawnEdgeX < 0 || board.spawnEdgeX >= board.width {
            errors.append(.invalidBoard(reason: "spawnEdgeX is out of bounds"))
        }

        if board.spawnYMin < 0 || board.spawnYMax >= board.height || board.spawnYMin > board.spawnYMax {
            errors.append(.invalidBoard(reason: "spawn Y range is invalid"))
        }

        for blocked in board.blockedCells where !isInBounds(blocked) {
            errors.append(.invalidBoard(reason: "blocked cell (\(blocked.x),\(blocked.y)) is out of bounds"))
        }

        for restricted in board.restrictedCells where !isInBounds(restricted) {
            errors.append(.invalidBoard(reason: "restricted cell (\(restricted.x),\(restricted.y)) is out of bounds"))
        }

        for ramp in board.ramps where !isInBounds(ramp.position) {
            errors.append(.invalidBoard(reason: "ramp cell (\(ramp.position.x),\(ramp.position.y)) is out of bounds"))
        }

        let blocked = Set(board.blockedCells.map { "\($0.x):\($0.y)" })
        let restricted = Set(board.restrictedCells.map { "\($0.x):\($0.y)" })
        if blocked.contains("\(board.basePosition.x):\(board.basePosition.y)") {
            errors.append(.invalidBoard(reason: "base position cannot be blocked"))
        }

        if board.spawnYMin <= board.spawnYMax {
            for y in board.spawnYMin...board.spawnYMax {
                if blocked.contains("\(board.spawnEdgeX):\(y)") {
                    errors.append(.invalidBoard(reason: "spawn edge cell (\(board.spawnEdgeX),\(y)) cannot be blocked"))
                }
            }
        }

        for ramp in board.ramps where restricted.contains("\(ramp.position.x):\(ramp.position.y)") {
            errors.append(.invalidBoard(reason: "ramp cell (\(ramp.position.x),\(ramp.position.y)) cannot also be restricted"))
        }

        return errors
    }
}
