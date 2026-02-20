#if canImport(SwiftUI)
import SwiftUI

// MARK: - Tutorial Tooltip Bubble

public struct TutorialTooltipBubble: View {
    public var step: TutorialStepDefinition
    public var stepIndex: Int
    public var totalSteps: Int
    public var onNext: () -> Void
    public var onSkip: () -> Void

    public init(
        step: TutorialStepDefinition,
        stepIndex: Int,
        totalSteps: Int,
        onNext: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.step = step
        self.stepIndex = stepIndex
        self.totalSteps = totalSteps
        self.onNext = onNext
        self.onSkip = onSkip
    }

    @State private var cardScale: CGFloat = 0.94
    @State private var cardOpacity: Double = 0

    private let cardWidth: CGFloat = 340

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: step.iconSystemName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(HUDColor.accentTeal)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(step.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(HUDColor.primaryText)

                    Text("Step \(stepIndex + 1) of \(totalSteps)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HUDColor.secondaryText)
                }

                Spacer()
            }

            // Gradient divider
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
                .frame(height: 1)

            // Body text
            Text(step.body)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(HUDColor.primaryText.opacity(0.88))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            // Footer buttons
            HStack {
                Button(action: onSkip) {
                    Text("Skip Tutorial")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HUDColor.secondaryText)
                }
                .buttonStyle(.plain)

                Spacer()

                if step.completionCondition == .tapToContinue {
                    Button(action: onNext) {
                        HStack(spacing: 6) {
                            Text(step.buttonLabel)
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(HUDColor.primaryText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(HUDColor.accentTeal.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(HUDColor.accentTeal.opacity(0.45), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(HUDColor.accentTeal)
                        Text(actionHintText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(HUDColor.accentTealBright)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(HUDColor.accentTeal.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(20)
        .frame(width: cardWidth, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(HUDColor.background.opacity(0.95))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    HUDColor.accentTeal.opacity(0.25),
                                    HUDColor.border,
                                    HUDColor.accentTeal.opacity(0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: Color.black.opacity(0.5), radius: 30, y: 6)
        }
        .scaleEffect(cardScale)
        .opacity(cardOpacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) {
                cardScale = 1.0
                cardOpacity = 1.0
            }
        }
        .onChange(of: step.id) { _, _ in
            cardScale = 0.94
            cardOpacity = 0
            withAnimation(.easeOut(duration: 0.25)) {
                cardScale = 1.0
                cardOpacity = 1.0
            }
        }
    }

    private var actionHintText: String {
        switch step.completionCondition {
        case .tapToContinue:
            return ""
        case .placeStructure:
            return "Waiting for placement..."
        case .selectBuildEntry:
            return "Select from the menu..."
        case .cameraInteraction:
            return "Pan or zoom the camera..."
        case .worldPredicate:
            return "Waiting..."
        }
    }
}
#endif
