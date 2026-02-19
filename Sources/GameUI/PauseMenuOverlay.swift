#if canImport(SwiftUI)
import SwiftUI

// MARK: - HUD Pause Button

public struct PauseHUDButton: View {
    public let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    @State private var isHovered = false

    public var body: some View {
        Button(action: action) {
            Image(systemName: "pause.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovered ? HUDColor.primaryText : HUDColor.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isHovered ? HUDColor.surface : HUDColor.background.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isHovered ? HUDColor.accentTeal.opacity(0.4) : HUDColor.border,
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Pause Menu Overlay

public struct PauseMenuOverlay: View {
    public let onResume: () -> Void
    public let onSettings: () -> Void
    public let onQuit: () -> Void

    public init(
        onResume: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onResume = onResume
        self.onSettings = onSettings
        self.onQuit = onQuit
    }

    @State private var cardScale: CGFloat = 0.96
    @State private var cardOpacity: Double = 0

    public var body: some View {
        ZStack {
            Color.black.opacity(0.80)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Title
                VStack(spacing: 6) {
                    Image(systemName: "pause.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(HUDColor.accentTeal)

                    Text("PAUSED")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(HUDColor.primaryText)
                }

                // Divider
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                HUDColor.border.opacity(0),
                                HUDColor.accentTeal.opacity(0.3),
                                HUDColor.border.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 180, height: 1)

                // Buttons
                VStack(spacing: 10) {
                    PauseMenuButton(
                        title: "Resume",
                        icon: "play.fill",
                        style: .primary,
                        action: onResume
                    )
                    PauseMenuButton(
                        title: "Settings",
                        icon: "gearshape.fill",
                        style: .secondary,
                        action: onSettings
                    )
                    PauseMenuButton(
                        title: "Quit to Menu",
                        icon: "rectangle.portrait.and.arrow.right",
                        style: .destructive,
                        action: onQuit
                    )
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 36)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(HUDColor.background.opacity(0.95))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        HUDColor.accentTeal.opacity(0.2),
                                        HUDColor.border,
                                        HUDColor.accentTeal.opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: Color.black.opacity(0.5), radius: 40, y: 8)
            }
            .scaleEffect(cardScale)
            .opacity(cardOpacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) {
                    cardScale = 1.0
                    cardOpacity = 1.0
                }
            }
        }
    }
}

// MARK: - Private Components

private enum PauseButtonStyle {
    case primary, secondary, destructive
}

private struct PauseMenuButton: View {
    let title: String
    let icon: String
    let style: PauseButtonStyle
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(textColor)
            .frame(width: 220, height: 46)
            .background(isHovered ? hoverBackground : background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isHovered ? hoverBorder : borderColor, lineWidth: 1)
            }
            .shadow(
                color: isHovered ? shadowColor : .clear,
                radius: 8, y: 2
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var textColor: Color {
        switch style {
        case .primary: HUDColor.primaryText
        case .secondary: HUDColor.primaryText
        case .destructive: isHovered ? HUDColor.accentRedBright : HUDColor.accentRed
        }
    }

    private var background: Color {
        switch style {
        case .primary: HUDColor.accentTeal.opacity(0.18)
        case .secondary: HUDColor.surface
        case .destructive: HUDColor.accentRed.opacity(0.08)
        }
    }

    private var hoverBackground: Color {
        switch style {
        case .primary: HUDColor.accentTeal.opacity(0.30)
        case .secondary: HUDColor.surface.opacity(0.8)
        case .destructive: HUDColor.accentRed.opacity(0.18)
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary: HUDColor.accentTeal.opacity(0.35)
        case .secondary: HUDColor.border
        case .destructive: HUDColor.accentRed.opacity(0.2)
        }
    }

    private var hoverBorder: Color {
        switch style {
        case .primary: HUDColor.accentTeal.opacity(0.6)
        case .secondary: HUDColor.secondaryText.opacity(0.3)
        case .destructive: HUDColor.accentRed.opacity(0.5)
        }
    }

    private var shadowColor: Color {
        switch style {
        case .primary: HUDColor.accentTeal.opacity(0.2)
        case .secondary: Color.white.opacity(0.03)
        case .destructive: HUDColor.accentRed.opacity(0.15)
        }
    }
}
#endif
