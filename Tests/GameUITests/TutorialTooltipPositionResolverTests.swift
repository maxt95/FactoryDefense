import CoreGraphics
import XCTest
@testable import GameUI

final class TutorialTooltipPositionResolverTests: XCTestCase {
    func testReturnsViewportCenterWhenNoSpotlight() {
        let resolver = TutorialTooltipPositionResolver()
        let viewport = CGSize(width: 1280, height: 720)

        let center = resolver.resolve(
            spotlightRect: nil,
            viewportSize: viewport,
            preferredDirection: .down
        )

        XCTAssertEqual(center.x, viewport.width * 0.5, accuracy: 0.001)
        XCTAssertEqual(center.y, viewport.height * 0.5, accuracy: 0.001)
    }

    func testUsesPreferredDirectionWhenSpaceExists() {
        let resolver = TutorialTooltipPositionResolver()
        let viewport = CGSize(width: 1280, height: 720)
        let spotlight = CGRect(x: 560, y: 280, width: 120, height: 120)

        let center = resolver.resolve(
            spotlightRect: spotlight,
            viewportSize: viewport,
            preferredDirection: .left
        )

        XCTAssertGreaterThan(center.x, spotlight.maxX)
        XCTAssertFalse(tooltipRect(center: center).intersects(spotlight))
    }

    func testFallsBackToAlternateDirectionToAvoidSpotlightOverlap() {
        let resolver = TutorialTooltipPositionResolver()
        let viewport = CGSize(width: 400, height: 860)
        let spotlight = CGRect(x: 120, y: 24, width: 160, height: 120)

        let center = resolver.resolve(
            spotlightRect: spotlight,
            viewportSize: viewport,
            preferredDirection: .down
        )

        XCTAssertFalse(tooltipRect(center: center).intersects(spotlight))
    }

    func testUsesActualTooltipSizeForCollisionAvoidance() {
        let resolver = TutorialTooltipPositionResolver()
        let viewport = CGSize(width: 430, height: 932)
        let spotlight = CGRect(x: 24, y: 120, width: 360, height: 320)
        let tooltipSize = CGSize(width: 340, height: 360)

        let center = resolver.resolve(
            spotlightRect: spotlight,
            viewportSize: viewport,
            preferredDirection: .down,
            tooltipSize: tooltipSize
        )

        let rect = CGRect(
            x: center.x - (tooltipSize.width * 0.5),
            y: center.y - (tooltipSize.height * 0.5),
            width: tooltipSize.width,
            height: tooltipSize.height
        )
        XCTAssertFalse(rect.intersects(spotlight))
    }

    func testSlidesAlongAxisToAvoidPartialOverlap() {
        let resolver = TutorialTooltipPositionResolver()
        let viewport = CGSize(width: 420, height: 780)
        let spotlight = CGRect(x: 40, y: 180, width: 300, height: 220)
        let tooltipSize = CGSize(width: 340, height: 260)

        let center = resolver.resolve(
            spotlightRect: spotlight,
            viewportSize: viewport,
            preferredDirection: .right,
            tooltipSize: tooltipSize
        )

        let rect = CGRect(
            x: center.x - (tooltipSize.width * 0.5),
            y: center.y - (tooltipSize.height * 0.5),
            width: tooltipSize.width,
            height: tooltipSize.height
        )
        XCTAssertFalse(rect.intersects(spotlight))
    }

    private func tooltipRect(center: CGPoint) -> CGRect {
        let tooltipSize = TutorialTooltipPositionResolver.defaultTooltipSize
        return CGRect(
            x: center.x - (tooltipSize.width * 0.5),
            y: center.y - (tooltipSize.height * 0.5),
            width: tooltipSize.width,
            height: tooltipSize.height
        )
    }
}
