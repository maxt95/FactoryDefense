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
            OpaquePBRNode(),
            TransparentVFXNode(),
            VolumetricFogNode(),
            PostProcessingNode(),
            WhiteboxBoardNode(),
            UICompositeNode()
        ])
    }
}
