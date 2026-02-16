import Foundation
import Metal
import simd
import GameSimulation

private struct InstanceUniforms {
    var modelViewProjection: simd_float4x4
    var modelMatrix: simd_float4x4
    var tintColor: SIMD4<Float>
}

private struct PipelineKey: Equatable {
    var deviceID: ObjectIdentifier
    var colorPixelFormat: MTLPixelFormat
    var depthPixelFormat: MTLPixelFormat
}

public final class WhiteboxMeshRenderer {
    private let sceneBuilder = WhiteboxSceneBuilder()
    private var pipelineState: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    private var meshLibrary: WhiteboxMeshLibrary?
    private var meshLibraryDeviceID: ObjectIdentifier?
    private var pipelineKey: PipelineKey?
    private var hasLoggedResourceIssue = false

    public init() {}

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

        guard let pipelineState, let depthState, let meshLibrary else { return }

        let viewProjection = makeViewProjectionMatrix(context: context)
        let scene = sceneBuilder.build(from: context.worldState)
        let batches = makeInstanceBatches(scene: scene, context: context, viewProjection: viewProjection)
        guard !batches.isEmpty else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setFrontFacing(.counterClockwise)

        for batch in batches {
            guard let mesh = meshLibrary.mesh(for: batch.meshID), !batch.instances.isEmpty else { continue }
            var instances = batch.instances
            guard let instanceBuffer = context.device.makeBuffer(
                bytes: &instances,
                length: MemoryLayout<InstanceUniforms>.stride * instances.count
            ) else {
                logResourceIssue("Failed to allocate whitebox instance buffer.")
                return
            }

            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: mesh.indexCount,
                indexType: .uint16,
                indexBuffer: mesh.indexBuffer,
                indexBufferOffset: 0,
                instanceCount: instances.count
            )
        }
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
        if meshLibrary == nil || meshLibraryDeviceID != deviceID {
            meshLibrary = WhiteboxMeshLibrary(device: device)
            meshLibraryDeviceID = deviceID
        }

        return meshLibrary != nil
    }

    private func makeViewProjectionMatrix(context: RenderContext) -> simd_float4x4 {
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
    ) -> [MeshInstanceBatch] {
        var grouped: [MeshID: [InstanceUniforms]] = [:]

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
            let centerX = Float(marker.x) + 0.5
            let centerZ = Float(marker.y) + 0.5
            let baseElevation = Float(
                context.worldState.board.elevation(
                    at: GridPosition(x: Int(marker.x), y: Int(marker.y))
                )
            )

            let meshID: MeshID
            let instanceScale: SIMD3<Float>
            let verticalOffset: Float

            if marker.category == WhiteboxEntityCategory.enemy.rawValue {
                meshID = .swarmling
                instanceScale = SIMD3<Float>(1.0, 1.0, 1.0)
                verticalOffset = 0.0
            } else {
                meshID = .lightBallisticProjectile
                instanceScale = SIMD3<Float>(1.0, 1.0, 1.0)
                verticalOffset = 0.16
            }

            let model = simd_float4x4.translation(
                SIMD3<Float>(centerX, baseElevation + verticalOffset, centerZ)
            ) * simd_float4x4.scale(instanceScale)

            grouped[meshID, default: []].append(
                InstanceUniforms(
                    modelViewProjection: viewProjection * model,
                    modelMatrix: model,
                    tintColor: SIMD4<Float>(WhiteboxColors.color(for: meshID), 1)
                )
            )
        }

        return MeshID.renderOrder.compactMap { meshID in
            guard let instances = grouped[meshID], !instances.isEmpty else { return nil }
            return MeshInstanceBatch(meshID: meshID, instances: instances)
        }
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

private struct MeshInstanceBatch {
    var meshID: MeshID
    var instances: [InstanceUniforms]
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
        case WhiteboxStructureTypeID.storage.rawValue:
            self = .storage
        case WhiteboxStructureTypeID.hq.rawValue:
            self = .hq
        default:
            self = .wall
        }
    }
}
