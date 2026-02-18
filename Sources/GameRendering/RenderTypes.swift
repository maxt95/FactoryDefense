import CoreGraphics
import Foundation
import Metal
import MetalKit
import QuartzCore
import simd
import GameSimulation

public enum ViewMode: String, Codable, CaseIterable, Sendable {
    case baseView
    case fpsView
}

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
    case wallAmmoFlow
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
    public var highlightedAffordableCount: Int
    public var highlightedStructure: StructureType?
    public var placementResult: PlacementResult
    public var viewMode: ViewMode
    public var fpsViewProjection: simd_float4x4?

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
        highlightedAffordableCount: Int = 0,
        highlightedStructure: StructureType? = nil,
        placementResult: PlacementResult = .ok,
        viewMode: ViewMode = .baseView,
        fpsViewProjection: simd_float4x4? = nil,
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
        self.highlightedAffordableCount = max(0, highlightedAffordableCount)
        self.highlightedStructure = highlightedStructure
        self.placementResult = placementResult
        self.viewMode = viewMode
        self.fpsViewProjection = fpsViewProjection
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

public struct FPSSkyboxNode: RenderPassNode {
    public let id = "fps_skybox"
    public init() {}

    public func encode(context: RenderContext, commandBuffer: MTLCommandBuffer) {
        guard context.viewMode == .fpsView else { return }
        commandBuffer.pushDebugGroup("FPSSkybox")

        // Draw sky to the drawable texture directly
        guard let drawableTexture = context.currentDrawable?.texture else {
            commandBuffer.popDebugGroup()
            return
        }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawableTexture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.15, green: 0.35, blue: 0.65, alpha: 1)

        // Also clear depth so sky sits behind everything
        if let depthTexture = context.renderResources.drawableDepthTexture ?? context.renderResources.depthTexture {
            descriptor.depthAttachment.texture = depthTexture
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.clearDepth = 1.0
            descriptor.depthAttachment.storeAction = .store
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            commandBuffer.popDebugGroup()
            return
        }
        encoder.label = "FPSSkybox"

        // Build sky pipeline lazily
        if let pipeline = context.shaderVariants.skyPipelineState(
            device: context.device,
            colorPixelFormat: drawableTexture.pixelFormat,
            depthPixelFormat: context.renderResources.drawableDepthTexture?.pixelFormat
                ?? context.renderResources.depthTexture?.pixelFormat
                ?? .depth32Float
        ) {
            encoder.setRenderPipelineState(pipeline)
            // Draw fullscreen triangle (3 vertices, no vertex buffer needed)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        encoder.endEncoding()
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
