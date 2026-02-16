import Foundation
import simd

public enum WhiteboxColors {
    public static func color(for structureTypeRaw: UInt32) -> SIMD3<Float> {
        switch structureTypeRaw {
        case WhiteboxStructureTypeID.wall.rawValue:
            return SIMD3<Float>(0.60, 0.60, 0.60)
        case WhiteboxStructureTypeID.turretMount.rawValue:
            return SIMD3<Float>(0.20, 0.50, 0.80)
        case WhiteboxStructureTypeID.miner.rawValue:
            return SIMD3<Float>(0.80, 0.60, 0.20)
        case WhiteboxStructureTypeID.smelter.rawValue:
            return SIMD3<Float>(0.90, 0.30, 0.10)
        case WhiteboxStructureTypeID.assembler.rawValue:
            return SIMD3<Float>(0.30, 0.70, 0.30)
        case WhiteboxStructureTypeID.ammoModule.rawValue:
            return SIMD3<Float>(0.80, 0.20, 0.20)
        case WhiteboxStructureTypeID.powerPlant.rawValue:
            return SIMD3<Float>(0.90, 0.90, 0.20)
        case WhiteboxStructureTypeID.conveyor.rawValue:
            return SIMD3<Float>(0.50, 0.50, 0.70)
        case WhiteboxStructureTypeID.storage.rawValue:
            return SIMD3<Float>(0.60, 0.40, 0.20)
        case WhiteboxStructureTypeID.hq.rawValue:
            return SIMD3<Float>(0.20, 0.80, 0.90)
        default:
            return SIMD3<Float>(0.72, 0.74, 0.78)
        }
    }

    public static func color(for meshID: MeshID) -> SIMD3<Float> {
        switch meshID {
        case .wall:
            return SIMD3<Float>(0.60, 0.60, 0.60)
        case .turretMount:
            return SIMD3<Float>(0.20, 0.50, 0.80)
        case .miner:
            return SIMD3<Float>(0.80, 0.60, 0.20)
        case .smelter:
            return SIMD3<Float>(0.90, 0.30, 0.10)
        case .assembler:
            return SIMD3<Float>(0.30, 0.70, 0.30)
        case .ammoModule:
            return SIMD3<Float>(0.80, 0.20, 0.20)
        case .powerPlant:
            return SIMD3<Float>(0.90, 0.90, 0.20)
        case .conveyor:
            return SIMD3<Float>(0.50, 0.50, 0.70)
        case .storage:
            return SIMD3<Float>(0.60, 0.40, 0.20)
        case .hq:
            return SIMD3<Float>(0.20, 0.80, 0.90)

        case .swarmling:
            return SIMD3<Float>(1.00, 0.20, 0.20)
        case .droneScout:
            return SIMD3<Float>(1.00, 0.50, 0.00)
        case .raider:
            return SIMD3<Float>(0.80, 0.00, 0.30)
        case .breacher:
            return SIMD3<Float>(0.60, 0.00, 0.60)
        case .artilleryBug:
            return SIMD3<Float>(0.40, 0.00, 0.00)
        case .overseer:
            return SIMD3<Float>(0.30, 0.00, 0.50)

        case .lightBallisticProjectile:
            return SIMD3<Float>(1.00, 1.00, 0.60)
        case .heavyBallisticProjectile:
            return SIMD3<Float>(1.00, 0.80, 0.30)
        case .plasmaProjectile:
            return SIMD3<Float>(0.30, 0.80, 1.00)

        case .gridTile:
            return SIMD3<Float>(0.25, 0.25, 0.25)
        case .ramp:
            return SIMD3<Float>(0.35, 0.30, 0.25)
        case .baseCore:
            return SIMD3<Float>(0.20, 0.80, 0.90)
        case .resourceNode:
            return SIMD3<Float>(0.70, 0.50, 0.10)
        }
    }
}
