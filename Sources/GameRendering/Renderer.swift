import CoreGraphics
import Foundation
import Metal
import MetalKit
import GameSimulation
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
public final class FactoryRenderer: NSObject {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue

    public var qualityPreset: QualityPreset
    public var debugMode: DebugVisualizationMode
    public var renderGraph: RenderGraph
    public var worldState: WorldState
    public var cameraState: WhiteboxCameraState
    public var highlightedCell: GridPosition?
    public var highlightedPath: [GridPosition]
    public var highlightedStructure: StructureType?
    public var placementResult: PlacementResult

    public var camera: IsometricCamera
    public let renderResources: RenderResources
    public let timingCapture: FrameTimingCapture
    public let shaderVariants: ShaderVariantLibrary
    public let whiteboxRenderer: WhiteboxRenderer
    public let whiteboxMeshRenderer: WhiteboxMeshRenderer
    private let picker: WhiteboxPicker
    private var hasLoggedCommandBufferError = false

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
        self.cameraState = WhiteboxCameraState()
        self.highlightedCell = nil
        self.highlightedPath = []
        self.highlightedStructure = nil
        self.placementResult = .ok
        self.camera = IsometricCamera()
        self.renderResources = RenderResources()
        self.timingCapture = FrameTimingCapture()
        self.shaderVariants = ShaderVariantLibrary()
        self.whiteboxRenderer = WhiteboxRenderer()
        self.whiteboxMeshRenderer = WhiteboxMeshRenderer()
        self.picker = WhiteboxPicker()

        super.init()
    }

    public func attach(to view: MTKView) {
        view.device = device
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.preferredFramesPerSecond = 60
        view.delegate = self
    }

    public func recentFrameTimings() -> [RenderFrameTiming] {
        timingCapture.recent()
    }

    public func panBoard(deltaX: Float, deltaY: Float) {
        cameraState.panBy(deltaX: deltaX, deltaY: deltaY)
    }

    public func zoomBoard(scale: Float) {
        cameraState.zoomBy(scale: scale)
    }

    public func boardPosition(at point: CGPoint, viewport: CGSize) -> GridPosition? {
        picker.gridPosition(
            at: point,
            viewport: viewport,
            board: worldState.board,
            camera: cameraState
        )
    }

    public func setPlacementHighlight(
        cell: GridPosition?,
        path: [GridPosition] = [],
        structure: StructureType?,
        result: PlacementResult
    ) {
        highlightedCell = cell
        highlightedPath = path
        highlightedStructure = structure
        placementResult = result
    }

    public func useProceduralMeshes() {
        whiteboxMeshRenderer.useProceduralMeshes()
    }

    public func useModelIOMeshes(assetURLs: [MeshID: URL]) {
        whiteboxMeshRenderer.useModelIOMeshes(assetURLs: assetURLs)
    }
}

@MainActor
extension FactoryRenderer: MTKViewDelegate {
    private func resolvedDrawableScale(for view: MTKView) -> (x: Float, y: Float) {
#if os(macOS)
        let backingScale = Float(view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0)
        let scale = max(1.0, backingScale)
        return (scale, scale)
#elseif canImport(UIKit)
        let contentScale = Float(max(1.0, view.contentScaleFactor))
        return (contentScale, contentScale)
#else
        return (1.0, 1.0)
#endif
    }

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

        let scale = resolvedDrawableScale(for: view)
        let scaleX = max(1.0, scale.x)
        let scaleY = max(1.0, scale.y)
        let viewSizePoints = CGSize(
            width: max(1, view.drawableSize.width / CGFloat(scaleX)),
            height: max(1, view.drawableSize.height / CGFloat(scaleY))
        )

        let context = RenderContext(
            device: device,
            drawableSize: view.drawableSize,
            viewSizePoints: viewSizePoints,
            drawableScaleX: scaleX,
            drawableScaleY: scaleY,
            worldState: worldState,
            qualityPreset: qualityPreset,
            debugMode: debugMode,
            cameraState: cameraState,
            highlightedCell: highlightedCell,
            highlightedPath: highlightedPath,
            highlightedStructure: highlightedStructure,
            placementResult: placementResult,
            currentDrawable: drawable,
            renderResources: renderResources,
            timingCapture: timingCapture,
            shaderVariants: shaderVariants,
            whiteboxRenderer: whiteboxRenderer,
            whiteboxMeshRenderer: whiteboxMeshRenderer
        )

        renderGraph.execute(context: context, commandBuffer: commandBuffer)

        timingCapture.endEncoding(commandBuffer: commandBuffer)
        commandBuffer.addCompletedHandler { [weak self] buffer in
            guard let self, let error = buffer.error else { return }
            Task { @MainActor in
                guard !self.hasLoggedCommandBufferError else { return }
                self.hasLoggedCommandBufferError = true
                fputs("FactoryDefense Renderer command buffer error: \(error.localizedDescription)\n", stderr)
                RenderDiagnostics.post("Renderer command buffer error: \(error.localizedDescription)")
            }
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
