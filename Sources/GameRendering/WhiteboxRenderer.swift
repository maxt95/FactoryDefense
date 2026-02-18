import Foundation
import Metal
import GameSimulation

private struct WhiteboxUniforms {
    var viewportPixelWidth: UInt32
    var viewportPixelHeight: UInt32
    var viewWidthPoints: Float
    var viewHeightPoints: Float
    var drawableScaleX: Float
    var drawableScaleY: Float
    var boardWidth: UInt32
    var boardHeight: UInt32
    var baseX: Int32
    var baseY: Int32
    var spawnEdgeX: Int32
    var spawnYMin: Int32
    var spawnYMax: Int32
    var blockedCount: UInt32
    var restrictedCount: UInt32
    var rampCount: UInt32
    var structureCount: UInt32
    var entityCount: UInt32
    var turretOverlayCount: UInt32
    var pathSegmentCount: UInt32
    var wallFlowSegmentCount: UInt32
    var debugModeRaw: UInt32
    var highlightedX: Int32
    var highlightedY: Int32
    var highlightedPathCount: UInt32
    var highlightedAffordableCount: UInt32
    var highlightedStructureTypeRaw: UInt32
    var placementResultRaw: Int32
    var cameraPanX: Float
    var cameraPanY: Float
    var cameraZoom: Float
    var animationTick: Float
    var _padding0: UInt32
}

private struct WhiteboxPointShader {
    var x: Int32
    var y: Int32
    var _pad0: Int32 = 0
    var _pad1: Int32 = 0
}

private struct WhiteboxRampShader {
    var x: Int32
    var y: Int32
    var elevation: Int32
    var _pad0: Int32 = 0
}

private struct WhiteboxTurretOverlayShader {
    var x: Int32
    var y: Int32
    var rangeTiles: Float
    var _pad0: Float = 0
}

private struct WhiteboxPathSegmentShader {
    var fromX: Int32
    var fromY: Int32
    var toX: Int32
    var toY: Int32
}

private struct WhiteboxWallFlowSegmentShader {
    var fromX: Int32
    var fromY: Int32
    var toX: Int32
    var toY: Int32
    var intensity: Float
    var ammoTypeRaw: UInt32
    var networkID: UInt32
    var phaseOffset: Float
    var phaseLength: Float
    var _pad0: UInt32 = 0
}

private struct DebugOverlayPayload {
    var debugModeRaw: UInt32
    var turretOverlays: [WhiteboxTurretOverlayShader]
    var pathSegments: [WhiteboxPathSegmentShader]
    var wallFlowSegments: [WhiteboxWallFlowSegmentShader]
}

public final class WhiteboxRenderer {
    private let sceneBuilder = WhiteboxSceneBuilder()
    private var pipelineState: MTLComputePipelineState?
    private var pipelineDeviceID: ObjectIdentifier?
    private var hasLoggedPipelineIssue = false
    private var lastAnimationSampleTick: UInt64?
    private var lastAnimationSampleTime: TimeInterval?
    private let assumedSimulationTickDurationSeconds = 1.0 / 20.0

    public init() {}

