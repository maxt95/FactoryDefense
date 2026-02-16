import Foundation

public enum ContentValidationError: Error, Equatable, Sendable {
    case missingReference(owner: String, reference: String)
    case circularRecipeDependency([String])
    case invalidWaveComposition(waveIndex: Int, reason: String)
    case invalidWaveConfig(reason: String)
    case unreachableTechNode(String)
    case invalidBoard(reason: String)
    case invalidHQ(reason: String)
    case invalidDifficulty(reason: String)
    case invalidBuilding(reason: String)
}

public struct ContentValidator {
    public init() {}

    public func validate(bundle: GameContentBundle) -> [ContentValidationError] {
        var errors: [ContentValidationError] = []
        errors += validateReferences(bundle: bundle)
        errors += validateEnemies(bundle: bundle)
        errors += validateWaves(bundle: bundle)
        errors += validateRecipeCycles(bundle: bundle)
        errors += validateTechReachability(bundle: bundle)
        errors += validateBoard(bundle.board)
        errors += validateHQ(bundle.hq, itemIDs: bundle.itemIDs)
        errors += validateDifficulty(bundle.difficulty)
        errors += validateBuildings(bundle.buildings, itemIDs: bundle.itemIDs)
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

        for wave in bundle.waveContent.handAuthoredWaves {
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

    private func validateEnemies(bundle: GameContentBundle) -> [ContentValidationError] {
        var errors: [ContentValidationError] = []
        for enemy in bundle.enemies {
            if enemy.health <= 0 {
                errors.append(.invalidWaveConfig(reason: "enemy:\(enemy.id): health must be positive"))
            }
            if enemy.speed <= 0 {
                errors.append(.invalidWaveConfig(reason: "enemy:\(enemy.id): speed must be positive"))
            }
            if enemy.threatCost <= 0 {
                errors.append(.invalidWaveConfig(reason: "enemy:\(enemy.id): threatCost must be positive"))
            }
            if enemy.baseDamage <= 0 {
                errors.append(.invalidWaveConfig(reason: "enemy:\(enemy.id): baseDamage must be positive"))
            }
            if enemy.minBudgetToSpawn < 0 {
                errors.append(.invalidWaveConfig(reason: "enemy:\(enemy.id): minBudgetToSpawn cannot be negative"))
            }
            if let multiplier = enemy.wallDamageMultiplier, multiplier <= 0 {
                errors.append(.invalidWaveConfig(reason: "enemy:\(enemy.id): wallDamageMultiplier must be positive"))
            }
        }
        return errors
    }

    private func validateWaves(bundle: GameContentBundle) -> [ContentValidationError] {
        var errors: [ContentValidationError] = []
        let enemyByID = Dictionary(uniqueKeysWithValues: bundle.enemies.map { ($0.id, $0) })
        let waves = bundle.waveContent.handAuthoredWaves.sorted { $0.index < $1.index }

        if let first = waves.first, first.index != 1 {
            errors.append(.invalidWaveConfig(reason: "hand-authored waves must start at index 1"))
        }

        for (offset, wave) in waves.enumerated() {
            let expectedIndex = offset + 1
            if wave.index != expectedIndex {
                errors.append(.invalidWaveConfig(reason: "hand-authored waves must be contiguous; expected \(expectedIndex), got \(wave.index)"))
            }
        }

        for wave in waves {
            if wave.composition.isEmpty {
                errors.append(.invalidWaveComposition(waveIndex: wave.index, reason: "empty composition"))
                continue
            }

            var totalThreat = 0
            for group in wave.composition {
                if group.count <= 0 {
                    errors.append(.invalidWaveComposition(waveIndex: wave.index, reason: "enemy group count must be positive"))
                }
                guard let enemy = enemyByID[group.enemyID] else {
                    continue
                }
                if group.enemyID == "artillery_bug" {
                    errors.append(.invalidWaveComposition(waveIndex: wave.index, reason: "artillery_bug is deferred for v1"))
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

        let config = bundle.waveContent.proceduralConfig
        if config.budgetFormula.base <= 0 {
            errors.append(.invalidWaveConfig(reason: "procedural budget formula base must be positive"))
        }
        if config.budgetFormula.linear < 0 {
            errors.append(.invalidWaveConfig(reason: "procedural budget formula linear cannot be negative"))
        }
        if config.budgetFormula.quadratic <= 0 {
            errors.append(.invalidWaveConfig(reason: "procedural budget formula quadratic must be positive"))
        }
        if !(0...1).contains(config.swarmlingReserveRatio) {
            errors.append(.invalidWaveConfig(reason: "swarmlingReserveRatio must be within 0...1"))
        }
        if config.difficultyMultipliers.easy <= 0 || config.difficultyMultipliers.normal <= 0 || config.difficultyMultipliers.hard <= 0 {
            errors.append(.invalidWaveConfig(reason: "all procedural difficulty multipliers must be positive"))
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

    private func validateHQ(_ hq: HQDef, itemIDs: Set<ItemID>) -> [ContentValidationError] {
        var errors: [ContentValidationError] = []

        if hq.health <= 0 {
            errors.append(.invalidHQ(reason: "hq health must be positive"))
        }
        if hq.storageCapacity <= 0 {
            errors.append(.invalidHQ(reason: "hq storageCapacity must be positive"))
        }
        if hq.footprint.width != 2 || hq.footprint.height != 2 {
            errors.append(.invalidHQ(reason: "hq footprint must be 2x2"))
        }

        let resourcesByDifficulty: [(DifficultyID, [ItemID: Int])] = [
            (.easy, hq.startingResources.easy),
            (.normal, hq.startingResources.normal),
            (.hard, hq.startingResources.hard)
        ]
        for (difficulty, resources) in resourcesByDifficulty {
            for (itemID, quantity) in resources {
                if !itemIDs.contains(itemID) {
                    errors.append(.invalidHQ(reason: "starting resource item '\(itemID)' is missing for \(difficulty.rawValue)"))
                }
                if quantity < 0 {
                    errors.append(.invalidHQ(reason: "starting resource quantity for '\(itemID)' must be non-negative"))
                }
            }
        }

        return errors
    }

    private func validateDifficulty(_ difficulty: DifficultyConfigDef) -> [ContentValidationError] {
        var errors: [ContentValidationError] = []

        let valuesByLabel: [(String, DifficultyDef)] = [
            ("easy", difficulty.easy),
            ("normal", difficulty.normal),
            ("hard", difficulty.hard)
        ]

        for (label, value) in valuesByLabel {
            if value.gracePeriodSeconds <= 0 {
                errors.append(.invalidDifficulty(reason: "\(label): gracePeriodSeconds must be positive"))
            }
            if value.interWaveGapBase <= 0 {
                errors.append(.invalidDifficulty(reason: "\(label): interWaveGapBase must be positive"))
            }
            if value.interWaveGapFloor <= 0 {
                errors.append(.invalidDifficulty(reason: "\(label): interWaveGapFloor must be positive"))
            }
            if value.interWaveGapFloor > value.interWaveGapBase {
                errors.append(.invalidDifficulty(reason: "\(label): interWaveGapFloor cannot exceed interWaveGapBase"))
            }
            if value.gapCompressionPerWave < 0 {
                errors.append(.invalidDifficulty(reason: "\(label): gapCompressionPerWave must be non-negative"))
            }
            if value.trickleIntervalSeconds <= 0 {
                errors.append(.invalidDifficulty(reason: "\(label): trickleIntervalSeconds must be positive"))
            }
            if value.trickleSize.count != 2 {
                errors.append(.invalidDifficulty(reason: "\(label): trickleSize must contain [min,max]"))
            } else {
                let minSize = value.trickleSize[0]
                let maxSize = value.trickleSize[1]
                if minSize <= 0 || maxSize <= 0 {
                    errors.append(.invalidDifficulty(reason: "\(label): trickleSize values must be positive"))
                }
                if minSize > maxSize {
                    errors.append(.invalidDifficulty(reason: "\(label): trickleSize min cannot exceed max"))
                }
            }
            if value.waveBudgetMultiplier <= 0 {
                errors.append(.invalidDifficulty(reason: "\(label): waveBudgetMultiplier must be positive"))
            }
        }

        return errors
    }

    private func validateBuildings(_ buildings: [BuildingDef], itemIDs: Set<ItemID>) -> [ContentValidationError] {
        var errors: [ContentValidationError] = []

        if buildings.isEmpty {
            errors.append(.invalidBuilding(reason: "buildings.json must define at least one building"))
            return errors
        }

        let requiredBuildingIDs: Set<String> = [
            "wall",
            "turretMount",
            "miner",
            "smelter",
            "assembler",
            "ammoModule",
            "powerPlant",
            "conveyor",
            "splitter",
            "merger",
            "storage"
        ]
        let providedIDs = Set(buildings.map(\.id))
        let missingIDs = requiredBuildingIDs.subtracting(providedIDs).sorted()
        for id in missingIDs {
            errors.append(.invalidBuilding(reason: "missing canonical building definition '\(id)'"))
        }

        for building in buildings {
            if building.footprint.width <= 0 || building.footprint.height <= 0 {
                errors.append(.invalidBuilding(reason: "\(building.id): footprint must be positive"))
            }
            if building.ports.isEmpty {
                errors.append(.invalidBuilding(reason: "\(building.id): must define at least one directional port"))
            }
            if building.id == "powerPlant",
               (building.footprint.width != 1 || building.footprint.height != 1) {
                errors.append(.invalidBuilding(reason: "powerPlant footprint must be 1x1"))
            }
            if building.id == "storage",
               (building.footprint.width != 1 || building.footprint.height != 1) {
                errors.append(.invalidBuilding(reason: "storage footprint must be 1x1"))
            }
            if building.id == "storage", building.powerDraw != 0 {
                errors.append(.invalidBuilding(reason: "storage powerDraw must be 0"))
            }

            let portIDs = Set(building.ports.map(\.id))
            if portIDs.count != building.ports.count {
                errors.append(.invalidBuilding(reason: "\(building.id): port ids must be unique"))
            }
            for port in building.ports {
                if port.bufferCapacity <= 0 {
                    errors.append(.invalidBuilding(reason: "\(building.id):\(port.id): bufferCapacity must be positive"))
                }
                if case let .allow(allowSet) = port.filter {
                    if allowSet.isEmpty {
                        errors.append(.invalidBuilding(reason: "\(building.id):\(port.id): allow filter cannot be empty"))
                    }
                    for itemID in allowSet where !itemIDs.contains(itemID) {
                        errors.append(.invalidBuilding(reason: "\(building.id):\(port.id): unknown filtered item '\(itemID)'"))
                    }
                }
            }
        }

        return errors
    }
}
