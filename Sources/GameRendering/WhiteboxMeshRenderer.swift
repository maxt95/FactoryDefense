import Foundation
import Metal
import simd
import GameSimulation

private struct InstanceUniforms {
    var modelViewProjection: simd_float4x4
    var modelMatrix: simd_float4x4
    var tintColor: SIMD4<Float>
}

// Must match FogParams in pbr.metal
private struct FogParams {
    var fogColor: SIMD3<Float>
    var fogStart: Float
    var fogEnd: Float
    var cameraPosition: SIMD3<Float>
    var _padding: Float = 0 // alignment padding
}

private struct PipelineKey: Equatable {
    var deviceID: ObjectIdentifier
    var colorPixelFormat: MTLPixelFormat
    var depthPixelFormat: MTLPixelFormat
}

private struct MeshInstanceBatch {
    var meshID: MeshID
    var instanceRange: Range<Int>
}

public final class WhiteboxMeshRenderer {
    private let sceneBuilder = WhiteboxSceneBuilder()
    private var pipelineState: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    private var meshProvider: (any MeshProvider)?
    private var meshProviderFactory: ((MTLDevice) -> any MeshProvider)?
    private var meshProviderDeviceID: ObjectIdentifier?
    private var pipelineKey: PipelineKey?
    private var hasLoggedResourceIssue = false

    // Triple-buffer instance uploads to avoid CPU/GPU contention.
    private let inFlightInstanceBufferCount = 3
    private var frameIndex = 0
    private var instanceBuffers: [MTLBuffer?]
    private var instanceBufferCapacities: [Int]

    public init() {
        self.instanceBuffers = Array(repeating: nil, count: inFlightInstanceBufferCount)
        self.instanceBufferCapacities = Array(repeating: 0, count: inFlightInstanceBufferCount)
    }

    public func useProceduralMeshes() {
        meshProviderFactory = nil
        meshProvider = nil
        meshProviderDeviceID = nil
    }

    public func useModelIOMeshes(assetURLs: [MeshID: URL]) {
        meshProviderFactory = { device in
            ModelIOMeshLibrary(device: device, assetURLs: assetURLs)
        }
        meshProvider = nil
        meshProviderDeviceID = nil
    }

