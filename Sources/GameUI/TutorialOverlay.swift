#if canImport(SwiftUI)
import SwiftUI
import GameSimulation

// MARK: - Tutorial Overlay

public struct TutorialOverlay: View {
    @ObservedObject public var controller: TutorialStateController
    public var spotlightRect: CGRect?
    public var viewportSize: CGSize

    public init(
        controller: TutorialStateController,
        spotlightRect: CGRect?,
        viewportSize: CGSize
    ) {
        self.controller = controller
        self.spotlightRect = spotlightRect
        self.viewportSize = viewportSize
    }

    public var body: some View {
        if let step = controller.currentStep {
            ZStack {
                TutorialDimLayer(
                    spotlightRect: spotlightRect,
                    dimOpacity: step.dimOpacity
                )

                TutorialTooltipBubble(
                    step: step,
                    stepIndex: controller.currentStepIndex,
                    totalSteps: controller.totalSteps,
                    onNext: { controller.advanceManually() },
                    onSkip: { controller.skip() }
                )
                .position(tooltipPosition(for: step))
            }
        }
    }

    private func tooltipPosition(for step: TutorialStepDefinition) -> CGPoint {
        let tooltipWidth: CGFloat = 340
        let tooltipEstimatedHeight: CGFloat = 220
        let padding: CGFloat = 20
        let spacing: CGFloat = 16

        guard let spotlight = spotlightRect else {
            return CGPoint(x: viewportSize.width * 0.5, y: viewportSize.height * 0.5)
        }

        let halfW = tooltipWidth * 0.5
        let halfH = tooltipEstimatedHeight * 0.5

        switch step.arrowDirection {
        case .down:
            let x = clampX(spotlight.midX, halfWidth: halfW, padding: padding)
            let y = spotlight.minY - spacing - halfH
            if y - halfH > padding {
                return CGPoint(x: x, y: y)
            }
            let belowY = spotlight.maxY + spacing + halfH
            return CGPoint(x: x, y: min(belowY, viewportSize.height - halfH - padding))

        case .up:
            let x = clampX(spotlight.midX, halfWidth: halfW, padding: padding)
            let y = spotlight.maxY + spacing + halfH
            if y + halfH < viewportSize.height - padding {
                return CGPoint(x: x, y: y)
            }
            let aboveY = spotlight.minY - spacing - halfH
            return CGPoint(x: x, y: max(aboveY, halfH + padding))

        case .right:
            let x = spotlight.minX - spacing - halfW
            let y = clampY(spotlight.midY, halfHeight: halfH, padding: padding)
            if x - halfW > padding {
                return CGPoint(x: x, y: y)
            }
            let rightX = spotlight.maxX + spacing + halfW
            return CGPoint(x: min(rightX, viewportSize.width - halfW - padding), y: y)

        case .left:
            let x = spotlight.maxX + spacing + halfW
            let y = clampY(spotlight.midY, halfHeight: halfH, padding: padding)
            if x + halfW < viewportSize.width - padding {
                return CGPoint(x: x, y: y)
            }
            let leftX = spotlight.minX - spacing - halfW
            return CGPoint(x: max(leftX, halfW + padding), y: y)
        }
    }

    private func clampX(_ x: CGFloat, halfWidth: CGFloat, padding: CGFloat) -> CGFloat {
        min(max(x, halfWidth + padding), viewportSize.width - halfWidth - padding)
    }

    private func clampY(_ y: CGFloat, halfHeight: CGFloat, padding: CGFloat) -> CGFloat {
        min(max(y, halfHeight + padding), viewportSize.height - halfHeight - padding)
    }
}
#endif
