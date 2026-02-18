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

    func testMountedTurretVisualSitsAboveWallSilhouette() {
        guard let wallMesh = WhiteboxAssetCatalog.makeMesh(for: .wall),
              let turretMesh = WhiteboxAssetCatalog.makeMesh(for: .turretMount) else {
            return XCTFail("Expected wall and turret meshes")
        }

        let wallTopY = wallMesh.vertices.map(\.py).max() ?? 0
        let turretTopY = (turretMesh.vertices.map(\.py).max() ?? 0)
            + WhiteboxMeshRenderer.structureVerticalOffset(for: WhiteboxStructureTypeID.turretMount.rawValue)

        XCTAssertGreaterThan(turretTopY, wallTopY + 0.05)
    }
}
