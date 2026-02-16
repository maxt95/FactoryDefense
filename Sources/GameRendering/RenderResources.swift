import CoreGraphics
import Foundation
import Metal

public final class RenderResources {
    public private(set) var scaledSize: CGSize = .zero

    public private(set) var depthTexture: MTLTexture?
    public private(set) var shadowTexture: MTLTexture?
    public private(set) var opaqueTexture: MTLTexture?
    public private(set) var transparentTexture: MTLTexture?
    public private(set) var volumetricTexture: MTLTexture?
    public private(set) var postTexture: MTLTexture?

    public init() {}

    public func resizeIfNeeded(
        device: MTLDevice,
        drawableSize: CGSize,
        qualityPreset: QualityPreset,
        drawablePixelFormat: MTLPixelFormat,
        depthPixelFormat: MTLPixelFormat
    ) {
        guard drawableSize.width > 0, drawableSize.height > 0 else { return }

        let scale: CGFloat
        switch qualityPreset {
        case .mobileBalanced:
            scale = 0.85
        case .tabletHigh:
            scale = 1.0
        case .macCinematic:
            scale = 1.0
        }

        let width = max(1, Int((drawableSize.width * scale).rounded(.toNearestOrEven)))
        let height = max(1, Int((drawableSize.height * scale).rounded(.toNearestOrEven)))

        let newSize = CGSize(width: width, height: height)
        guard newSize != scaledSize else { return }

        scaledSize = newSize
        depthTexture = makeTexture(device: device, width: width, height: height, pixelFormat: depthPixelFormat, usage: [.renderTarget])
        shadowTexture = makeTexture(device: device, width: width, height: height, pixelFormat: .r32Float, usage: [.renderTarget, .shaderRead])
        opaqueTexture = makeTexture(device: device, width: width, height: height, pixelFormat: drawablePixelFormat, usage: [.renderTarget, .shaderRead])
        transparentTexture = makeTexture(device: device, width: width, height: height, pixelFormat: drawablePixelFormat, usage: [.renderTarget, .shaderRead])
        volumetricTexture = makeTexture(device: device, width: width, height: height, pixelFormat: .rgba16Float, usage: [.renderTarget, .shaderRead])
        postTexture = makeTexture(device: device, width: width, height: height, pixelFormat: drawablePixelFormat, usage: [.renderTarget, .shaderRead])
    }

    public func depthPrepassDescriptor() -> MTLRenderPassDescriptor? {
        guard let depthTexture else { return nil }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.depthAttachment.texture = depthTexture
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .store
        descriptor.depthAttachment.clearDepth = 1.0
        return descriptor
    }

    public func shadowPassDescriptor() -> MTLRenderPassDescriptor? {
        guard let shadowTexture else { return nil }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = shadowTexture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
        return descriptor
    }

    public func opaquePassDescriptor() -> MTLRenderPassDescriptor? {
        guard let opaqueTexture, let depthTexture else { return nil }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = opaqueTexture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
        descriptor.depthAttachment.texture = depthTexture
        descriptor.depthAttachment.loadAction = .load
        descriptor.depthAttachment.storeAction = .store
        return descriptor
    }

    public func transparentPassDescriptor() -> MTLRenderPassDescriptor? {
        guard let transparentTexture, let depthTexture else { return nil }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = transparentTexture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        descriptor.depthAttachment.texture = depthTexture
        descriptor.depthAttachment.loadAction = .load
        descriptor.depthAttachment.storeAction = .dontCare
        return descriptor
    }

    public func volumetricPassDescriptor() -> MTLRenderPassDescriptor? {
        guard let volumetricTexture else { return nil }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = volumetricTexture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1)
        return descriptor
    }

    public func postPassDescriptor() -> MTLRenderPassDescriptor? {
        guard let postTexture else { return nil }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = postTexture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        return descriptor
    }

    public func uiCompositeDescriptor(drawableTexture: MTLTexture?) -> MTLRenderPassDescriptor? {
        guard let drawableTexture else { return nil }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawableTexture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
        return descriptor
    }

    private func makeTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat,
        usage: MTLTextureUsage
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)
    }
}
