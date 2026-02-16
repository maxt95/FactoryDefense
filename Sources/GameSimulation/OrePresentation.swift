import Foundation
import simd
import GameContent

public enum OrePatchVisualStage: String, Codable, Hashable, Sendable {
    case full
    case partial
    case low
    case exhausted
}

public enum OrePresentation {
    private static let neutralGray = SIMD3<Float>(0.58, 0.58, 0.58)

    public static func displayName(for oreType: ItemID) -> String {
        switch oreType {
        case "ore_iron":
            return "Iron Ore"
        case "ore_copper":
            return "Copper Ore"
        case "ore_coal":
            return "Coal"
        default:
            return humanizedLabel(oreType)
        }
    }

    public static func color(for oreType: ItemID) -> SIMD3<Float> {
        switch oreType {
        case "ore_iron":
            // #B87333
            return SIMD3<Float>(0.7216, 0.4510, 0.2000)
        case "ore_copper":
            // #2E8B7A
            return SIMD3<Float>(0.1804, 0.5451, 0.4784)
        case "ore_coal":
            // #3A3A3A
            return SIMD3<Float>(0.2275, 0.2275, 0.2275)
        default:
            return neutralGray
        }
    }

    private static func humanizedLabel(_ value: String) -> String {
        value
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

public extension OrePatch {
    var visualStage: OrePatchVisualStage {
        guard remainingOre > 0 else {
            return .exhausted
        }

        let denominator = max(1.0, Double(totalOre))
        let ratio = max(0.0, Double(remainingOre) / denominator)
        if ratio >= 0.75 {
            return .full
        }
        if ratio >= 0.40 {
            return .partial
        }
        return .low
    }
}
