import Metal
import XCTest
@testable import GameRendering

final class WhiteboxMeshCatalogTests: XCTestCase {
    func testAssetCatalogBuildsAllMeshIDs() {
        XCTAssertEqual(MemoryLayout<PackedWhiteboxVertex>.stride, 20)

        for meshID in MeshID.allCases {
            let mesh = WhiteboxAssetCatalog.makeMesh(for: meshID)
            XCTAssertNotNil(mesh, "Missing mesh for \(meshID)")
            XCTAssertGreaterThan(mesh?.vertices.count ?? 0, 0, "Mesh has no vertices for \(meshID)")
            XCTAssertGreaterThan(mesh?.indices.count ?? 0, 0, "Mesh has no indices for \(meshID)")
        }
    }

    func testMeshLibraryUploadsAllMeshIDs() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }

        let library = WhiteboxMeshLibrary(device: device)
        for meshID in MeshID.allCases {
            let mesh = library.mesh(for: meshID)
            XCTAssertNotNil(mesh, "Missing GPU mesh for \(meshID)")
            XCTAssertGreaterThan(mesh?.indexCount ?? 0, 0, "Mesh has no indices for \(meshID)")
        }
    }
}
