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
            // 2x2 footprint — solid extraction platform with taller drill
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.42, 0.22, 0.42))
            addMesh(
                &builder,
                MeshPrimitives.cylinder(radius: 0.12, height: 0.40, segments: 10),
                offset: SIMD3<Float>(0, 0.44, 0)
            )

        case .smelter:
            // 3x2 footprint — wide furnace body with taller chimney
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.42, 0.32, 0.42))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.10, 0.35, 0.10), offset: SIMD3<Float>(0.20, 0.64, -0.15))

        case .assembler:
            // 3x3 footprint — large workshop floor with taller work stations
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.44, 0.28, 0.44))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.16, 0.18, 0.16), offset: SIMD3<Float>(-0.18, 0.56, 0))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.16, 0.18, 0.16), offset: SIMD3<Float>(0.18, 0.56, 0))

        case .ammoModule:
            // 2x2 footprint — ammo fabrication box
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.40, 0.28, 0.40))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.10, 0.10, 0.22), offset: SIMD3<Float>(0.30, 0.34, 0))

        case .powerPlant:
            // 4x3 footprint — massive generator block with tall smokestack
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.44, 0.45, 0.44))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.14, 0.30, 0.14), offset: SIMD3<Float>(0, 0.90, 0))

        case .conveyor:
            // 1x1 — narrow belt strip
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.45, 0.04, 0.16))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.06, 0.02, 0.06), offset: SIMD3<Float>(0.30, 0.08, 0))

        case .splitter:
            // 1x1 — compact junction
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.42, 0.06, 0.20))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.10, 0.03, 0.10), offset: SIMD3<Float>(0.22, 0.12, 0))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.08, 0.03, 0.08), offset: SIMD3<Float>(0.08, 0.12, 0.12))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.08, 0.03, 0.08), offset: SIMD3<Float>(0.08, 0.12, -0.12))

        case .merger:
            // 1x1 — compact junction
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.42, 0.06, 0.20))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.10, 0.03, 0.10), offset: SIMD3<Float>(0.25, 0.12, 0))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.08, 0.03, 0.08), offset: SIMD3<Float>(-0.20, 0.12, 0.12))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.08, 0.03, 0.08), offset: SIMD3<Float>(-0.20, 0.12, -0.12))

        case .storage:
            // 3x2 footprint — low warehouse
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.44, 0.24, 0.44))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.18, 0.08, 0.18), offset: SIMD3<Float>(0, 0.48, 0))

        case .hq:
            // 5x5 footprint — massive command block with spire
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.44, 0.48, 0.44))
            addGroundedBox(&builder, halfExtents: SIMD3<Float>(0.18, 0.20, 0.18), offset: SIMD3<Float>(0, 0.96, 0))

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