    public func encode(context: RenderContext, encoder: MTLRenderCommandEncoder) {
        let colorPixelFormat = context.currentDrawable?.texture.pixelFormat ?? .bgra8Unorm_srgb
        let depthPixelFormat = context.renderResources.drawableDepthTexture?.pixelFormat
            ?? context.renderResources.depthTexture?.pixelFormat
            ?? .depth32Float

        guard prepareResources(
            device: context.device,
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat
        ) else {
            return
        }

        guard let pipelineState, let depthState, let meshProvider else { return }

        let viewProjection = makeViewProjectionMatrix(context: context)
        let scene = sceneBuilder.build(from: context.worldState)
        let (batches, instancePayload) = makeInstanceBatches(scene: scene, context: context, viewProjection: viewProjection)
        guard !instancePayload.isEmpty else { return }

        let slot = frameIndex
        frameIndex = (frameIndex + 1) % inFlightInstanceBufferCount
        guard let instanceBuffer = ensureInstanceBuffer(
            device: context.device,
            slot: slot,
            minimumInstanceCount: instancePayload.count
        ) else {
            logResourceIssue("Failed to allocate triple-buffered whitebox instance data.")
            return
        }

        let instancePointer = instanceBuffer.contents().bindMemory(
            to: InstanceUniforms.self,
            capacity: instancePayload.count
        )
        instancePayload.withUnsafeBufferPointer { source in
            guard let sourceAddress = source.baseAddress else { return }
            instancePointer.update(from: sourceAddress, count: source.count)
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setFrontFacing(.counterClockwise)
#if os(macOS)
        encoder.setTriangleFillMode(context.debugMode == .wireframe ? .lines : .fill)
#else
        encoder.setTriangleFillMode(.fill)
#endif

        // Set fog params for PBR fragment shader
        var fogParams = makeFogParams(context: context)
        encoder.setFragmentBytes(&fogParams, length: MemoryLayout<FogParams>.stride, index: 0)

        for batch in batches {
            guard let mesh = meshProvider.mesh(for: batch.meshID) else { continue }
            let instanceCount = batch.instanceRange.count
            guard instanceCount > 0 else { continue }

            let instanceOffset = MemoryLayout<InstanceUniforms>.stride * batch.instanceRange.lowerBound
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(instanceBuffer, offset: instanceOffset, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: mesh.indexCount,
                indexType: .uint16,
                indexBuffer: mesh.indexBuffer,
                indexBufferOffset: 0,
                instanceCount: instanceCount
            )
        }
    }

    private func ensureInstanceBuffer(
        device: MTLDevice,
        slot: Int,
        minimumInstanceCount: Int
    ) -> MTLBuffer? {
        guard minimumInstanceCount > 0 else { return nil }
        let clampedSlot = max(0, min(slot, inFlightInstanceBufferCount - 1))
        if let existing = instanceBuffers[clampedSlot], instanceBufferCapacities[clampedSlot] >= minimumInstanceCount {
            return existing
        }

        let capacity = max(256, nextPowerOfTwo(minimumInstanceCount))
        let length = MemoryLayout<InstanceUniforms>.stride * capacity
        guard let buffer = device.makeBuffer(length: length, options: [.storageModeShared]) else {
            return nil
        }

        instanceBuffers[clampedSlot] = buffer
        instanceBufferCapacities[clampedSlot] = capacity
        return buffer
    }

    private func nextPowerOfTwo(_ value: Int) -> Int {
        var result = 1
        while result < value {
            result <<= 1
        }
        return result
    }

    private func prepareResources(
        device: MTLDevice,
        colorPixelFormat: MTLPixelFormat,
        depthPixelFormat: MTLPixelFormat
    ) -> Bool {
        let key = PipelineKey(
            deviceID: ObjectIdentifier(device as AnyObject),
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat
        )

        if pipelineKey != key || pipelineState == nil || depthState == nil {
            do {
                let library = try device.makeDefaultLibrary(bundle: .module)
                guard let vertex = library.makeFunction(name: "pbr_vertex"),
                      let fragment = library.makeFunction(name: "pbr_fragment") else {
                    logResourceIssue("Missing pbr shader functions in default Metal library.")
                    return false
                }

                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.label = "WhiteboxPBRPipeline"
                descriptor.vertexFunction = vertex
                descriptor.fragmentFunction = fragment
                descriptor.vertexDescriptor = makeWhiteboxVertexDescriptor()
                descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
                descriptor.depthAttachmentPixelFormat = depthPixelFormat

                let depthDescriptor = MTLDepthStencilDescriptor()
                depthDescriptor.label = "WhiteboxDepthStencil"
                depthDescriptor.depthCompareFunction = .less
                depthDescriptor.isDepthWriteEnabled = true

                let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
                guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
                    logResourceIssue("Failed to create depth stencil state.")
                    return false
                }

                self.pipelineState = pipeline
                self.depthState = depthState
                self.pipelineKey = key
            } catch {
                logResourceIssue("Failed to build whitebox mesh pipeline: \(error.localizedDescription)")
                return false
            }
        }

        let deviceID = ObjectIdentifier(device as AnyObject)
        if meshProvider == nil || meshProviderDeviceID != deviceID {
            let proceduralProvider: any MeshProvider = WhiteboxMeshLibrary(device: device)
            if let meshProviderFactory {
                let dccProvider = meshProviderFactory(device)
                meshProvider = CompositeMeshProvider(primary: dccProvider, fallback: proceduralProvider)
            } else {
                meshProvider = proceduralProvider
            }
            meshProviderDeviceID = deviceID
        }

        return meshProvider != nil
    }

