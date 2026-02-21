#if canImport(SwiftUI)
import SwiftUI
import GameSimulation

// MARK: - Tutorial Overlay

public struct TutorialOverlay: View {
    @ObservedObject public var controller: TutorialStateController
    public var spotlightRect: CGRect?
    public var viewportSize: CGSize
    @State private var tooltipSize: CGSize = TutorialTooltipPositionResolver.defaultTooltipSize

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
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .preference(key: TutorialTooltipSizePreferenceKey.self, value: geometry.size)
                    }
                }
                .position(tooltipPosition(for: step))
            }
            .onPreferenceChange(TutorialTooltipSizePreferenceKey.self) { newSize in
                if newSize.width > 0, newSize.height > 0 {
                    tooltipSize = newSize
                }
            }
        }
    }

    private func tooltipPosition(for step: TutorialStepDefinition) -> CGPoint {
        TutorialTooltipPositionResolver().resolve(
            spotlightRect: spotlightRect,
            viewportSize: viewportSize,
            preferredDirection: step.arrowDirection,
            tooltipSize: tooltipSize
        )
    }
}

struct TutorialTooltipPositionResolver {
    static let defaultTooltipSize = CGSize(width: 340, height: 220)

    let padding: CGFloat = 20
    let spacing: CGFloat = 16
    let spotlightAvoidancePadding: CGFloat = 12

    func resolve(
        spotlightRect: CGRect?,
        viewportSize: CGSize,
        preferredDirection: TutorialArrowDirection,
        tooltipSize: CGSize = defaultTooltipSize
    ) -> CGPoint {
        guard let spotlightRect else {
            return CGPoint(x: viewportSize.width * 0.5, y: viewportSize.height * 0.5)
        }

        let halfWidth = tooltipSize.width * 0.5
        let halfHeight = tooltipSize.height * 0.5
        let orderedDirections = directionPriority(preferredDirection)
        let protectedSpotlight = spotlightRect.insetBy(dx: -spotlightAvoidancePadding, dy: -spotlightAvoidancePadding)

        let directionalCandidates = orderedDirections.map { direction in
            bestCandidateNearPreferred(
                preferredCenter: preferredCenter(
                    for: direction,
                    spotlightRect: spotlightRect,
                    halfWidth: halfWidth,
                    halfHeight: halfHeight
                ),
                protectedSpotlight: protectedSpotlight,
                spotlightRect: spotlightRect,
                viewportSize: viewportSize,
                halfWidth: halfWidth,
                halfHeight: halfHeight
            )
        }
        let cornerCandidates = viewportCornerCandidates(
            protectedSpotlight: protectedSpotlight,
            spotlightRect: spotlightRect,
            viewportSize: viewportSize,
            halfWidth: halfWidth,
            halfHeight: halfHeight
        )
        let candidates = directionalCandidates + cornerCandidates

        if let firstNonOverlapping = candidates.first(where: { $0.overlapArea == 0 }) {
            return firstNonOverlapping.center
        }

        guard let fallback = candidates.min(by: { lhs, rhs in
            if lhs.overlapArea != rhs.overlapArea {
                return lhs.overlapArea < rhs.overlapArea
            }
            return lhs.distanceToSpotlightCenter > rhs.distanceToSpotlightCenter
        }) else {
            return CGPoint(x: viewportSize.width * 0.5, y: viewportSize.height * 0.5)
        }
        return fallback.center
    }

    private func directionPriority(_ preferredDirection: TutorialArrowDirection) -> [TutorialArrowDirection] {
        let directions: [TutorialArrowDirection] = [.up, .down, .left, .right]
        return [preferredDirection] + directions.filter { $0 != preferredDirection }
    }

    private func candidate(
        center: CGPoint,
        protectedSpotlight: CGRect,
        spotlightRect: CGRect,
        viewportSize: CGSize,
        halfWidth: CGFloat,
        halfHeight: CGFloat
    ) -> TooltipCandidate {
        let center = clampCenter(center, viewportSize: viewportSize, halfWidth: halfWidth, halfHeight: halfHeight)
        let tooltipRect = CGRect(
            x: center.x - halfWidth,
            y: center.y - halfHeight,
            width: halfWidth * 2,
            height: halfHeight * 2
        )
        return candidateMetrics(
            for: tooltipRect,
            center: center,
            spotlightRect: spotlightRect,
            protectedSpotlight: protectedSpotlight
        )
    }

