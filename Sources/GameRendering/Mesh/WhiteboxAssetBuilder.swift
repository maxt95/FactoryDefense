import Foundation
import simd

public struct WhiteboxAssetBuilder {
    private var vertices: [PackedWhiteboxVertex] = []
    private var indices: [UInt16] = []

    public init() {}

    public mutating func add(
        mesh: WhiteboxPrimitiveMesh,
        transform: simd_float4x4 = matrix_identity_float4x4
    ) {
        guard !mesh.vertices.isEmpty, !mesh.indices.isEmpty else { return }
        guard vertices.count + mesh.vertices.count <= Int(UInt16.max) else { return }

        let baseVertex = UInt16(vertices.count)
        let normalMatrix = simd_float3x3(
            transform.columns.0.xyz,
            transform.columns.1.xyz,
            transform.columns.2.xyz
        )

        for vertex in mesh.vertices {
            let transformedPosition = (transform * SIMD4<Float>(vertex.position, 1)).xyz
            let transformedNormal = simd_normalize(normalMatrix * vertex.normal)
            vertices.append(PackedWhiteboxVertex(position: transformedPosition, normal: transformedNormal))
        }

        indices.reserveCapacity(indices.count + mesh.indices.count)
        for index in mesh.indices {
            indices.append(baseVertex + index)
        }
    }

    public func build() -> WhiteboxPrimitiveMesh? {
        guard !vertices.isEmpty, !indices.isEmpty else { return nil }
        return WhiteboxPrimitiveMesh(vertices: vertices, indices: indices)
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}
