import CoreGraphics
import Foundation
import Metal
import MetalKit
import GameSimulation

@MainActor
public final class FactoryRenderer: NSObject {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue

    public var qualityPreset: QualityPreset
    public var debugMode: DebugVisualizationMode
    public var renderGraph: RenderGraph
    public var worldState: WorldState

    public var camera: IsometricCamera
    public let renderResources: RenderResources
    public let timingCapture: FrameTimingCapture
    public let shaderVariants: ShaderVariantLibrary

    public init?(
        device: MTLDevice? = MTLCreateSystemDefaultDevice(),
        qualityPreset: QualityPreset = .mobileBalanced,
        debugMode: DebugVisualizationMode = .none,
        worldState: WorldState = .bootstrap()
    ) {
        guard let device, let queue = device.makeCommandQueue() else {
            return nil
        }

        self.device = device
        self.commandQueue = queue
        self.qualityPreset = qualityPreset
        self.debugMode = debugMode
        self.renderGraph = .default()
        self.worldState = worldState
        self.camera = IsometricCamera()
        self.renderResources = RenderResources()
        self.timingCapture = FrameTimingCapture()
        self.shaderVariants = ShaderVariantLibrary()

        super.init()
    }

    public func attach(to view: MTKView) {
        view.device = device
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.preferredFramesPerSecond = 60
        view.delegate = self
    }

    public func recentFrameTimings() -> [RenderFrameTiming] {
        timingCapture.recent()
    }
}

@MainActor
extension FactoryRenderer: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // View size is consumed on every draw through RenderContext.
        _ = size
    }

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        renderResources.resizeIfNeeded(
            device: device,
            drawableSize: view.drawableSize,
            qualityPreset: qualityPreset,
            drawablePixelFormat: view.colorPixelFormat,
            depthPixelFormat: view.depthStencilPixelFormat
        )

        timingCapture.beginFrame()
        commandBuffer.label = "FactoryDefenseFrame"

        let context = RenderContext(
            device: device,
            drawableSize: view.drawableSize,
            worldState: worldState,
            qualityPreset: qualityPreset,
            debugMode: debugMode,
            currentDrawable: drawable,
            renderResources: renderResources,
            timingCapture: timingCapture,
            shaderVariants: shaderVariants
        )

        renderGraph.execute(context: context, commandBuffer: commandBuffer)

        timingCapture.endEncoding(commandBuffer: commandBuffer)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
