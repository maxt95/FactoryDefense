import CoreGraphics
import Foundation
import Metal
import MetalKit
import QuartzCore
import GameSimulation

public enum QualityPreset: String, Codable, CaseIterable, Sendable {
    case mobileBalanced
    case tabletHigh
    case macCinematic
}

public enum DebugVisualizationMode: String, Codable, CaseIterable, Sendable {
    case none
    case normals
    case depth
    case overdraw
    case nanInf
    case wireframe
    case turretRanges
    case enemyPaths
    case tactical
}

public struct RenderContext {
    public var device: MTLDevice
    public var drawableSize: CGSize
    public var viewSizePoints: CGSize
    public var drawableScaleX: Float
    public var drawableScaleY: Float
    public var worldState: WorldState
    public var qualityPreset: QualityPreset
    public var debugMode: DebugVisualizationMode
    public var cameraState: WhiteboxCameraState
    public var highlightedCell: GridPosition?
    public var highlightedPath: [GridPosition]
    public var highlightedStructure: StructureType?
    public var placementResult: PlacementResult

    public var currentDrawable: CAMetalDrawable?
    public var renderResources: RenderResources
    public var timingCapture: FrameTimingCapture
    public var shaderVariants: ShaderVariantLibrary
    public var whiteboxRenderer: WhiteboxRenderer
    public var whiteboxMeshRenderer: WhiteboxMeshRenderer

    public init(
        device: MTLDevice,
        drawableSize: CGSize,
        viewSizePoints: CGSize,
        drawableScaleX: Float,
        drawableScaleY: Float,
        worldState: WorldState,
        qualityPreset: QualityPreset,
        debugMode: DebugVisualizationMode,
        cameraState: WhiteboxCameraState = WhiteboxCameraState(),
        highlightedCell: GridPosition? = nil,
        highlightedPath: [GridPosition] = [],
        highlightedStructure: StructureType? = nil,
        placementResult: PlacementResult = .ok,
        currentDrawable: CAMetalDrawable?,
        renderResources: RenderResources,
        timingCapture: FrameTimingCapture,
        shaderVariants: ShaderVariantLibrary,
        whiteboxRenderer: WhiteboxRenderer,
        whiteboxMeshRenderer: WhiteboxMeshRenderer
    ) {
        self.device = device
        self.drawableSize = drawableSize
        self.viewSizePoints = viewSizePoints
        self.drawableScaleX = drawableScaleX
        self.drawableScaleY = drawableScaleY
        self.worldState = worldState
        self.qualityPreset = qualityPreset
        self.debugMode = debugMode
        self.cameraState = cameraState
        self.highlightedCell = highlightedCell
        self.highlightedPath = highlightedPath
        self.highlightedStructure = highlightedStructure
        self.placementResult = placementResult
        self.currentDrawable = currentDrawable
        self.renderResources = renderResources
        self.timingCapture = timingCapture
        self.shaderVariants = shaderVariants
        self.whiteboxRenderer = whiteboxRenderer
        self.whiteboxMeshRenderer = whiteboxMeshRenderer
    }
}

public protocol RenderPassNode {
    var id: String { get }
    func encode(context: RenderContext, commandBuffer: MTLCommandBuffer)
}

private func beginRenderPass(
    commandBuffer: MTLCommandBuffer,
    descriptor: MTLRenderPassDescriptor?,
    label: String
) -> MTLRenderCommandEncoder? {
    guard let descriptor else { return nil }
    let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
    encoder?.label = label
    return encoder
}

public struct DepthPrepassNode: RenderPassNode {
    public let id = "depth_prepass"
    public init() {}

    public func encode(context: RenderContext, commandBuffer: MTLCommandBuffer) {
        commandBuffer.pushDebugGroup("DepthPrepass")
        let encoder = beginRenderPass(
            commandBuffer: commandBuffer,
            descriptor: context.renderResources.depthPrepassDescriptor(),
            label: "DepthPrepass"
        )
        encoder?.endEncoding()
        commandBuffer.popDebugGroup()
    }
}

