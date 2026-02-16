import Metal
import XCTest
@testable import GameRendering

final class MeshProviderTests: XCTestCase {
    func testCompositeProviderUsesPrimaryWhenAvailable() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }

        let primaryMesh = try makeDummyMesh(device: device)
        let fallbackMesh = try makeDummyMesh(device: device)

        let primary = FixedMeshProvider(meshes: [.wall: primaryMesh])
        let fallback = FixedMeshProvider(meshes: [.wall: fallbackMesh])
        let composite = CompositeMeshProvider(primary: primary, fallback: fallback)

        let resolved = composite.mesh(for: .wall)
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved?.vertexBuffer === primaryMesh.vertexBuffer)
    }

    func testCompositeProviderFallsBackWhenPrimaryMissing() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }

        let fallbackMesh = try makeDummyMesh(device: device)

        let primary = FixedMeshProvider(meshes: [:])
        let fallback = FixedMeshProvider(meshes: [.hq: fallbackMesh])
        let composite = CompositeMeshProvider(primary: primary, fallback: fallback)

        let resolved = composite.mesh(for: .hq)
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved?.vertexBuffer === fallbackMesh.vertexBuffer)
    }

    private func makeDummyMesh(device: MTLDevice) throws -> WhiteboxMeshGPU {
        guard let vertexBuffer = device.makeBuffer(length: MemoryLayout<PackedWhiteboxVertex>.stride, options: []) else {
            throw XCTSkip("Unable to allocate dummy vertex buffer")
        }
        guard let indexBuffer = device.makeBuffer(length: MemoryLayout<UInt16>.stride * 3, options: []) else {
            throw XCTSkip("Unable to allocate dummy index buffer")
        }

        return WhiteboxMeshGPU(vertexBuffer: vertexBuffer, indexBuffer: indexBuffer, indexCount: 3)
    }
}

private struct FixedMeshProvider: MeshProvider {
    var meshes: [MeshID: WhiteboxMeshGPU]

    func mesh(for id: MeshID) -> WhiteboxMeshGPU? {
        meshes[id]
    }
}