    public func encode(context: RenderContext, commandBuffer: MTLCommandBuffer) {
        guard let drawableTexture = context.currentDrawable?.texture else { return }
        guard let pipelineState = preparePipeline(device: context.device) else { return }

        let scene = sceneBuilder.build(from: context.worldState)
        let debugOverlays = buildDebugOverlays(context: context)

        var uniforms = WhiteboxUniforms(
            viewportPixelWidth: UInt32(max(1, Int(context.drawableSize.width))),
            viewportPixelHeight: UInt32(max(1, Int(context.drawableSize.height))),
            viewWidthPoints: Float(max(1, context.viewSizePoints.width)),
            viewHeightPoints: Float(max(1, context.viewSizePoints.height)),
            drawableScaleX: max(0.001, context.drawableScaleX),
            drawableScaleY: max(0.001, context.drawableScaleY),
            boardWidth: UInt32(max(1, context.worldState.board.width)),
            boardHeight: UInt32(max(1, context.worldState.board.height)),
            baseX: Int32(context.worldState.board.basePosition.x),
            baseY: Int32(context.worldState.board.basePosition.y),
            spawnEdgeX: Int32(context.worldState.board.spawnEdgeX),
            spawnYMin: Int32(context.worldState.board.spawnYMin),
            spawnYMax: Int32(context.worldState.board.spawnYMax),
            blockedCount: UInt32(scene.blockedCells.count),
            restrictedCount: UInt32(scene.restrictedCells.count),
            rampCount: UInt32(scene.ramps.count),
            structureCount: 0,
            entityCount: 0,
            turretOverlayCount: UInt32(debugOverlays.turretOverlays.count),
            pathSegmentCount: UInt32(debugOverlays.pathSegments.count),
            wallFlowSegmentCount: UInt32(debugOverlays.wallFlowSegments.count),
            debugModeRaw: debugOverlays.debugModeRaw,
            highlightedX: Int32(context.highlightedCell?.x ?? -1),
            highlightedY: Int32(context.highlightedCell?.y ?? -1),
            highlightedPathCount: UInt32(context.highlightedPath.count),
            highlightedAffordableCount: UInt32(max(0, context.highlightedAffordableCount)),
            highlightedStructureTypeRaw: highlightedStructureTypeRaw(context.highlightedStructure),
            placementResultRaw: Int32(context.placementResult.rawValue),
            cameraPanX: context.cameraState.pan.x,
            cameraPanY: context.cameraState.pan.y,
            cameraZoom: context.cameraState.zoom,
            animationTick: interpolatedSimulationTick(currentTick: context.worldState.tick),
            _padding0: 0
        )

        let blockedBuffer = makePointBuffer(context.device, points: scene.blockedCells)
        let restrictedBuffer = makePointBuffer(context.device, points: scene.restrictedCells)
        let rampBuffer = makeRampBuffer(context.device, ramps: scene.ramps)
        let structureBuffer: MTLBuffer? = nil
        let entityBuffer: MTLBuffer? = nil
        let turretOverlayBuffer = makeTurretOverlayBuffer(context.device, overlays: debugOverlays.turretOverlays)
        let pathSegmentBuffer = makePathSegmentBuffer(context.device, segments: debugOverlays.pathSegments)
        let wallFlowSegmentBuffer = makeWallFlowSegmentBuffer(context.device, segments: debugOverlays.wallFlowSegments)
        let highlightedPathBuffer = makePointBuffer(
            context.device,
            points: context.highlightedPath.map { WhiteboxPoint(x: Int32($0.x), y: Int32($0.y)) }
        )

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "WhiteboxBoardCompute"
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(drawableTexture, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<WhiteboxUniforms>.stride, index: 0)
        encoder.setBuffer(blockedBuffer, offset: 0, index: 1)
        encoder.setBuffer(restrictedBuffer, offset: 0, index: 2)
        encoder.setBuffer(rampBuffer, offset: 0, index: 3)
        encoder.setBuffer(structureBuffer, offset: 0, index: 4)
        encoder.setBuffer(entityBuffer, offset: 0, index: 5)
        encoder.setBuffer(turretOverlayBuffer, offset: 0, index: 6)
        encoder.setBuffer(pathSegmentBuffer, offset: 0, index: 7)
        encoder.setBuffer(highlightedPathBuffer, offset: 0, index: 8)
        encoder.setBuffer(wallFlowSegmentBuffer, offset: 0, index: 9)

        let threadsPerThreadgroup = MTLSize(width: 8, height: 8, depth: 1)
        let threadgroups = MTLSize(
            width: (drawableTexture.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: (drawableTexture.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
    }

    private func preparePipeline(device: MTLDevice) -> MTLComputePipelineState? {
        let deviceID = ObjectIdentifier(device as AnyObject)
        if pipelineDeviceID == deviceID, let pipelineState {
            return pipelineState
        }

        do {
            let library = try device.makeDefaultLibrary(bundle: .module)
            guard let function = library.makeFunction(name: "whitebox_board") else {
                logPipelineIssue("Missing whitebox_board function in default Metal library.")
                return nil
            }
            let pipeline = try device.makeComputePipelineState(function: function)
            pipelineState = pipeline
            pipelineDeviceID = deviceID
            return pipeline
        } catch {
            logPipelineIssue("Failed to build whitebox pipeline: \(error.localizedDescription)")
            return nil
        }
    }

    private func logPipelineIssue(_ message: String) {
        guard !hasLoggedPipelineIssue else { return }
        hasLoggedPipelineIssue = true
        fputs("FactoryDefense WhiteboxRenderer: \(message)\n", stderr)
        RenderDiagnostics.post("Whitebox renderer issue: \(message)")
    }

    private func makePointBuffer(_ device: MTLDevice, points: [WhiteboxPoint]) -> MTLBuffer? {
        guard !points.isEmpty else { return nil }
        var payload = points.map { WhiteboxPointShader(x: $0.x, y: $0.y) }
        return device.makeBuffer(
            bytes: &payload,
            length: MemoryLayout<WhiteboxPointShader>.stride * payload.count
        )
    }

    private func makeRampBuffer(_ device: MTLDevice, ramps: [WhiteboxRampPoint]) -> MTLBuffer? {
        guard !ramps.isEmpty else { return nil }
        var payload = ramps.map { WhiteboxRampShader(x: $0.x, y: $0.y, elevation: $0.elevation) }
        return device.makeBuffer(
            bytes: &payload,
            length: MemoryLayout<WhiteboxRampShader>.stride * payload.count
        )
    }

    private func makeTurretOverlayBuffer(_ device: MTLDevice, overlays: [WhiteboxTurretOverlayShader]) -> MTLBuffer? {
        guard !overlays.isEmpty else { return nil }
        var payload = overlays
        return device.makeBuffer(
            bytes: &payload,
            length: MemoryLayout<WhiteboxTurretOverlayShader>.stride * payload.count
        )
    }

    private func makePathSegmentBuffer(_ device: MTLDevice, segments: [WhiteboxPathSegmentShader]) -> MTLBuffer? {
        guard !segments.isEmpty else { return nil }
        var payload = segments
        return device.makeBuffer(
            bytes: &payload,
            length: MemoryLayout<WhiteboxPathSegmentShader>.stride * payload.count
        )
    }

    private func makeWallFlowSegmentBuffer(_ device: MTLDevice, segments: [WhiteboxWallFlowSegmentShader]) -> MTLBuffer? {
        guard !segments.isEmpty else { return nil }
        var payload = segments
        return device.makeBuffer(
            bytes: &payload,
            length: MemoryLayout<WhiteboxWallFlowSegmentShader>.stride * payload.count
        )
    }

    private func interpolatedSimulationTick(currentTick: UInt64) -> Float {
        let now = ProcessInfo.processInfo.systemUptime
        if lastAnimationSampleTick == nil || lastAnimationSampleTime == nil {
            lastAnimationSampleTick = currentTick
            lastAnimationSampleTime = now
            return Float(currentTick)
        }

        if lastAnimationSampleTick != currentTick {
            lastAnimationSampleTick = currentTick
            lastAnimationSampleTime = now
            return Float(currentTick)
        }

        guard let sampleTime = lastAnimationSampleTime else {
            return Float(currentTick)
        }
        let elapsed = max(0.0, now - sampleTime)
        let clampedElapsed = min(assumedSimulationTickDurationSeconds, elapsed)
        let fraction = clampedElapsed / assumedSimulationTickDurationSeconds
        return Float(currentTick) + Float(fraction)
    }

    private func highlightedStructureTypeRaw(_ structure: StructureType?) -> UInt32 {
        guard let structure else { return 0 }
        return WhiteboxStructureTypeID(structureType: structure).rawValue
    }

    private func buildDebugOverlays(context: RenderContext) -> DebugOverlayPayload {
        let modeRaw = debugModeRaw(context.debugMode)
        let includeTurretRanges = modeRaw == 1 || modeRaw == 3
        let includeEnemyPaths = modeRaw == 2 || modeRaw == 3
        let includeWallAmmoFlow = modeRaw == 3 || modeRaw == 4

        let turretOverlays = includeTurretRanges
            ? buildTurretOverlays(world: context.worldState, maxCount: 256)
            : []
        let pathSegments = includeEnemyPaths
            ? buildEnemyPathSegments(world: context.worldState, maxSegmentCount: 2048)
            : []
        let wallFlowSegments = includeWallAmmoFlow
            ? buildWallFlowSegments(world: context.worldState, maxSegmentCount: 4096)
            : []

        return DebugOverlayPayload(
            debugModeRaw: modeRaw,
            turretOverlays: turretOverlays,
            pathSegments: pathSegments,
            wallFlowSegments: wallFlowSegments
        )
    }

    private func debugModeRaw(_ mode: DebugVisualizationMode) -> UInt32 {
        switch mode {
        case .turretRanges:
            return 1
        case .enemyPaths:
            return 2
        case .tactical:
            return 3
        case .wallAmmoFlow:
            return 4
        default:
            return 0
        }
    }

    private func buildWallFlowSegments(world: WorldState, maxSegmentCount: Int) -> [WhiteboxWallFlowSegmentShader] {
        guard maxSegmentCount > 0 else { return [] }
        guard !world.combat.wallNetworks.isEmpty else { return [] }

        var wallByID: [EntityID: Entity] = [:]
        var structureByPosition: [GridPosition: Entity] = [:]
        for structure in world.entities.all
            .filter({ $0.category == .structure })
            .sorted(by: { $0.id < $1.id }) {
            let flat = GridPosition(x: structure.position.x, y: structure.position.y, z: 0)
            structureByPosition[flat] = structure
            guard structure.structureType == .wall else { continue }
            let wall = structure
            wallByID[wall.id] = wall
        }

        var segments: [WhiteboxWallFlowSegmentShader] = []
        segments.reserveCapacity(min(maxSegmentCount, 1024))

        for networkID in world.combat.wallNetworks.keys.sorted() {
            guard let network = world.combat.wallNetworks[networkID] else { continue }
            guard network.capacity > 0 else { continue }

            let totalAmmo = network.ammoPoolByItemID.values.reduce(0, +)
            guard totalAmmo > 0 else { continue }

            let fillRatio = Float(min(1.0, Double(totalAmmo) / Double(network.capacity)))
            let intensity = 0.25 + (0.75 * fillRatio)
            let ammoTypeRaw = dominantAmmoTypeRaw(in: network.ammoPoolByItemID)
            let wallIDs = network.wallEntityIDs.sorted()
            let adjacencyByWallID = wallAdjacencyByWallID(wallIDs: wallIDs, wallByID: wallByID)
            let inputCandidates = potentialInputWallIDs(
                wallIDs: wallIDs,
                wallByID: wallByID,
                structureByPosition: structureByPosition,
                world: world
            )
            guard let startWallID = inputCandidates.sorted().first ?? wallIDs.first else { continue }
            guard let startWall = wallByID[startWallID] else { continue }
            let centroid = wallCentroid(wallIDs: wallIDs, wallByID: wallByID)
            let initialDirection = clockwiseInitialDirection(from: startWall.position, centroid: centroid)

            let maxEdges = adjacencyByWallID.values.reduce(0) { $0 + $1.count } / 2
            let traversal = clockwiseTraversal(
                startWallID: startWallID,
                adjacencyByWallID: adjacencyByWallID,
                initialDirection: initialDirection,
                maxSteps: max(1, maxEdges)
            )
            guard !traversal.isEmpty else { continue }

            let phaseLength = 1.0 / Float(max(1, traversal.count))
            for (index, step) in traversal.enumerated() {
                guard segments.count < maxSegmentCount else { return segments }
                guard let fromWall = wallByID[step.fromWallID], let toWall = wallByID[step.toWallID] else { continue }

                let from = GridPosition(x: fromWall.position.x, y: fromWall.position.y, z: 0)
                let to = GridPosition(x: toWall.position.x, y: toWall.position.y, z: 0)
                let phaseOffset = Float(index) * phaseLength

                segments.append(
                    WhiteboxWallFlowSegmentShader(
                        fromX: Int32(from.x),
                        fromY: Int32(from.y),
                        toX: Int32(to.x),
                        toY: Int32(to.y),
                        intensity: intensity,
                        ammoTypeRaw: ammoTypeRaw,
                        networkID: UInt32(max(0, networkID)),
                        phaseOffset: phaseOffset,
                        phaseLength: phaseLength
                    )
                )
            }
        }

        return segments
    }

    private func wallAdjacencyByWallID(
        wallIDs: [EntityID],
        wallByID: [EntityID: Entity]
    ) -> [EntityID: [(neighborID: EntityID, direction: CardinalDirection)]] {
        var wallIDByPosition: [GridPosition: EntityID] = [:]
        for wallID in wallIDs {
            guard let wall = wallByID[wallID] else { continue }
            let flat = GridPosition(x: wall.position.x, y: wall.position.y, z: 0)
            wallIDByPosition[flat] = wallID
        }

        var result: [EntityID: [(neighborID: EntityID, direction: CardinalDirection)]] = [:]
        for wallID in wallIDs {
            guard let wall = wallByID[wallID] else { continue }
            let flat = GridPosition(x: wall.position.x, y: wall.position.y, z: 0)
            var neighbors: [(neighborID: EntityID, direction: CardinalDirection)] = []
            for direction in CardinalDirection.allCases {
                let neighborPos = flat.translated(by: direction)
                if let neighborID = wallIDByPosition[neighborPos] {
                    neighbors.append((neighborID, direction))
                }
            }
            result[wallID] = neighbors
        }
        return result
    }

    private func potentialInputWallIDs(
        wallIDs: [EntityID],
        wallByID: [EntityID: Entity],
        structureByPosition: [GridPosition: Entity],
        world: WorldState
    ) -> Set<EntityID> {
        var candidates: Set<EntityID> = []
        for wallID in wallIDs {
            guard let wall = wallByID[wallID] else { continue }
            let wallPos = GridPosition(x: wall.position.x, y: wall.position.y, z: 0)
            for direction in CardinalDirection.allCases {
                let sourcePos = wallPos.translated(by: direction)
                guard let source = structureByPosition[sourcePos] else { continue }
                guard source.id != wallID else { continue }
                guard let sourceType = source.structureType, sourceType != .wall && sourceType != .turretMount else { continue }
                let directionToWall = direction.opposite
                if sourceOutputDirections(source: source, world: world).contains(directionToWall) {
                    candidates.insert(wallID)
                    break
                }
            }
        }
        return candidates
    }

    private func sourceOutputDirections(source: Entity, world: WorldState) -> [CardinalDirection] {
        guard let structureType = source.structureType else { return [] }
        switch structureType {
        case .conveyor:
            return [resolvedConveyorIO(for: source, world: world).outputDirection]
        case .splitter:
            let facing = source.rotation.direction
            return [facing.left, facing.right]
        case .merger:
            return [source.rotation.direction]
        case .miner, .smelter, .assembler, .ammoModule, .storage, .hq:
            return CardinalDirection.allCases
        case .wall, .turretMount, .powerPlant:
            return []
        }
    }

    private func resolvedConveyorIO(for source: Entity, world: WorldState) -> ConveyorIOConfig {
        if let configured = world.economy.conveyorIOByEntity[source.id] {
            return configured
        }
        return ConveyorIOConfig.default(for: source.rotation)
    }

    private func wallCentroid(
        wallIDs: [EntityID],
        wallByID: [EntityID: Entity]
    ) -> (x: Double, y: Double) {
        guard !wallIDs.isEmpty else { return (0, 0) }
        var sumX = 0.0
        var sumY = 0.0
        var count = 0.0
        for wallID in wallIDs {
            guard let wall = wallByID[wallID] else { continue }
            sumX += Double(wall.position.x)
            sumY += Double(wall.position.y)
            count += 1
        }
        guard count > 0 else { return (0, 0) }
        return (sumX / count, sumY / count)
    }

    private func clockwiseInitialDirection(
        from position: GridPosition,
        centroid: (x: Double, y: Double)
    ) -> CardinalDirection {
        let dx = Double(position.x) - centroid.x
        let dy = Double(position.y) - centroid.y
        let radial: CardinalDirection
        if abs(dx) >= abs(dy) {
            radial = dx >= 0 ? .east : .west
        } else {
            radial = dy >= 0 ? .south : .north
        }
        return radial.right
    }

    private struct TraversalStep {
        var fromWallID: EntityID
        var toWallID: EntityID
    }

    private func clockwiseTraversal(
        startWallID: EntityID,
        adjacencyByWallID: [EntityID: [(neighborID: EntityID, direction: CardinalDirection)]],
        initialDirection: CardinalDirection,
        maxSteps: Int
    ) -> [TraversalStep] {
        guard maxSteps > 0 else { return [] }
        var steps: [TraversalStep] = []
        var visitedEdges: Set<String> = []
        var currentWallID = startWallID
        var previousWallID: EntityID?
        var previousDirection = initialDirection

        for _ in 0..<maxSteps {
            guard let neighbors = adjacencyByWallID[currentWallID], !neighbors.isEmpty else { break }

            let candidates = neighbors.filter {
                !visitedEdges.contains(edgeKey(currentWallID, $0.neighborID))
            }
            guard !candidates.isEmpty else { break }

            let ranked = candidates.sorted { lhs, rhs in
                let l = traversalScore(
                    from: previousDirection,
                    to: lhs.direction,
                    previousWallID: previousWallID,
                    candidateWallID: lhs.neighborID
                )
                let r = traversalScore(
                    from: previousDirection,
                    to: rhs.direction,
                    previousWallID: previousWallID,
                    candidateWallID: rhs.neighborID
                )
                if l != r { return l < r }
                return lhs.neighborID < rhs.neighborID
            }
            guard let next = ranked.first else { break }

            visitedEdges.insert(edgeKey(currentWallID, next.neighborID))
            steps.append(TraversalStep(fromWallID: currentWallID, toWallID: next.neighborID))

            previousWallID = currentWallID
            currentWallID = next.neighborID
            previousDirection = next.direction

            if currentWallID == startWallID, steps.count > 1 {
                break
            }
        }

        return steps
    }

    private func traversalScore(
        from: CardinalDirection,
        to: CardinalDirection,
        previousWallID: EntityID?,
        candidateWallID: EntityID
    ) -> Int {
        let turnCost: Int
        if to == from.right {
            turnCost = 0
        } else if to == from {
            turnCost = 1
        } else if to == from.left {
            turnCost = 2
        } else {
            turnCost = 3
        }
        let backtrackPenalty = previousWallID == candidateWallID ? 4 : 0
        return turnCost + backtrackPenalty
    }

    private func edgeKey(_ a: EntityID, _ b: EntityID) -> String {
        let lo = min(a, b)
        let hi = max(a, b)
        return "\(lo):\(hi)"
    }

    private func dominantAmmoTypeRaw(in ammoPoolByItemID: [String: Int]) -> UInt32 {
        let dominantItemID = ammoPoolByItemID
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .first?
            .key

        switch dominantItemID {
        case "ammo_heavy":
            return 2
        case "ammo_plasma":
            return 3
        case "ammo_light":
            return 1
        default:
            return 0
        }
    }

    private func buildTurretOverlays(world: WorldState, maxCount: Int) -> [WhiteboxTurretOverlayShader] {
        guard maxCount > 0 else { return [] }
        let turrets = world.entities.structures(of: .turretMount).sorted { $0.id < $1.id }
        if turrets.isEmpty { return [] }

        return turrets.prefix(maxCount).map { turret in
            WhiteboxTurretOverlayShader(
                x: Int32(turret.position.x),
                y: Int32(turret.position.y),
                rangeTiles: turretRangeTiles(for: turret.turretDefID)
            )
        }
    }

    private func turretRangeTiles(for turretDefID: String?) -> Float {
        switch turretDefID ?? "turret_mk1" {
        case "turret_mk2":
            return 10.0
        case "gattling_tower":
            return 6.5
        case "plasma_sentinel":
            return 11.0
        default:
            return 8.0
        }
    }

    private func buildEnemyPathSegments(world: WorldState, maxSegmentCount: Int) -> [WhiteboxPathSegmentShader] {
        guard maxSegmentCount > 0 else { return [] }
        guard !world.combat.enemies.isEmpty else { return [] }

        let map = navigationMap(for: world)
        let base = GridPosition(x: world.combat.basePosition.x, y: world.combat.basePosition.y, z: 0)
        let flowField = buildFlowField(on: map, goal: base)
        guard !flowField.isEmpty else { return [] }

        var segments: [WhiteboxPathSegmentShader] = []
        segments.reserveCapacity(min(maxSegmentCount, 512))

        for enemyID in world.combat.enemies.keys.sorted() {
            guard let enemy = world.entities.entity(id: enemyID) else { continue }
            var current = GridPosition(x: enemy.position.x, y: enemy.position.y, z: 0)
            guard flowField[current] != nil else { continue }

            var guardSteps = min(maxSegmentCount, max(1, world.board.width * world.board.height))
            while current != base, guardSteps > 0, segments.count < maxSegmentCount {
                guard let next = nextFlowStep(from: current, map: map, flowField: flowField) else { break }
                segments.append(
                    WhiteboxPathSegmentShader(
                        fromX: Int32(current.x),
                        fromY: Int32(current.y),
                        toX: Int32(next.x),
                        toY: Int32(next.y)
                    )
                )
                current = next
                guardSteps -= 1
            }
        }

        return segments
    }

    private func buildFlowField(on map: GridMap, goal: GridPosition) -> [GridPosition: Int] {
        guard let goalTile = map.tile(at: goal), goalTile.walkable else { return [:] }

        var distances: [GridPosition: Int] = [goal: 0]
        var queue: [GridPosition] = [goal]
        var index = 0

        while index < queue.count {
            let current = queue[index]
            index += 1
            let nextDistance = distances[current, default: 0] + 1

            let neighbors = [
                current.translated(byX: 1),
                current.translated(byX: -1),
                current.translated(byY: 1),
                current.translated(byY: -1)
            ]

            for neighbor in neighbors {
                guard distances[neighbor] == nil else { continue }
                guard let tile = map.tile(at: neighbor), tile.walkable else { continue }
                distances[neighbor] = nextDistance
                queue.append(neighbor)
            }
        }

        return distances
    }

    private func nextFlowStep(from position: GridPosition, map: GridMap, flowField: [GridPosition: Int]) -> GridPosition? {
        let current = GridPosition(x: position.x, y: position.y, z: 0)
        let currentDistance = flowField[current]
        var candidates: [(position: GridPosition, distance: Int)] = []

        let neighbors = [
            current.translated(byX: 1),
            current.translated(byX: -1),
            current.translated(byY: 1),
            current.translated(byY: -1)
        ]

        for neighbor in neighbors {
            guard let tile = map.tile(at: neighbor), tile.walkable else { continue }
            guard let neighborDistance = flowField[neighbor] else { continue }
            if let currentDistance {
                guard neighborDistance < currentDistance else { continue }
            }
            candidates.append((neighbor, neighborDistance))
        }

        guard !candidates.isEmpty else { return nil }
        let best = candidates.min { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            if lhs.position.y != rhs.position.y { return lhs.position.y < rhs.position.y }
            return lhs.position.x < rhs.position.x
        }
        return best?.position
    }

    private func navigationMap(for world: WorldState) -> GridMap {
        var map = GridMap(width: world.board.width, height: world.board.height)

        for y in 0..<world.board.height {
            for x in 0..<world.board.width {
                let position = GridPosition(x: x, y: y)
                guard let terrain = world.board.terrain(at: position) else { continue }
                map.setTile(
                    GridTile(walkable: terrain.walkable, elevation: terrain.elevation, isRamp: terrain.isRamp),
                    at: position
                )
            }
        }

        for entity in world.entities.all where entity.category == .structure {
            guard let structureType = entity.structureType, structureType.blocksMovement else { continue }
            for blockedCell in structureType.coveredCells(anchor: entity.position) {
                map.setTile(GridTile(walkable: false, elevation: entity.position.z), at: blockedCell)
            }
        }

        let base = world.board.basePosition
        map.setTile(
            GridTile(walkable: true, elevation: world.board.elevation(at: base), isRamp: false),
            at: base
        )

        return map
    }
}
