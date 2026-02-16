import Foundation
import Metal

public struct WhiteboxMeshGPU {
    public var vertexBuffer: MTLBuffer
    public var indexBuffer: MTLBuffer
    public var indexCount: Int

    public init(vertexBuffer: MTLBuffer, indexBuffer: MTLBuffer, indexCount: Int) {
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        self.indexCount = indexCount
    }
}

public protocol MeshProvider {
    func mesh(for id: MeshID) -> WhiteboxMeshGPU?
}

public enum MeshID: Int, CaseIterable, Hashable, Sendable {
    case wall
    case turretMount
    case miner
    case smelter
    case assembler
    case ammoModule
    case powerPlant
    case conveyor
    case storage
    case hq

    case swarmling
    case droneScout
    case raider
    case breacher
    case artilleryBug
    case overseer

    case lightBallisticProjectile
    case heavyBallisticProjectile
    case plasmaProjectile

    case gridTile
    case ramp
    case baseCore
    case resourceNode

    static var renderOrder: [MeshID] {
        allCases
    }
}

public final class WhiteboxMeshLibrary: MeshProvider {
    private var meshes: [MeshID: WhiteboxMeshGPU] = [:]

    public init(device: MTLDevice) {
        for meshID in MeshID.allCases {
            guard let cpuMesh = WhiteboxAssetCatalog.makeMesh(for: meshID) else { continue }
            guard let gpuMesh = makeGPUMesh(device: device, mesh: cpuMesh) else { continue }
            meshes[meshID] = gpuMesh
        }
    }

    public func mesh(for id: MeshID) -> WhiteboxMeshGPU? {
        meshes[id]
    }

    private func makeGPUMesh(device: MTLDevice, mesh: WhiteboxPrimitiveMesh) -> WhiteboxMeshGPU? {
        guard !mesh.vertices.isEmpty, !mesh.indices.isEmpty else { return nil }

        guard let vertexBuffer = device.makeBuffer(
            bytes: mesh.vertices,
            length: MemoryLayout<PackedWhiteboxVertex>.stride * mesh.vertices.count
        ) else {
            return nil
        }

        guard let indexBuffer = device.makeBuffer(
            bytes: mesh.indices,
            length: MemoryLayout<UInt16>.stride * mesh.indices.count
        ) else {
            return nil
        }

        return WhiteboxMeshGPU(
            vertexBuffer: vertexBuffer,
            indexBuffer: indexBuffer,
            indexCount: mesh.indices.count
        )
    }
}
