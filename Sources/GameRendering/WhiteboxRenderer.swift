import Foundation
import Metal

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
    var entityCount: UInt32
    var highlightedX: Int32
    var highlightedY: Int32
    var placementResultRaw: Int32
    var cameraPanX: Float
    var cameraPanY: Float
    var cameraZoom: Float
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

private struct WhiteboxEntityShader {
    var x: Int32
    var y: Int32
    var category: UInt32
    var _pad0: UInt32 = 0
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
            entityCount: UInt32(scene.entities.count),
            highlightedX: Int32(context.highlightedCell?.x ?? -1),
            highlightedY: Int32(context.highlightedCell?.y ?? -1),
            placementResultRaw: Int32(context.placementResult.rawValue),
            cameraPanX: context.cameraState.pan.x,
            cameraPanY: context.cameraState.pan.y,
            cameraZoom: context.cameraState.zoom,
            _padding0: 0
        )

        let blockedBuffer = makePointBuffer(context.device, points: scene.blockedCells)
        let restrictedBuffer = makePointBuffer(context.device, points: scene.restrictedCells)
        let rampBuffer = makeRampBuffer(context.device, ramps: scene.ramps)
        let entityBuffer = makeEntityBuffer(context.device, entities: scene.entities)

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "WhiteboxBoardCompute"
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(drawableTexture, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<WhiteboxUniforms>.stride, index: 0)
        encoder.setBuffer(blockedBuffer, offset: 0, index: 1)
        encoder.setBuffer(restrictedBuffer, offset: 0, index: 2)
        encoder.setBuffer(rampBuffer, offset: 0, index: 3)
        encoder.setBuffer(entityBuffer, offset: 0, index: 4)

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

    private func makeEntityBuffer(_ device: MTLDevice, entities: [WhiteboxEntityMarker]) -> MTLBuffer? {
        guard !entities.isEmpty else { return nil }
        var payload = entities.map { WhiteboxEntityShader(x: $0.x, y: $0.y, category: $0.category) }
        return device.makeBuffer(
            bytes: &payload,
            length: MemoryLayout<WhiteboxEntityShader>.stride * payload.count
        )
    }
}