    private func clampCenter(
        _ center: CGPoint,
        viewportSize: CGSize,
        halfWidth: CGFloat,
        halfHeight: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: min(max(center.x, halfWidth + padding), viewportSize.width - halfWidth - padding),
            y: min(max(center.y, halfHeight + padding), viewportSize.height - halfHeight - padding)
        )
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return intersection.width * intersection.height
    }

    private func viewportCornerCandidates(
        protectedSpotlight: CGRect,
        spotlightRect: CGRect,
        viewportSize: CGSize,
        halfWidth: CGFloat,
        halfHeight: CGFloat
    ) -> [TooltipCandidate] {
        let corners: [CGPoint] = [
            CGPoint(x: halfWidth + padding, y: halfHeight + padding),
            CGPoint(x: viewportSize.width - halfWidth - padding, y: halfHeight + padding),
            CGPoint(x: halfWidth + padding, y: viewportSize.height - halfHeight - padding),
            CGPoint(x: viewportSize.width - halfWidth - padding, y: viewportSize.height - halfHeight - padding)
        ]

        return corners.map { unclampedCenter in
            let center = clampCenter(unclampedCenter, viewportSize: viewportSize, halfWidth: halfWidth, halfHeight: halfHeight)
            let tooltipRect = CGRect(
                x: center.x - halfWidth,
                y: center.y - halfHeight,
                width: halfWidth * 2,
                height: halfHeight * 2
            )
            return candidateMetrics(
                for: tooltipRect,
                center: center,
                spotlightRect: spotlightRect,
                protectedSpotlight: protectedSpotlight
            )
        }
    }

    private func candidateMetrics(
        for tooltipRect: CGRect,
        center: CGPoint,
        spotlightRect: CGRect,
        protectedSpotlight: CGRect
    ) -> TooltipCandidate {
        let overlapArea = intersectionArea(tooltipRect, protectedSpotlight)
        let spotlightCenter = CGPoint(x: spotlightRect.midX, y: spotlightRect.midY)
        let distanceToSpotlightCenter = hypot(center.x - spotlightCenter.x, center.y - spotlightCenter.y)

        return TooltipCandidate(
            center: center,
            overlapArea: overlapArea,
            distanceToSpotlightCenter: distanceToSpotlightCenter
        )
    }

    private func preferredCenter(
        for direction: TutorialArrowDirection,
        spotlightRect: CGRect,
        halfWidth: CGFloat,
        halfHeight: CGFloat
    ) -> CGPoint {
        switch direction {
        case .down:
            return CGPoint(
                x: spotlightRect.midX,
                y: spotlightRect.minY - spacing - halfHeight
            )
        case .up:
            return CGPoint(
                x: spotlightRect.midX,
                y: spotlightRect.maxY + spacing + halfHeight
            )
        case .right:
            return CGPoint(
                x: spotlightRect.minX - spacing - halfWidth,
                y: spotlightRect.midY
            )
        case .left:
            return CGPoint(
                x: spotlightRect.maxX + spacing + halfWidth,
                y: spotlightRect.midY
            )
        }
    }

    private func bestCandidateNearPreferred(
        preferredCenter: CGPoint,
        protectedSpotlight: CGRect,
        spotlightRect: CGRect,
        viewportSize: CGSize,
        halfWidth: CGFloat,
        halfHeight: CGFloat
    ) -> TooltipCandidate {
        let bounds = CGRect(
            x: halfWidth + padding,
            y: halfHeight + padding,
            width: max(0, viewportSize.width - ((halfWidth + padding) * 2)),
            height: max(0, viewportSize.height - ((halfHeight + padding) * 2))
        )
        let clampedPreferred = clampPoint(preferredCenter, to: bounds)
        let preferredCandidate = candidate(
            center: clampedPreferred,
            protectedSpotlight: protectedSpotlight,
            spotlightRect: spotlightRect,
            viewportSize: viewportSize,
            halfWidth: halfWidth,
            halfHeight: halfHeight
        )
        if preferredCandidate.overlapArea == 0 {
            return preferredCandidate
        }

        guard
            let shifted = nearestCenterOutsideForbidden(
                preferredCenter: clampedPreferred,
                centerBounds: bounds,
                protectedSpotlight: protectedSpotlight,
                halfWidth: halfWidth,
                halfHeight: halfHeight
            )
        else {
            return preferredCandidate
        }

        return candidate(
            center: shifted,
            protectedSpotlight: protectedSpotlight,
            spotlightRect: spotlightRect,
            viewportSize: viewportSize,
            halfWidth: halfWidth,
            halfHeight: halfHeight
        )
    }

    private func nearestCenterOutsideForbidden(
        preferredCenter: CGPoint,
        centerBounds: CGRect,
        protectedSpotlight: CGRect,
        halfWidth: CGFloat,
        halfHeight: CGFloat
    ) -> CGPoint? {
        guard centerBounds.width > 0, centerBounds.height > 0 else { return nil }

        let forbidden = CGRect(
            x: protectedSpotlight.minX - halfWidth,
            y: protectedSpotlight.minY - halfHeight,
            width: protectedSpotlight.width + (halfWidth * 2),
            height: protectedSpotlight.height + (halfHeight * 2)
        )

        let overlap = centerBounds.intersection(forbidden)
        if overlap.isNull || overlap.isEmpty {
            return clampPoint(preferredCenter, to: centerBounds)
        }

        let regions: [CGRect] = [
            CGRect(
                x: centerBounds.minX,
                y: centerBounds.minY,
                width: centerBounds.width,
                height: max(0, overlap.minY - centerBounds.minY)
            ),
            CGRect(
                x: centerBounds.minX,
                y: overlap.maxY,
                width: centerBounds.width,
                height: max(0, centerBounds.maxY - overlap.maxY)
            ),
            CGRect(
                x: centerBounds.minX,
                y: overlap.minY,
                width: max(0, overlap.minX - centerBounds.minX),
                height: overlap.height
            ),
            CGRect(
                x: overlap.maxX,
                y: overlap.minY,
                width: max(0, centerBounds.maxX - overlap.maxX),
                height: overlap.height
            )
        ]

        var bestPoint: CGPoint?
        var bestDistanceSquared: CGFloat = .greatestFiniteMagnitude

        for region in regions where region.width > 0 && region.height > 0 {
            let candidate = clampPoint(preferredCenter, to: region)
            let dx = candidate.x - preferredCenter.x
            let dy = candidate.y - preferredCenter.y
            let distanceSquared = (dx * dx) + (dy * dy)
            if distanceSquared < bestDistanceSquared {
                bestDistanceSquared = distanceSquared
                bestPoint = candidate
            }
        }

        return bestPoint
    }

    private func clampPoint(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }
}

private struct TooltipCandidate {
    let center: CGPoint
    let overlapArea: CGFloat
    let distanceToSpotlightCenter: CGFloat
}

private struct TutorialTooltipSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize { .zero }

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}
#endif
