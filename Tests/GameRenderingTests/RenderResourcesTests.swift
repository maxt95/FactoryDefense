import Metal
import XCTest
@testable import GameRendering

final class RenderResourcesTests: XCTestCase {
    func testResizeAllocatesTextures() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }

        let resources = RenderResources()
        resources.resizeIfNeeded(
            device: device,
            drawableSize: CGSize(width: 1024, height: 768),
            qualityPreset: .mobileBalanced,
            drawablePixelFormat: .bgra8Unorm_srgb,
            depthPixelFormat: .depth32Float
        )

        XCTAssertNotNil(resources.depthTexture)
        XCTAssertNotNil(resources.drawableDepthTexture)
        XCTAssertNotNil(resources.opaqueTexture)
        XCTAssertNotNil(resources.postTexture)
        XCTAssertEqual(resources.drawableDepthTexture?.width, 1024)
        XCTAssertEqual(resources.drawableDepthTexture?.height, 768)
        XCTAssertEqual(resources.drawablePixelSize.width, 1024)
        XCTAssertEqual(resources.drawablePixelSize.height, 768)
    }
}