    private func makeViewProjectionMatrix(context: RenderContext) -> simd_float4x4 {
        if context.viewMode == .fpsView, let fpsVP = context.fpsViewProjection {
            return fpsVP
        }

        let board = context.worldState.board
        let viewWidth = Float(max(1, context.viewSizePoints.width))
        let viewHeight = Float(max(1, context.viewSizePoints.height))
        let zoom = max(0.001, context.cameraState.zoom)
        let tileWidth: Float = 34.0 * zoom
        let tileHeight: Float = 22.0 * zoom

        let boardPixelWidth = Float(board.width) * tileWidth
        let boardPixelHeight = Float(board.height) * tileHeight
        let originX = (viewWidth - boardPixelWidth) * 0.5 + context.cameraState.pan.x
        let originY = viewHeight * 0.5 - boardPixelHeight * 0.5 + context.cameraState.pan.y

        let xScale = (2.0 * tileWidth) / viewWidth
        let yFromHeight = (2.0 * tileHeight) / viewHeight
        let yFromDepth = (-2.0 * tileHeight) / viewHeight
        let xOffset = (2.0 * originX / viewWidth) - 1.0
        let yOffset = 1.0 - (2.0 * originY / viewHeight)

        let depthX = 0.30 / Float(max(1, board.width))
        let depthZ = 0.30 / Float(max(1, board.height))
        let depthY: Float = -0.05
        let depthOffset: Float = 0.2

        return simd_float4x4(columns: (
            SIMD4<Float>(xScale, 0, depthX, 0),
            SIMD4<Float>(0, yFromHeight, depthY, 0),
            SIMD4<Float>(0, yFromDepth, depthZ, 0),
            SIMD4<Float>(xOffset, yOffset, depthOffset, 1)
        ))
    }

