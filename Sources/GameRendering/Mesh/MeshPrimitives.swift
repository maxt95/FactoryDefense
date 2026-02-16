import Foundation
import simd

public enum MeshPrimitives {
    public static func box(halfExtents: SIMD3<Float>) -> WhiteboxPrimitiveMesh {
        let faces: [(normal: SIMD3<Float>, corners: [SIMD3<Float>])] = [
            (
                SIMD3<Float>(0, 0, 1),
                [
                    SIMD3<Float>(-halfExtents.x, -halfExtents.y, halfExtents.z),
                    SIMD3<Float>(halfExtents.x, -halfExtents.y, halfExtents.z),
                    SIMD3<Float>(halfExtents.x, halfExtents.y, halfExtents.z),
                    SIMD3<Float>(-halfExtents.x, halfExtents.y, halfExtents.z)
                ]
            ),
            (
                SIMD3<Float>(0, 0, -1),
                [
                    SIMD3<Float>(halfExtents.x, -halfExtents.y, -halfExtents.z),
                    SIMD3<Float>(-halfExtents.x, -halfExtents.y, -halfExtents.z),
                    SIMD3<Float>(-halfExtents.x, halfExtents.y, -halfExtents.z),
                    SIMD3<Float>(halfExtents.x, halfExtents.y, -halfExtents.z)
                ]
            ),
            (
                SIMD3<Float>(-1, 0, 0),
                [
                    SIMD3<Float>(-halfExtents.x, -halfExtents.y, -halfExtents.z),
                    SIMD3<Float>(-halfExtents.x, -halfExtents.y, halfExtents.z),
                    SIMD3<Float>(-halfExtents.x, halfExtents.y, halfExtents.z),
                    SIMD3<Float>(-halfExtents.x, halfExtents.y, -halfExtents.z)
                ]
            ),
            (
                SIMD3<Float>(1, 0, 0),
                [
                    SIMD3<Float>(halfExtents.x, -halfExtents.y, halfExtents.z),
                    SIMD3<Float>(halfExtents.x, -halfExtents.y, -halfExtents.z),
                    SIMD3<Float>(halfExtents.x, halfExtents.y, -halfExtents.z),
                    SIMD3<Float>(halfExtents.x, halfExtents.y, halfExtents.z)
                ]
            ),
            (
                SIMD3<Float>(0, 1, 0),
                [
                    SIMD3<Float>(-halfExtents.x, halfExtents.y, halfExtents.z),
                    SIMD3<Float>(halfExtents.x, halfExtents.y, halfExtents.z),
                    SIMD3<Float>(halfExtents.x, halfExtents.y, -halfExtents.z),
                    SIMD3<Float>(-halfExtents.x, halfExtents.y, -halfExtents.z)
                ]
            ),
            (
                SIMD3<Float>(0, -1, 0),
                [
                    SIMD3<Float>(-halfExtents.x, -halfExtents.y, -halfExtents.z),
                    SIMD3<Float>(halfExtents.x, -halfExtents.y, -halfExtents.z),
                    SIMD3<Float>(halfExtents.x, -halfExtents.y, halfExtents.z),
                    SIMD3<Float>(-halfExtents.x, -halfExtents.y, halfExtents.z)
                ]
            )
        ]

        var vertices: [PackedWhiteboxVertex] = []
        var indices: [UInt16] = []
        vertices.reserveCapacity(24)
        indices.reserveCapacity(36)

        for face in faces {
            let base = UInt16(vertices.count)
            for corner in face.corners {
                vertices.append(PackedWhiteboxVertex(position: corner, normal: face.normal))
            }
            indices.append(contentsOf: [
                base, base + 1, base + 2,
                base + 2, base + 3, base
            ])
        }

        return WhiteboxPrimitiveMesh(vertices: vertices, indices: indices)
    }

