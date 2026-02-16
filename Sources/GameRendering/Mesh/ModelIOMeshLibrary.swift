import Foundation
import Metal
import MetalKit
import ModelIO

public final class ModelIOMeshLibrary: MeshProvider {
    private let device: MTLDevice
    private let assetURLs: [MeshID: URL]
    private var cache: [MeshID: WhiteboxMeshGPU?] = [:]

    public init(device: MTLDevice, assetURLs: [MeshID: URL]) {
        self.device = device
        self.assetURLs = assetURLs
    }

    public func mesh(for id: MeshID) -> WhiteboxMeshGPU? {
        if let cached = cache[id] {
            return cached
        }

        guard let assetURL = assetURLs[id] else {
            cache[id] = nil
            return nil
        }

        let loadedMesh = loadMesh(from: assetURL)
        cache[id] = loadedMesh
        return loadedMesh
    }

    private func loadMesh(from assetURL: URL) -> WhiteboxMeshGPU? {
        let allocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(
            url: assetURL,
            vertexDescriptor: makeModelIOVertexDescriptor(),
            bufferAllocator: allocator
        )

        let meshes = asset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []
        guard !meshes.isEmpty else { return nil }

        for mesh in meshes {
            if mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal) == nil {
                mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.2)
            }

            guard let mtkMesh = try? MTKMesh(mesh: mesh, device: device) else {
                continue
            }

            for submesh in mtkMesh.submeshes {
                guard submesh.primitiveType == .triangle,
                      submesh.indexType == .uint16,
                      !mtkMesh.vertexBuffers.isEmpty,
                      submesh.indexCount > 0 else {
                    continue
                }

                return WhiteboxMeshGPU(
                    vertexBuffer: mtkMesh.vertexBuffers[0].buffer,
                    indexBuffer: submesh.indexBuffer.buffer,
                    indexCount: submesh.indexCount
                )
            }
        }

        return nil
    }

    private func makeModelIOVertexDescriptor() -> MDLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .half3
        descriptor.attributes[1].offset = 12
        descriptor.attributes[1].bufferIndex = 0
        descriptor.layouts[0].stride = MemoryLayout<PackedWhiteboxVertex>.stride

        let modelIO = MTKModelIOVertexDescriptorFromMetal(descriptor)
        (modelIO.attributes[0] as? MDLVertexAttribute)?.name = MDLVertexAttributePosition
        (modelIO.attributes[1] as? MDLVertexAttribute)?.name = MDLVertexAttributeNormal
        return modelIO
    }
}
