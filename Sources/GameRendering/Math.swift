import Foundation
import simd

public struct IsometricCamera: Sendable {
    public var target: SIMD3<Float>
    public var distance: Float
    public var pitchRadians: Float
    public var yawRadians: Float
    public var fovYRadians: Float
    public var nearZ: Float
    public var farZ: Float

    public init(
        target: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        distance: Float = 28,
        pitchRadians: Float = .pi / 4.2,
        yawRadians: Float = .pi / 4,
        fovYRadians: Float = .pi / 3.2,
        nearZ: Float = 0.1,
        farZ: Float = 500
    ) {
        self.target = target
        self.distance = distance
        self.pitchRadians = pitchRadians
        self.yawRadians = yawRadians
        self.fovYRadians = fovYRadians
        self.nearZ = nearZ
        self.farZ = farZ
    }

    public func eyePosition() -> SIMD3<Float> {
        let x = target.x + distance * cos(pitchRadians) * cos(yawRadians)
        let y = target.y + distance * sin(pitchRadians)
        let z = target.z + distance * cos(pitchRadians) * sin(yawRadians)
        return SIMD3<Float>(x, y, z)
    }

    public func viewMatrix() -> simd_float4x4 {
        simd_float4x4.lookAt(eye: eyePosition(), center: target, up: SIMD3<Float>(0, 1, 0))
    }

    public func projectionMatrix(aspect: Float) -> simd_float4x4 {
        simd_float4x4.perspective(fovY: fovYRadians, aspect: max(0.0001, aspect), near: nearZ, far: farZ)
    }

    public func viewProjection(aspect: Float) -> simd_float4x4 {
        projectionMatrix(aspect: aspect) * viewMatrix()
    }
}

public extension simd_float4x4 {
    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let yScale = 1.0 / tan(fovY * 0.5)
        let xScale = yScale / aspect
        let zRange = far - near
        let zScale = -(far + near) / zRange
        let wz = -(2 * far * near) / zRange

        return simd_float4x4(columns: (
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, wz, 0)
        ))
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(center - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)

        return simd_float4x4(columns: (
            SIMD4<Float>(s.x, u.x, -f.x, 0),
            SIMD4<Float>(s.y, u.y, -f.y, 0),
            SIMD4<Float>(s.z, u.z, -f.z, 0),
            SIMD4<Float>(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
        ))
    }
}
