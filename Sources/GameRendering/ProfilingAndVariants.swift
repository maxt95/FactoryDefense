import Foundation
import Metal

public struct ShaderVariantKey: Hashable, Sendable {
    public var enableNormalMap: Bool
    public var enableEmission: Bool
    public var enableFog: Bool

    public init(enableNormalMap: Bool, enableEmission: Bool, enableFog: Bool) {
        self.enableNormalMap = enableNormalMap
        self.enableEmission = enableEmission
        self.enableFog = enableFog
    }
}

public final class ShaderVariantLibrary {
    private var constantsCache: [ShaderVariantKey: MTLFunctionConstantValues] = [:]
    private var cachedSkyPipeline: MTLRenderPipelineState?
    private var skyPipelineColorFormat: MTLPixelFormat?
    private var skyPipelineDepthFormat: MTLPixelFormat?

    public init() {}

    public func activeVariant(for qualityPreset: QualityPreset, debugMode: DebugVisualizationMode) -> ShaderVariantKey {
        switch qualityPreset {
        case .mobileBalanced:
            return ShaderVariantKey(enableNormalMap: true, enableEmission: false, enableFog: debugMode == .none)
        case .tabletHigh:
            return ShaderVariantKey(enableNormalMap: true, enableEmission: true, enableFog: true)
        case .macCinematic:
            return ShaderVariantKey(enableNormalMap: true, enableEmission: true, enableFog: true)
        }
    }

    public func skyPipelineState(
        device: MTLDevice,
        colorPixelFormat: MTLPixelFormat,
        depthPixelFormat: MTLPixelFormat
    ) -> MTLRenderPipelineState? {
        if let cached = cachedSkyPipeline,
           skyPipelineColorFormat == colorPixelFormat,
           skyPipelineDepthFormat == depthPixelFormat {
            return cached
        }

        guard let library = try? device.makeDefaultLibrary(bundle: .module),
              let vertexFunc = library.makeFunction(name: "sky_vertex"),
              let fragmentFunc = library.makeFunction(name: "sky_fragment") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "SkyGradientPipeline"
        descriptor.vertexFunction = vertexFunc
        descriptor.fragmentFunction = fragmentFunc
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.depthAttachmentPixelFormat = depthPixelFormat

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }

        cachedSkyPipeline = pipeline
        skyPipelineColorFormat = colorPixelFormat
        skyPipelineDepthFormat = depthPixelFormat
        return pipeline
    }

    public func functionConstants(for key: ShaderVariantKey) -> MTLFunctionConstantValues {
        if let cached = constantsCache[key] {
            return cached
        }

        let values = MTLFunctionConstantValues()
        var normal = key.enableNormalMap
        var emission = key.enableEmission
        var fog = key.enableFog
        values.setConstantValue(&normal, type: .bool, index: 0)
        values.setConstantValue(&emission, type: .bool, index: 1)
        values.setConstantValue(&fog, type: .bool, index: 2)

        constantsCache[key] = values
        return values
    }
}

public struct RenderFrameTiming: Sendable {
    public var frameIndex: UInt64
    public var cpuFrameMS: Double
    public var passEncodeMS: [String: Double]
    public var gpuCompletionMS: Double?

    public init(frameIndex: UInt64, cpuFrameMS: Double, passEncodeMS: [String: Double], gpuCompletionMS: Double?) {
        self.frameIndex = frameIndex
        self.cpuFrameMS = cpuFrameMS
        self.passEncodeMS = passEncodeMS
        self.gpuCompletionMS = gpuCompletionMS
    }
}

public final class FrameTimingCapture: @unchecked Sendable {
    private let lock = NSLock()

    private var frameStartTime: CFAbsoluteTime = 0
    private var submitTime: CFAbsoluteTime = 0
    private var frameIndex: UInt64 = 0
    private var currentPasses: [String: Double] = [:]

    private let capacity: Int
    private var recentFrames: [RenderFrameTiming] = []

    public init(capacity: Int = 180) {
        self.capacity = max(1, capacity)
    }

    public func beginFrame() {
        lock.lock()
        frameIndex &+= 1
        frameStartTime = CFAbsoluteTimeGetCurrent()
        currentPasses.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    public func recordCheckpoint(passID: String, encodeMS: Double) {
        lock.lock()
        currentPasses[passID] = encodeMS
        lock.unlock()
    }

    public func endEncoding(commandBuffer: MTLCommandBuffer) {
        lock.lock()
        submitTime = CFAbsoluteTimeGetCurrent()

        let cpuMS = (submitTime - frameStartTime) * 1_000
        let frame = RenderFrameTiming(frameIndex: frameIndex, cpuFrameMS: cpuMS, passEncodeMS: currentPasses, gpuCompletionMS: nil)
        append(frame: frame)
        lock.unlock()

        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            let completionTime = CFAbsoluteTimeGetCurrent()
            self.lock.lock()
            if var latest = self.recentFrames.last {
                latest.gpuCompletionMS = max(0, (completionTime - self.submitTime) * 1_000)
                self.recentFrames[self.recentFrames.count - 1] = latest
            }
            self.lock.unlock()
        }
    }

    public func recent() -> [RenderFrameTiming] {
        lock.lock()
        defer { lock.unlock() }
        return recentFrames
    }

    private func append(frame: RenderFrameTiming) {
        recentFrames.append(frame)
        if recentFrames.count > capacity {
            recentFrames.removeFirst(recentFrames.count - capacity)
        }
    }
}
