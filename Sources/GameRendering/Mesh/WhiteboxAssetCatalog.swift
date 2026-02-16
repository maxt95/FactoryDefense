import Foundation
import simd

public enum WhiteboxAssetCatalog {
    public static func makeMesh(for id: MeshID) -> WhiteboxPrimitiveMesh? {
        var builder = WhiteboxAssetBuilder()

        switch id {
        case .wall:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.45, 0.50, 0.45))

        case .turretMount:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.45, 0.10, 0.45))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.15, 0.25, 0.15), offset: SIMD3<Float>(0, 0.20, 0))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.25, 0.10, 0.25), offset: SIMD3<Float>(0, 0.50, 0))

        case .miner:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.40, 0.20, 0.40))
            addMesh(
                &builder,
                MeshPrimitives.cylinder(radius: 0.10, height: 0.30, segments: 10),
                offset: SIMD3<Float>(0, 0.40, 0)
            )

        case .smelter:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.40, 0.30, 0.40))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.08, 0.25, 0.08), offset: SIMD3<Float>(0.20, 0.60, -0.15))

        case .assembler:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.45, 0.25, 0.45))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.14, 0.14, 0.14), offset: SIMD3<Float>(-0.18, 0.53, 0))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.14, 0.14, 0.14), offset: SIMD3<Float>(0.18, 0.53, 0))

        case .ammoModule:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.35, 0.30, 0.35))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.10, 0.10, 0.22), offset: SIMD3<Float>(0.30, 0.34, 0))

        case .powerPlant:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.40, 0.40, 0.40))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.16, 0.20, 0.16), offset: SIMD3<Float>(0, 0.80, 0))

        case .conveyor:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.45, 0.05, 0.45))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.10, 0.02, 0.10), offset: SIMD3<Float>(0.24, 0.10, 0))

        case .storage:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.45, 0.20, 0.45))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.18, 0.08, 0.18), offset: SIMD3<Float>(0, 0.45, 0))

        case .hq:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.45, 0.45, 0.45))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.16, 0.16, 0.16), offset: SIMD3<Float>(0, 0.90, 0))

        case .swarmling:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.15, 0.15, 0.15))

        case .droneScout:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.20, 0.08, 0.20), offset: SIMD3<Float>(0, 0.08, 0))

        case .raider:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.20, 0.30, 0.20))

        case .breacher:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.30, 0.25, 0.30))

        case .artilleryBug:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.25, 0.20, 0.25))
            addMesh(
                &builder,
                MeshPrimitives.cylinder(radius: 0.06, height: 0.30, segments: 8),
                offset: SIMD3<Float>(0.22, 0.35, 0)
            )

        case .overseer:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.35, 0.35, 0.35))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.15, 0.15, 0.15), offset: SIMD3<Float>(0, 0.70, 0))

        case .lightBallisticProjectile:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.05, 0.05, 0.05), offset: SIMD3<Float>(0, 0.10, 0))

        case .heavyBallisticProjectile:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.08, 0.08, 0.08), offset: SIMD3<Float>(0, 0.12, 0))

        case .plasmaProjectile:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.06, 0.06, 0.06), offset: SIMD3<Float>(0, 0.10, 0))

        case .gridTile:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.49, 0.02, 0.49))

        case .ramp:
            addMesh(&builder, MeshPrimitives.wedge(width: 1.0, height: 1.0, depth: 1.0), offset: SIMD3<Float>(0, 0, 0))

        case .baseCore:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.45, 0.45, 0.45))

        case .resourceNode:
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.30, 0.15, 0.30))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.16, 0.10, 0.16), offset: SIMD3<Float>(-0.12, 0.24, 0.08))
        }

        return builder.build()
    }

    private static func addGroundedBox(
        _ builder: inout WhiteboxAssetBuilder,
        halfExtents: SIMD3<Float>,
        offset: SIMD3<Float> = .zero
    ) {
        addMesh(
            &builder,
            MeshPrimitives.box(halfExtents: halfExtents),
            offset: offset + SIMD3<Float>(0, halfExtents.y, 0)
        )
    }

    private static func addMesh(
        _ builder: inout WhiteboxAssetBuilder,
        _ mesh: WhiteboxPrimitiveMesh,
        offset: SIMD3<Float>
    ) {
        let transform = simd_float4x4.translation(offset)
        builder.add(mesh: mesh, transform: transform)
    }
}
