import CoreGraphics
import XCTest
@testable import GameUI
import GameSimulation

final class TutorialSpotlightResolverTests: XCTestCase {
    func testGridPositionUsesTileSizeAndPadding() {
        let resolver = TutorialSpotlightResolver()
        let tileSize = CGSize(width: 34, height: 22)
        let rect = resolver.resolve(
            target: .gridPosition(GridPosition(x: 3, y: 4)),
            gridToScreen: { _ in CGPoint(x: 100, y: 200) },
            tileSize: tileSize,
            uiAnchors: [:]
        )

        guard let rect else { return XCTFail("Expected spotlight rect") }
        XCTAssertEqual(rect.width, tileSize.width + 8, accuracy: 0.001)
        XCTAssertEqual(rect.height, tileSize.height + 8, accuracy: 0.001)
        XCTAssertEqual(rect.midX, 100, accuracy: 0.001)
        XCTAssertEqual(rect.midY, 200, accuracy: 0.001)
    }

    func testGridRegionMatchesExactCellBounds() {
        let resolver = TutorialSpotlightResolver()
        let tileSize = CGSize(width: 10, height: 10)
        let rect = resolver.resolve(
            target: .gridRegion(origin: GridPosition(x: 2, y: 3), width: 3, height: 2),
            gridToScreen: { pos in
                CGPoint(x: CGFloat(pos.x * 10 + 5), y: CGFloat(pos.y * 10 + 5))
            },
            tileSize: tileSize,
            uiAnchors: [:]
        )

        guard let rect else { return XCTFail("Expected spotlight rect") }
        XCTAssertEqual(rect.origin.x, 12, accuracy: 0.001)
        XCTAssertEqual(rect.origin.y, 22, accuracy: 0.001)
        XCTAssertEqual(rect.width, 46, accuracy: 0.001)
        XCTAssertEqual(rect.height, 36, accuracy: 0.001)
    }

    func testUIElementUsesAnchorFrameWithPadding() {
        let resolver = TutorialSpotlightResolver()
        let anchor = CGRect(x: 40, y: 60, width: 100, height: 80)
        let rect = resolver.resolve(
            target: .uiElement(anchorKey: "buildMenu"),
            gridToScreen: { _ in .zero },
            tileSize: CGSize(width: 1, height: 1),
            uiAnchors: ["buildMenu": anchor]
        )

        guard let rect else { return XCTFail("Expected spotlight rect") }
        XCTAssertEqual(rect.origin.x, 34, accuracy: 0.001)
        XCTAssertEqual(rect.origin.y, 54, accuracy: 0.001)
        XCTAssertEqual(rect.width, 112, accuracy: 0.001)
        XCTAssertEqual(rect.height, 92, accuracy: 0.001)
    }
}
