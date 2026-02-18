import Foundation
import Metal
import QuartzCore

public final class RenderGraph {
    public private(set) var nodes: [any RenderPassNode]

    public init(nodes: [any RenderPassNode]) {
        self.nodes = nodes
    }

    public func setNodes(_ nodes: [any RenderPassNode]) {
        self.nodes = nodes
    }

    public func execute(context: RenderContext, commandBuffer: MTLCommandBuffer) {
        for node in nodes {
            let start = CFAbsoluteTimeGetCurrent()
            node.encode(context: context, commandBuffer: commandBuffer)
            let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1_000
            context.timingCapture.recordCheckpoint(passID: node.id, encodeMS: elapsedMS)
        }
    }

    public static func `default`() -> RenderGraph {
        RenderGraph(nodes: [
            DepthPrepassNode(),
            ShadowCascadeNode(),
            WhiteboxBoardNode(),
            OpaquePBRNode(),
            TransparentVFXNode(),
            VolumetricFogNode(),
            PostProcessingNode(),
            UICompositeNode()
        ])
    }

    /// FPS mode render graph — draws sky gradient first, then 3D meshes with fog.
    /// Skips WhiteboxBoardNode (2D compute shader is meaningless in perspective view).
    public static func fpsMode() -> RenderGraph {
        RenderGraph(nodes: [
            FPSSkyboxNode(),
            OpaquePBRNode(),
            UICompositeNode()
        ])
    }
}