public struct ShadowCascadeNode: RenderPassNode {
    public let id = "shadow_cascades"
    public init() {}

    public func encode(context: RenderContext, commandBuffer: MTLCommandBuffer) {
        commandBuffer.pushDebugGroup("ShadowCascades")
        let encoder = beginRenderPass(
            commandBuffer: commandBuffer,
            descriptor: context.renderResources.shadowPassDescriptor(),
            label: "ShadowCascades"
        )
        encoder?.endEncoding()
        commandBuffer.popDebugGroup()
    }
}

public struct OpaquePBRNode: RenderPassNode {
    public let id = "opaque_pbr"
    public init() {}

    public func encode(context: RenderContext, commandBuffer: MTLCommandBuffer) {
        commandBuffer.pushDebugGroup("OpaquePBR")

        let variant = context.shaderVariants.activeVariant(for: context.qualityPreset, debugMode: context.debugMode)
        _ = context.shaderVariants.functionConstants(for: variant)

        let encoder = beginRenderPass(
            commandBuffer: commandBuffer,
            descriptor: context.renderResources.drawableOpaqueDescriptor(drawableTexture: context.currentDrawable?.texture),
            label: "OpaquePBR(normal:\(variant.enableNormalMap), emission:\(variant.enableEmission), fog:\(variant.enableFog))"
        )
        if let encoder {
            context.whiteboxMeshRenderer.encode(context: context, encoder: encoder)
        }
        encoder?.endEncoding()
        commandBuffer.popDebugGroup()
    }
}

public struct TransparentVFXNode: RenderPassNode {
    public let id = "transparent_vfx"
    public init() {}

    public func encode(context: RenderContext, commandBuffer: MTLCommandBuffer) {
        commandBuffer.pushDebugGroup("TransparentVFX")
        let encoder = beginRenderPass(
            commandBuffer: commandBuffer,
            descriptor: context.renderResources.transparentPassDescriptor(),
            label: "TransparentVFX"
        )
        encoder?.endEncoding()
        commandBuffer.popDebugGroup()
    }
}

public struct VolumetricFogNode: RenderPassNode {
    public let id = "volumetric_fog"
    public init() {}

    public func encode(context: RenderContext, commandBuffer: MTLCommandBuffer) {
        commandBuffer.pushDebugGroup("VolumetricFog")
        let encoder = beginRenderPass(
            commandBuffer: commandBuffer,
            descriptor: context.renderResources.volumetricPassDescriptor(),
            label: "VolumetricFog"
        )
        encoder?.endEncoding()
        commandBuffer.popDebugGroup()
    }
}

public struct PostProcessingNode: RenderPassNode {
    public let id = "post_processing"
    public init() {}

    public func encode(context: RenderContext, commandBuffer: MTLCommandBuffer) {
        commandBuffer.pushDebugGroup("PostProcessing")
        let encoder = beginRenderPass(
            commandBuffer: commandBuffer,
            descriptor: context.renderResources.postPassDescriptor(),
            label: "PostProcessing"
        )
        encoder?.endEncoding()
        commandBuffer.popDebugGroup()
    }
}

public struct WhiteboxBoardNode: RenderPassNode {
    public let id = "whitebox_board"
    public init() {}

    public func encode(context: RenderContext, commandBuffer: MTLCommandBuffer) {
        commandBuffer.pushDebugGroup("WhiteboxBoard")
        context.whiteboxRenderer.encode(context: context, commandBuffer: commandBuffer)
        commandBuffer.popDebugGroup()
    }
}

public struct UICompositeNode: RenderPassNode {
    public let id = "ui_composite"
    public init() {}

    public func encode(context: RenderContext, commandBuffer: MTLCommandBuffer) {
        commandBuffer.pushDebugGroup("UIComposite")
        let descriptor = context.renderResources.uiCompositeDescriptor(drawableTexture: context.currentDrawable?.texture)
        let encoder = beginRenderPass(
            commandBuffer: commandBuffer,
            descriptor: descriptor,
            label: "UIComposite"
        )
        encoder?.endEncoding()
        commandBuffer.popDebugGroup()
    }
}
