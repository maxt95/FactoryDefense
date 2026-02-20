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
    var cursorWorldX: Float
    var cursorWorldY: Float
    var gridRevealRadius: Float
    var gridRevealStrength: Float
    var oreCount: UInt32
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
    var phaseOffset: Float
    var _pad0: UInt32 = 0
}

private struct WhiteboxOreInfluenceShader {
    var x: Int32
    var y: Int32
    var oreTypeRaw: UInt32
    var richness: Float
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

    public init() {}

    public func encode(context: RenderContext, commandBuffer: MTLCommandBuffer) {
        guard let drawableTexture = context.currentDrawable?.texture else { return }
        guard let pipelineState = preparePipeline(device: context.device) else { return }

        let scene = sceneBuilder.build(from: context.worldState)
        let debugOverlays = buildDebugOverlays(context: context)

        // Compute grid reveal parameters based on interaction state
        let cursorWorldX: Float
        let cursorWorldY: Float
        let gridRevealRadius: Float
        let gridRevealStrength: Float

        if context.highlightedStructure != nil && context.highlightedCell != nil {
            // Building placement mode
            cursorWorldX = Float(context.highlightedCell!.x) + 0.5
            cursorWorldY = Float(context.highlightedCell!.y) + 0.5
            gridRevealRadius = 3.0
            gridRevealStrength = 0.70
        } else if !context.highlightedPath.isEmpty, let first = context.highlightedPath.first {
            // Path placement mode
            cursorWorldX = Float(first.x) + 0.5
            cursorWorldY = Float(first.y) + 0.5
            gridRevealRadius = 4.0
            gridRevealStrength = 0.80
        } else if let cell = context.highlightedCell {
            // Passive hover
            cursorWorldX = Float(cell.x) + 0.5
            cursorWorldY = Float(cell.y) + 0.5
            gridRevealRadius = 2.0
            gridRevealStrength = 0.35
        } else {
            // No hover
            cursorWorldX = -100.0
            cursorWorldY = -100.0
            gridRevealRadius = 0.0
            gridRevealStrength = 0.0
        }

        // Build ore influences from world state
        let oreInfluences: [WhiteboxOreInfluenceShader] = context.worldState.orePatches.compactMap { patch in
            guard !patch.isExhausted else { return nil }
            let oreTypeRaw: UInt32
            switch patch.oreType {
            case "iron_ore":
                oreTypeRaw = 1
            case "copper_ore":
                oreTypeRaw = 2
            case "coal":
                oreTypeRaw = 3
            default:
                oreTypeRaw = 1
            }
            let richness: Float
            switch patch.richness {
            case .poor:
                richness = 0.4
            case .normal:
                richness = 0.7
            case .rich:
                richness = 1.0
            }
            return WhiteboxOreInfluenceShader(
                x: Int32(patch.position.x),
                y: Int32(patch.position.y),
                oreTypeRaw: oreTypeRaw,
                richness: richness
            )
        }

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
            animationTick: Float(context.worldState.tick),
            cursorWorldX: cursorWorldX,
            cursorWorldY: cursorWorldY,
            gridRevealRadius: gridRevealRadius,
            gridRevealStrength: gridRevealStrength,
            oreCount: UInt32(oreInfluences.count)
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
        let oreInfluenceBuffer = makeOreInfluenceBuffer(context.device, influences: oreInfluences)

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
        encoder.setBuffer(oreInfluenceBuffer, offset: 0, index: 10)

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

    private func makeOreInfluenceBuffer(_ device: MTLDevice, influences: [WhiteboxOreInfluenceShader]) -> MTLBuffer? {
        guard !influences.isEmpty else { return nil }
        var payload = influences
        return device.makeBuffer(
            bytes: &payload,
            length: MemoryLayout<WhiteboxOreInfluenceShader>.stride * payload.count
        )
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
        for wall in world.entities.structures(of: .wall) {
            wallByID[wall.id] = wall
        }

        var segments: [WhiteboxWallFlowSegmentShader] = []
        segments.reserveCapacity(min(maxSegmentCount, 1024))

        let neighborOffsets: [(x: Int, y: Int)] = [(1, 0), (0, 1)]
        for networkID in world.combat.wallNetworks.keys.sorted() {
            guard let network = world.combat.wallNetworks[networkID] else { continue }
            guard network.capacity > 0 else { continue }

            let totalAmmo = network.ammoPoolByItemID.values.reduce(0, +)
            guard totalAmmo > 0 else { continue }

            let fillRatio = Float(min(1.0, Double(totalAmmo) / Double(network.capacity)))
            let intensity = 0.25 + (0.75 * fillRatio)
            let ammoTypeRaw = dominantAmmoTypeRaw(in: network.ammoPoolByItemID)
            let wallIDs = network.wallEntityIDs.sorted()
            let wallIDsByPosition: [GridPosition: EntityID] = Dictionary(
                uniqueKeysWithValues: wallIDs.compactMap { wallID in
                    guard let wall = wallByID[wallID] else { return nil }
                    return (GridPosition(x: wall.position.x, y: wall.position.y, z: 0), wallID)
                }
            )

            for wallID in wallIDs {
                guard let wall = wallByID[wallID] else { continue }
                let position = GridPosition(x: wall.position.x, y: wall.position.y, z: 0)

                for offset in neighborOffsets {
                    guard segments.count < maxSegmentCount else { return segments }
                    let neighbor = position.translated(byX: offset.x, byY: offset.y)
                    guard wallIDsByPosition[neighbor] != nil else { continue }

                    let seed = (networkID &* 131) &+ (position.x &* 17) &+ (position.y &* 29) &+ (offset.x &* 7) &+ (offset.y &* 11)
                    let phaseOffset = Float(abs(seed % 1000)) / 1000.0

                    segments.append(
                        WhiteboxWallFlowSegmentShader(
                            fromX: Int32(position.x),
                            fromY: Int32(position.y),
                            toX: Int32(neighbor.x),
                            toY: Int32(neighbor.y),
                            intensity: intensity,
                            ammoTypeRaw: ammoTypeRaw,
                            phaseOffset: phaseOffset
                        )
                    )
                }
            }
        }

        return segments
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