    private func makeInstanceBatches(
        scene: WhiteboxSceneData,
        context: RenderContext,
        viewProjection: simd_float4x4
    ) -> ([MeshInstanceBatch], [InstanceUniforms]) {
        var grouped: [MeshID: [InstanceUniforms]] = [:]
        let isFPSView = context.viewMode == .fpsView

        // In FPS mode, generate ground for the board and a large surrounding terrain
        if isFPSView {
            let board = context.worldState.board
            let blockedSet = Set(scene.blockedCells.map { WhiteboxPoint(x: $0.x, y: $0.y) })
            let restrictedSet = Set(scene.restrictedCells.map { WhiteboxPoint(x: $0.x, y: $0.y) })

            // Board ground tiles (detailed, per-cell)
            for y in 0..<board.height {
                for x in 0..<board.width {
                    let point = WhiteboxPoint(x: Int32(x), y: Int32(y))
                    let centerX = Float(x) + 0.5
                    let centerZ = Float(y) + 0.5
                    let model = simd_float4x4.translation(SIMD3<Float>(centerX, 0, centerZ))

                    let tint: SIMD3<Float>
                    if blockedSet.contains(point) {
                        tint = SIMD3<Float>(0.25, 0.22, 0.20)
                    } else if restrictedSet.contains(point) {
                        tint = SIMD3<Float>(0.55, 0.50, 0.35)
                    } else {
                        tint = SIMD3<Float>(0.45, 0.55, 0.35)
                    }

                    grouped[.gridTile, default: []].append(
                        InstanceUniforms(
                            modelViewProjection: viewProjection * model,
                            modelMatrix: model,
                            tintColor: SIMD4<Float>(tint, 1)
                        )
                    )
                }
            }

            // Extended terrain beyond board edges — large tiles in a ring around the board
            // Creates the illusion of an infinite world
            let extend = 40 // tiles beyond each edge
            let terrainColor = SIMD3<Float>(0.32, 0.38, 0.28) // muted grass/dirt
            let terrainFarColor = SIMD3<Float>(0.30, 0.35, 0.26)

            let minX = -extend
            let maxX = board.width + extend
            let minZ = -extend
            let maxZ = board.height + extend

            // Use larger tiles (4x4) for the extended terrain to keep instance count reasonable
            let tileSize = 4
            var tx = minX
            while tx < maxX {
                var tz = minZ
                while tz < maxZ {
                    // Skip tiles that are inside the board (already rendered above)
                    let insideBoard = tx >= 0 && tx + tileSize <= board.width
                        && tz >= 0 && tz + tileSize <= board.height
                    if !insideBoard {
                        let centerX = Float(tx) + Float(tileSize) * 0.5
                        let centerZ = Float(tz) + Float(tileSize) * 0.5
                        let scale = SIMD3<Float>(Float(tileSize), 1.0, Float(tileSize))
                        let model = simd_float4x4.translation(SIMD3<Float>(centerX, -0.02, centerZ))
                            * simd_float4x4.scale(scale)

                        // Darken terrain tiles further from the board for a natural gradient
                        let distFromBoardX = max(0, max(Float(-tx), Float(tx + tileSize - board.width)))
                        let distFromBoardZ = max(0, max(Float(-tz), Float(tz + tileSize - board.height)))
                        let distFromBoard = max(distFromBoardX, distFromBoardZ)
                        let fadeFactor = min(distFromBoard / Float(extend), 1.0)
                        let tint = terrainColor + (terrainFarColor - terrainColor) * fadeFactor

                        grouped[.gridTile, default: []].append(
                            InstanceUniforms(
                                modelViewProjection: viewProjection * model,
                                modelMatrix: model,
                                tintColor: SIMD4<Float>(tint, 1)
                            )
                        )
                    }
                    tz += tileSize
                }
                tx += tileSize
            }
        }

        for structure in scene.structures {
            let width = max(1, Int(structure.footprintWidth))
            let depth = max(1, Int(structure.footprintHeight))
            let minX = Int(structure.anchorX) - (width - 1)
            let minY = Int(structure.anchorY) - (depth - 1)
            let centerX = Float(minX) + (Float(width) * 0.5)
            let centerZ = Float(minY) + (Float(depth) * 0.5)
            let baseElevation = Float(
                context.worldState.board.elevation(
                    at: GridPosition(x: Int(structure.anchorX), y: Int(structure.anchorY))
                )
            )

            let meshID = MeshID(structureTypeRaw: structure.typeRaw)
            let footprintScale = SIMD3<Float>(Float(width) * 0.92, 1.0, Float(depth) * 0.92)
            let model = simd_float4x4.translation(
                SIMD3<Float>(centerX, baseElevation, centerZ)
            ) * simd_float4x4.scale(footprintScale)

            grouped[meshID, default: []].append(
                InstanceUniforms(
                    modelViewProjection: viewProjection * model,
                    modelMatrix: model,
                    tintColor: SIMD4<Float>(WhiteboxColors.color(for: structure.typeRaw), 1)
                )
            )
        }

        for marker in scene.entities {
            // Skip player mesh in FPS view (can't see yourself)
            if isFPSView && marker.category == WhiteboxEntityCategory.player.rawValue {
                continue
            }

            let centerX: Float
            let centerZ: Float

            // Use sub-cell position for player entities
            if marker.category == WhiteboxEntityCategory.player.rawValue {
                let player = context.worldState.player
                centerX = player.worldX
                centerZ = player.worldZ
            } else {
                centerX = Float(marker.x) + 0.5
                centerZ = Float(marker.y) + 0.5
            }

            let baseElevation = Float(
                context.worldState.board.elevation(
                    at: GridPosition(x: Int(marker.x), y: Int(marker.y))
                )
            )

            let meshID = meshID(for: marker)
            let verticalOffset: Float = marker.category == WhiteboxEntityCategory.projectile.rawValue ? 0.16 : 0
            let model = simd_float4x4.translation(
                SIMD3<Float>(centerX, baseElevation + verticalOffset, centerZ)
            )

            grouped[meshID, default: []].append(
                InstanceUniforms(
                    modelViewProjection: viewProjection * model,
                    modelMatrix: model,
                    tintColor: SIMD4<Float>(tintColor(for: marker, meshID: meshID), 1)
                )
            )
        }

        var batches: [MeshInstanceBatch] = []
        var flattenedInstances: [InstanceUniforms] = []
        for meshID in MeshID.renderOrder {
            guard let instances = grouped[meshID], !instances.isEmpty else { continue }
            let start = flattenedInstances.count
            flattenedInstances.append(contentsOf: instances)
            batches.append(MeshInstanceBatch(meshID: meshID, instanceRange: start..<flattenedInstances.count))
        }

        return (batches, flattenedInstances)
    }

