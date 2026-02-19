#if canImport(SwiftUI)
import SwiftUI

public struct ModeIndicatorView: View {
    public var mode: GameplayInteractionMode
    public var structureName: String?

    public init(mode: GameplayInteractionMode, structureName: String? = nil) {
        self.mode = mode
        self.structureName = structureName
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: modeIcon)
                .font(.system(size: 12))
            Text(modeLabel)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(modeColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(HUDColor.background.opacity(0.85))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(HUDColor.border, lineWidth: 1)
        }
    }

    private var modeIcon: String {
        switch mode {
        case .interact: return "hand.tap"
        case .build: return "hammer.fill"
        case .editBelts: return "arrow.triangle.swap"
        case .planBelt: return "pencil.and.ruler"
        }
    }

    private var modeLabel: String {
        switch mode {
        case .interact: return "Interact"
        case .build:
            if let name = structureName {
                return "Build: \(name)"
            }
            return "Build"
        case .editBelts: return "Edit Belts"
        case .planBelt: return "Plan Belt"
        }
    }

    private var modeColor: Color {
        switch mode {
        case .interact: return HUDColor.primaryText
        case .build: return HUDColor.accentBlue
        case .editBelts: return Color(red: 0.60, green: 0.40, blue: 0.80)
        case .planBelt: return HUDColor.accentTeal
        }
    }
}
#endif
