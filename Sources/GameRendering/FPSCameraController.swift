import Foundation
import simd

/// First-person camera controller using the existing `simd_float4x4.lookAt()` and `.perspective()`.
public struct FPSCameraController: Sendable {
    public var fovYRadians: Float
    public var nearZ: Float
    public var farZ: Float
    public var mouseSensitivity: Float

    public init(
        fovYRadians: Float = .pi / 3.0,
        nearZ: Float = 0.05,
        farZ: Float = 300,
        mouseSensitivity: Float = 0.002
    ) {
        self.fovYRadians = fovYRadians
        self.nearZ = nearZ
        self.farZ = farZ
        self.mouseSensitivity = mouseSensitivity
    }

    // MARK: - Look Direction

    /// Look direction from yaw/pitch. Uses standard FPS convention:
    /// yaw=0 looks along -Z, yaw=pi/2 looks along +X.
    public func lookDirection(yaw: Float, pitch: Float) -> SIMD3<Float> {
        let clampedPitch = clampPitch(pitch)
        return SIMD3<Float>(
            sin(yaw) * cos(clampedPitch),
            sin(clampedPitch),
            -cos(yaw) * cos(clampedPitch)
        )
    }

    /// Right vector perpendicular to the look direction (horizontal plane).
    public func rightDirection(yaw: Float) -> SIMD3<Float> {
        SIMD3<Float>(cos(yaw), 0, sin(yaw))
    }

    // MARK: - Matrices

    /// Compute the view matrix from eye position and yaw/pitch angles.
    public func viewMatrix(eye: SIMD3<Float>, yaw: Float, pitch: Float) -> simd_float4x4 {
        let direction = lookDirection(yaw: yaw, pitch: pitch)
        let center = eye + direction
        return simd_float4x4.lookAt(eye: eye, center: center, up: SIMD3<Float>(0, 1, 0))
    }

    /// Standard perspective projection matrix.
    public func projectionMatrix(aspect: Float) -> simd_float4x4 {
        simd_float4x4.perspective(fovY: fovYRadians, aspect: max(0.0001, aspect), near: nearZ, far: farZ)
    }

    /// Combined view-projection matrix.
    public func viewProjectionMatrix(eye: SIMD3<Float>, yaw: Float, pitch: Float, aspect: Float) -> simd_float4x4 {
        projectionMatrix(aspect: aspect) * viewMatrix(eye: eye, yaw: yaw, pitch: pitch)
    }

    // MARK: - Grid Raycast (DDA)

    /// DDA grid-stepping raycast from camera eye along look direction.
    /// Returns the first ground-level grid cell hit within `maxDistance` world units.
    /// Checks both direct ground-plane intersection and horizontal grid stepping.
    public func raycastGrid(
        eye: SIMD3<Float>,
        yaw: Float,
        pitch: Float,
        maxDistance: Float = 20
    ) -> (x: Int, y: Int)? {
        let dir = lookDirection(yaw: yaw, pitch: pitch)

        // Method 1: Direct ground-plane intersection (y=0)
        // If looking downward, find where the ray hits the ground plane
        if dir.y < -1e-6 && eye.y > 0 {
            let t = -eye.y / dir.y
            if t > 0 && t < maxDistance {
                let hitX = eye.x + t * dir.x
                let hitZ = eye.z + t * dir.z
                let gx = Int(floor(hitX))
                let gz = Int(floor(hitZ))
                return (x: gx, y: gz)
            }
        }

        // Method 2: DDA grid stepping on XZ plane for horizontal/upward looking
        guard abs(dir.x) > 1e-6 || abs(dir.z) > 1e-6 else { return nil }

        // Project to XZ plane
        let dirXZ = SIMD2<Float>(dir.x, dir.z)
        let dirXZLength = simd_length(dirXZ)
        guard dirXZLength > 1e-6 else { return nil }

        var posX = eye.x
        var posZ = eye.z
        var traveled: Float = 0

        // DDA step direction
        let stepX: Int = dir.x >= 0 ? 1 : -1
        let stepZ: Int = dir.z >= 0 ? 1 : -1

        for _ in 0..<Int(maxDistance * 2) {
            guard traveled < maxDistance else { break }

            // Distance to next cell boundary
            let nextBoundaryX: Float
            if stepX > 0 {
                nextBoundaryX = floor(posX) + 1.0
            } else {
                nextBoundaryX = ceil(posX) - 1.0
            }

            let nextBoundaryZ: Float
            if stepZ > 0 {
                nextBoundaryZ = floor(posZ) + 1.0
            } else {
                nextBoundaryZ = ceil(posZ) - 1.0
            }

            let tToNextX = abs(dir.x) > 1e-6 ? (nextBoundaryX - posX) / dir.x : Float.greatestFiniteMagnitude
            let tToNextZ = abs(dir.z) > 1e-6 ? (nextBoundaryZ - posZ) / dir.z : Float.greatestFiniteMagnitude

            let tStep = min(tToNextX, tToNextZ)
            guard tStep > 1e-6, tStep.isFinite else { break }

            posX += dir.x * tStep + Float(stepX) * 0.001
            posZ += dir.z * tStep + Float(stepZ) * 0.001
            traveled += tStep

            let gridX = Int(floor(posX))
            let gridZ = Int(floor(posZ))

            // Check if this cell is at ground level (for building placement etc.)
            return (x: gridX, y: gridZ)
        }
        return nil
    }

    // MARK: - Helpers

    private func clampPitch(_ pitch: Float) -> Float {
        max(-.pi / 2 * 0.95, min(.pi / 2 * 0.95, pitch))
    }
}