    private func meshID(for marker: WhiteboxEntityMarker) -> MeshID {
        if marker.category == WhiteboxEntityCategory.resourceNode.rawValue {
            return .resourceNode
        }

        if marker.category == WhiteboxEntityCategory.enemy.rawValue {
            switch marker.subtypeRaw {
            case WhiteboxEnemyTypeID.swarmling.rawValue:
                return .swarmling
            case WhiteboxEnemyTypeID.droneScout.rawValue:
                return .droneScout
            case WhiteboxEnemyTypeID.raider.rawValue:
                return .raider
            case WhiteboxEnemyTypeID.breacher.rawValue:
                return .breacher
            case WhiteboxEnemyTypeID.artilleryBug.rawValue:
                return .artilleryBug
            case WhiteboxEnemyTypeID.overseer.rawValue:
                return .overseer
            default:
                return .swarmling
            }
        }

        if marker.category == WhiteboxEntityCategory.projectile.rawValue {
            switch marker.subtypeRaw {
            case WhiteboxProjectileTypeID.heavyBallistic.rawValue:
                return .heavyBallisticProjectile
            case WhiteboxProjectileTypeID.plasma.rawValue:
                return .plasmaProjectile
            default:
                return .lightBallisticProjectile
            }
        }

        if marker.category == WhiteboxEntityCategory.player.rawValue {
            return .playerCharacter
        }

        return .gridTile
    }

    private func tintColor(for marker: WhiteboxEntityMarker, meshID: MeshID) -> SIMD3<Float> {
        if marker.category == WhiteboxEntityCategory.resourceNode.rawValue {
            let resourceType = WhiteboxResourceTypeID(rawValue: marker.subtypeRaw) ?? .unknown
            return OrePresentation.color(for: resourceType.oreType)
        }
        return WhiteboxColors.color(for: meshID)
    }

    private func makeFogParams(context: RenderContext) -> FogParams {
        if context.viewMode == .fpsView {
            let player = context.worldState.player
            return FogParams(
                fogColor: SIMD3<Float>(0.55, 0.70, 0.85), // match horizon color in sky shader
                fogStart: 20.0,
                fogEnd: 80.0,
                cameraPosition: player.worldPosition
            )
        }
        // Base view: no fog (very large start distance)
        return FogParams(
            fogColor: SIMD3<Float>(0.07, 0.08, 0.10),
            fogStart: 9999.0,
            fogEnd: 10000.0,
            cameraPosition: SIMD3<Float>(0, 0, 0)
        )
    }

    private func makeWhiteboxVertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .half3
        descriptor.attributes[1].offset = 12
        descriptor.attributes[1].bufferIndex = 0
        descriptor.layouts[0].stride = 20
        descriptor.layouts[0].stepFunction = .perVertex
        descriptor.layouts[0].stepRate = 1
        return descriptor
    }

    private func logResourceIssue(_ message: String) {
        guard !hasLoggedResourceIssue else { return }
        hasLoggedResourceIssue = true
        fputs("FactoryDefense WhiteboxMeshRenderer: \(message)\n", stderr)
        RenderDiagnostics.post("Whitebox mesh renderer issue: \(message)")
    }
}

private extension MeshID {
    init(structureTypeRaw: UInt32) {
        switch structureTypeRaw {
        case WhiteboxStructureTypeID.wall.rawValue:
            self = .wall
        case WhiteboxStructureTypeID.turretMount.rawValue:
            self = .turretMount
        case WhiteboxStructureTypeID.miner.rawValue:
            self = .miner
        case WhiteboxStructureTypeID.smelter.rawValue:
            self = .smelter
        case WhiteboxStructureTypeID.assembler.rawValue:
            self = .assembler
        case WhiteboxStructureTypeID.ammoModule.rawValue:
            self = .ammoModule
        case WhiteboxStructureTypeID.powerPlant.rawValue:
            self = .powerPlant
        case WhiteboxStructureTypeID.conveyor.rawValue:
            self = .conveyor
        case WhiteboxStructureTypeID.splitter.rawValue:
            self = .splitter
        case WhiteboxStructureTypeID.merger.rawValue:
            self = .merger
        case WhiteboxStructureTypeID.storage.rawValue:
            self = .storage
        case WhiteboxStructureTypeID.hq.rawValue:
            self = .hq
        default:
            self = .wall
        }
    }
}