    public static func cylinder(radius: Float, height: Float, segments: Int = 8) -> WhiteboxPrimitiveMesh {
        let clampedSegments = max(3, segments)
        let halfHeight = height * 0.5
        var vertices: [PackedWhiteboxVertex] = []
        var indices: [UInt16] = []

        func addVertex(position: SIMD3<Float>, normal: SIMD3<Float>) {
            vertices.append(PackedWhiteboxVertex(position: position, normal: normal))
        }

        func addTri(_ a: UInt16, _ b: UInt16, _ c: UInt16) {
            indices.append(contentsOf: [a, b, c])
        }

        for index in 0..<clampedSegments {
            let t0 = (Float(index) / Float(clampedSegments)) * (.pi * 2)
            let t1 = (Float(index + 1) / Float(clampedSegments)) * (.pi * 2)
            let mid = (t0 + t1) * 0.5
            let normal = SIMD3<Float>(cos(mid), 0, sin(mid))

            let p0 = SIMD3<Float>(cos(t0) * radius, -halfHeight, sin(t0) * radius)
            let p1 = SIMD3<Float>(cos(t1) * radius, -halfHeight, sin(t1) * radius)
            let p2 = SIMD3<Float>(cos(t1) * radius, halfHeight, sin(t1) * radius)
            let p3 = SIMD3<Float>(cos(t0) * radius, halfHeight, sin(t0) * radius)

            let base = UInt16(vertices.count)
            addVertex(position: p0, normal: normal)
            addVertex(position: p1, normal: normal)
            addVertex(position: p2, normal: normal)
            addVertex(position: p3, normal: normal)
            addTri(base, base + 1, base + 2)
            addTri(base + 2, base + 3, base)
        }

        let topCenter = UInt16(vertices.count)
        addVertex(position: SIMD3<Float>(0, halfHeight, 0), normal: SIMD3<Float>(0, 1, 0))
        var topRing: [UInt16] = []
        for index in 0..<clampedSegments {
            let theta = (Float(index) / Float(clampedSegments)) * (.pi * 2)
            let v = SIMD3<Float>(cos(theta) * radius, halfHeight, sin(theta) * radius)
            topRing.append(UInt16(vertices.count))
            addVertex(position: v, normal: SIMD3<Float>(0, 1, 0))
        }
        for index in 0..<clampedSegments {
            let a = topCenter
            let b = topRing[index]
            let c = topRing[(index + 1) % clampedSegments]
            addTri(a, b, c)
        }

        let bottomCenter = UInt16(vertices.count)
        addVertex(position: SIMD3<Float>(0, -halfHeight, 0), normal: SIMD3<Float>(0, -1, 0))
        var bottomRing: [UInt16] = []
        for index in 0..<clampedSegments {
            let theta = (Float(index) / Float(clampedSegments)) * (.pi * 2)
            let v = SIMD3<Float>(cos(theta) * radius, -halfHeight, sin(theta) * radius)
            bottomRing.append(UInt16(vertices.count))
            addVertex(position: v, normal: SIMD3<Float>(0, -1, 0))
        }
        for index in 0..<clampedSegments {
            let a = bottomCenter
            let b = bottomRing[(index + 1) % clampedSegments]
            let c = bottomRing[index]
            addTri(a, b, c)
        }

        return WhiteboxPrimitiveMesh(vertices: vertices, indices: indices)
    }

    public static func wedge(width: Float, height: Float, depth: Float) -> WhiteboxPrimitiveMesh {
        let hx = width * 0.5
        let hz = depth * 0.5

        let a = SIMD3<Float>(-hx, 0, -hz)
        let b = SIMD3<Float>(hx, 0, -hz)
        let c = SIMD3<Float>(hx, 0, hz)
        let d = SIMD3<Float>(-hx, 0, hz)
        let e = SIMD3<Float>(-hx, height, -hz)
        let f = SIMD3<Float>(-hx, height, hz)

        var vertices: [PackedWhiteboxVertex] = []
        var indices: [UInt16] = []

        func addFace(_ points: [SIMD3<Float>]) {
            guard points.count >= 3 else { return }
            let faceNormal = simd_normalize(simd_cross(points[1] - points[0], points[2] - points[0]))
            let base = UInt16(vertices.count)
            for point in points {
                vertices.append(PackedWhiteboxVertex(position: point, normal: faceNormal))
            }
            for i in 1..<(points.count - 1) {
                indices.append(contentsOf: [base, base + UInt16(i), base + UInt16(i + 1)])
            }
        }

        addFace([a, d, c, b]) // bottom
        addFace([a, e, f, d]) // left
        addFace([d, f, c])    // front
        addFace([a, b, e])    // back
        addFace([e, b, c, f]) // slope

        return WhiteboxPrimitiveMesh(vertices: vertices, indices: indices)
    }
}
