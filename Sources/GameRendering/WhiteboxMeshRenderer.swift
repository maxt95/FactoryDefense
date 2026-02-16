import Foundation
import Metal
import simd
import GameSimulation

private struct PackedWhiteboxVertex {
    var px: Float
    var py: Float
    var pz: Float
    var nx: UInt16
    var ny: UInt16
    var nz: UInt16
    var _pad: UInt16 = 0
}

private struct WhiteboxMesh {
    var vertexBuffer: MTLBuffer
    var indexBuffer: MTLBuffer
    var indexCount: Int
}

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
    private var cubeMesh: WhiteboxMesh?
    private var pipelineKey: PipelineKey?
    private var hasLoggedResourceIssue = false

    public init() {}

    public func encode(context: RenderContext, encoder: MTLRenderCommandEncoder) {
        let colorPixelFormat = context.currentDrawable?.texture.pixelFormat ?? .bgra8Unorm_srgb
        let depthPixelFormat = context.renderResources.depthTexture?.pixelFormat ?? .depth32Float
        guard prepareResources(
            device: context.device,
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat
        ) else {
            return
        }
        guard let pipelineState, let depthState, let cubeMesh else { return }

        let viewProjection = makeViewProjectionMatrix(context: context)
        let scene = sceneBuilder.build(from: context.worldState)
        var instances = makeInstanceUniforms(scene: scene, context: context, viewProjection: viewProjection)
        guard !instances.isEmpty else { return }

        guard let instanceBuffer = context.device.makeBuffer(
            bytes: &instances,
            length: MemoryLayout<InstanceUniforms>.stride * instances.count
        ) else {
            logResourceIssue("Failed to allocate whitebox instance buffer.")
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setVertexBuffer(cubeMesh.vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: cubeMesh.indexCount,
            indexType: .uint16,
            indexBuffer: cubeMesh.indexBuffer,
            indexBufferOffset: 0,
            instanceCount: instances.count
        )
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

        if pipelineKey == key, pipelineState != nil, depthState != nil, cubeMesh != nil {
            return true
        }

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

            let cubeMesh = try makeCubeMesh(device: device)
            let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
                logResourceIssue("Failed to create depth stencil state.")
                return false
            }

            self.cubeMesh = cubeMesh
            self.pipelineState = pipeline
            self.depthState = depthState
            self.pipelineKey = key
            return true
        } catch {
            logResourceIssue("Failed to build whitebox mesh pipeline: \(error.localizedDescription)")
            return false
        }
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

    private func makeInstanceUniforms(
        scene: WhiteboxSceneData,
        context: RenderContext,
        viewProjection: simd_float4x4
    ) -> [InstanceUniforms] {
        var instances: [InstanceUniforms] = []
        instances.reserveCapacity(scene.structures.count + scene.entities.count)

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

            let size = SIMD3<Float>(
                Float(width) * 0.86,
                structureHeight(typeRaw: structure.typeRaw),
                Float(depth) * 0.86
            )
            let model = simd_float4x4.translation(
                SIMD3<Float>(centerX, baseElevation + (size.y * 0.5), centerZ)
            ) * simd_float4x4.scale(size)

            instances.append(
                InstanceUniforms(
                    modelViewProjection: viewProjection * model,
                    modelMatrix: model,
                    tintColor: SIMD4<Float>(structureColor(typeRaw: structure.typeRaw), 1)
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

            let size: SIMD3<Float>
            let tint: SIMD3<Float>
            if marker.category == WhiteboxEntityCategory.enemy.rawValue {
                size = SIMD3<Float>(0.34, 0.34, 0.34)
                tint = SIMD3<Float>(0.93, 0.27, 0.18)
            } else {
                size = SIMD3<Float>(0.14, 0.14, 0.14)
                tint = SIMD3<Float>(1.0, 0.82, 0.30)
            }

            let model = simd_float4x4.translation(
                SIMD3<Float>(centerX, baseElevation + (size.y * 0.5) + 0.04, centerZ)
            ) * simd_float4x4.scale(size)

            instances.append(
                InstanceUniforms(
                    modelViewProjection: viewProjection * model,
                    modelMatrix: model,
                    tintColor: SIMD4<Float>(tint, 1)
                )
            )
        }

        return instances
    }

    private func structureHeight(typeRaw: UInt32) -> Float {
        switch typeRaw {
        case WhiteboxStructureTypeID.wall.rawValue:
            return 0.40
        case WhiteboxStructureTypeID.turretMount.rawValue:
            return 1.10
        case WhiteboxStructureTypeID.miner.rawValue:
            return 0.70
        case WhiteboxStructureTypeID.smelter.rawValue:
            return 0.80
        case WhiteboxStructureTypeID.assembler.rawValue:
            return 0.70
        case WhiteboxStructureTypeID.ammoModule.rawValue:
            return 0.62
        case WhiteboxStructureTypeID.powerPlant.rawValue:
            return 1.20
        case WhiteboxStructureTypeID.conveyor.rawValue:
            return 0.15
        case WhiteboxStructureTypeID.storage.rawValue:
            return 0.80
        case WhiteboxStructureTypeID.hq.rawValue:
            return 1.35
        default:
            return 0.6
        }
    }

    private func structureColor(typeRaw: UInt32) -> SIMD3<Float> {
        switch typeRaw {
        case WhiteboxStructureTypeID.wall.rawValue:
            return SIMD3<Float>(0.60, 0.60, 0.60)
        case WhiteboxStructureTypeID.turretMount.rawValue:
            return SIMD3<Float>(0.20, 0.50, 0.80)
        case WhiteboxStructureTypeID.miner.rawValue:
            return SIMD3<Float>(0.80, 0.60, 0.20)
        case WhiteboxStructureTypeID.smelter.rawValue:
            return SIMD3<Float>(0.90, 0.30, 0.10)
        case WhiteboxStructureTypeID.assembler.rawValue:
            return SIMD3<Float>(0.30, 0.70, 0.30)
        case WhiteboxStructureTypeID.ammoModule.rawValue:
            return SIMD3<Float>(0.80, 0.20, 0.20)
        case WhiteboxStructureTypeID.powerPlant.rawValue:
            return SIMD3<Float>(0.90, 0.90, 0.20)
        case WhiteboxStructureTypeID.conveyor.rawValue:
            return SIMD3<Float>(0.50, 0.50, 0.70)
        case WhiteboxStructureTypeID.storage.rawValue:
            return SIMD3<Float>(0.60, 0.40, 0.20)
        case WhiteboxStructureTypeID.hq.rawValue:
            return SIMD3<Float>(0.25, 0.80, 0.90)
        default:
            return SIMD3<Float>(0.72, 0.74, 0.78)
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

    private func makeCubeMesh(device: MTLDevice) throws -> WhiteboxMesh {
        if MemoryLayout<PackedWhiteboxVertex>.stride != 20 {
            throw NSError(
                domain: "WhiteboxMeshRenderer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "PackedWhiteboxVertex stride is \(MemoryLayout<PackedWhiteboxVertex>.stride), expected 20."]
            )
        }

        let faces: [(normal: SIMD3<Float>, corners: [SIMD3<Float>])] = [
            (
                SIMD3<Float>(0, 0, 1),
                [
                    SIMD3<Float>(-0.5, -0.5, 0.5),
                    SIMD3<Float>(0.5, -0.5, 0.5),
                    SIMD3<Float>(0.5, 0.5, 0.5),
                    SIMD3<Float>(-0.5, 0.5, 0.5)
                ]
            ),
            (
                SIMD3<Float>(0, 0, -1),
                [
                    SIMD3<Float>(0.5, -0.5, -0.5),
                    SIMD3<Float>(-0.5, -0.5, -0.5),
                    SIMD3<Float>(-0.5, 0.5, -0.5),
                    SIMD3<Float>(0.5, 0.5, -0.5)
                ]
            ),
            (
                SIMD3<Float>(-1, 0, 0),
                [
                    SIMD3<Float>(-0.5, -0.5, -0.5),
                    SIMD3<Float>(-0.5, -0.5, 0.5),
                    SIMD3<Float>(-0.5, 0.5, 0.5),
                    SIMD3<Float>(-0.5, 0.5, -0.5)
                ]
            ),
            (
                SIMD3<Float>(1, 0, 0),
                [
                    SIMD3<Float>(0.5, -0.5, 0.5),
                    SIMD3<Float>(0.5, -0.5, -0.5),
                    SIMD3<Float>(0.5, 0.5, -0.5),
                    SIMD3<Float>(0.5, 0.5, 0.5)
                ]
            ),
            (
                SIMD3<Float>(0, 1, 0),
                [
                    SIMD3<Float>(-0.5, 0.5, 0.5),
                    SIMD3<Float>(0.5, 0.5, 0.5),
                    SIMD3<Float>(0.5, 0.5, -0.5),
                    SIMD3<Float>(-0.5, 0.5, -0.5)
                ]
            ),
            (
                SIMD3<Float>(0, -1, 0),
                [
                    SIMD3<Float>(-0.5, -0.5, -0.5),
                    SIMD3<Float>(0.5, -0.5, -0.5),
                    SIMD3<Float>(0.5, -0.5, 0.5),
                    SIMD3<Float>(-0.5, -0.5, 0.5)
                ]
            )
        ]

        var vertices: [PackedWhiteboxVertex] = []
        var indices: [UInt16] = []
        vertices.reserveCapacity(24)
        indices.reserveCapacity(36)

        for face in faces {
            let baseIndex = UInt16(vertices.count)
            for corner in face.corners {
                vertices.append(
                    PackedWhiteboxVertex(
                        px: corner.x,
                        py: corner.y,
                        pz: corner.z,
                        nx: packHalf(face.normal.x),
                        ny: packHalf(face.normal.y),
                        nz: packHalf(face.normal.z)
                    )
                )
            }

            indices.append(contentsOf: [
                baseIndex, baseIndex + 1, baseIndex + 2,
                baseIndex + 2, baseIndex + 3, baseIndex
            ])
        }

        guard let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<PackedWhiteboxVertex>.stride * vertices.count
        ) else {
            throw NSError(domain: "WhiteboxMeshRenderer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate vertex buffer."])
        }

        guard let indexBuffer = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt16>.stride * indices.count
        ) else {
            throw NSError(domain: "WhiteboxMeshRenderer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate index buffer."])
        }

        return WhiteboxMesh(
            vertexBuffer: vertexBuffer,
            indexBuffer: indexBuffer,
            indexCount: indices.count
        )
    }

    private func packHalf(_ value: Float) -> UInt16 {
        Float16(value).bitPattern
    }

    private func logResourceIssue(_ message: String) {
        guard !hasLoggedResourceIssue else { return }
        hasLoggedResourceIssue = true
        fputs("FactoryDefense WhiteboxMeshRenderer: \(message)\n", stderr)
        RenderDiagnostics.post("Whitebox mesh renderer issue: \(message)")
    }
}
