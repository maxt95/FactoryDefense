#if canImport(SwiftUI)
import SwiftUI

public enum HUDColor {
    public static let background = Color(red: 0.05, green: 0.07, blue: 0.09)
    public static let surface = Color(red: 0.086, green: 0.106, blue: 0.133)
    public static let border = Color.white.opacity(0.12)
    public static let primaryText = Color(red: 0.90, green: 0.93, blue: 0.95)
    public static let secondaryText = Color.white.opacity(0.50)

    public static let accentTeal = Color(red: 0.18, green: 0.62, blue: 0.62)
    public static let accentTealBright = Color(red: 0.23, green: 0.72, blue: 0.72)
    public static let accentAmber = Color(red: 0.83, green: 0.63, blue: 0.09)
    public static let accentRed = Color(red: 0.85, green: 0.21, blue: 0.20)
    public static let accentRedBright = Color(red: 1.0, green: 0.42, blue: 0.42)
    public static let accentBlue = Color(red: 0.22, green: 0.55, blue: 0.99)
    public static let accentGreen = Color(red: 0.18, green: 0.63, blue: 0.26)
    public static let powerYellow = Color(red: 0.83, green: 0.77, blue: 0.13)

    public static func resourceDotColor(for itemID: String) -> Color {
        switch itemID {
        case "plate_iron": return Color(red: 0.80, green: 0.60, blue: 0.20)
        case "gear": return Color(red: 0.53, green: 0.53, blue: 0.53)
        case "circuit": return Color(red: 0.27, green: 0.67, blue: 0.40)
        case "ammo_light": return Color(red: 0.80, green: 0.27, blue: 0.27)
        case "ammo_heavy": return Color(red: 0.67, green: 0.20, blue: 0.20)
        case "ammo_plasma": return Color(red: 0.47, green: 0.27, blue: 0.80)
        case "ore_iron": return Color(red: 0.72, green: 0.45, blue: 0.20)
        case "ore_copper": return Color(red: 0.20, green: 0.60, blue: 0.55)
        case "ore_coal": return Color(red: 0.30, green: 0.30, blue: 0.30)
        case "plate_copper": return Color(red: 0.80, green: 0.50, blue: 0.25)
        case "plate_steel": return Color(red: 0.55, green: 0.55, blue: 0.60)
        case "power_cell": return Color(red: 0.83, green: 0.77, blue: 0.13)
        case "wall_kit": return Color(red: 0.60, green: 0.60, blue: 0.60)
        case "turret_core": return Color(red: 0.20, green: 0.50, blue: 0.80)
        default: return Color.gray
        }
    }

    public static func warningColor(for warning: WarningBanner) -> Color {
        switch warning {
        case .none: return .clear
        case .baseCritical: return accentRed
        case .powerShortage, .surgeImminent, .lowAmmo: return accentAmber
        case .patchExhausted: return Color(red: 0.85, green: 0.50, blue: 0.15)
        }
    }

    public static func warningMessage(for warning: WarningBanner) -> String {
        switch warning {
        case .none: return ""
        case .baseCritical: return "HQ HEALTH CRITICAL"
        case .powerShortage: return "POWER SHORTAGE"
        case .lowAmmo: return "LOW AMMO DURING SURGE"
        case .surgeImminent: return "SURGE IMMINENT"
        case .patchExhausted: return "ORE PATCH EXHAUSTED"
        }
    }
}
#endif
