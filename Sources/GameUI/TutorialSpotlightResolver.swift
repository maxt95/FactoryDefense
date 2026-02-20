#if canImport(SwiftUI)
import CoreGraphics
import GameSimulation

// MARK: - Spotlight Resolver

public struct TutorialSpotlightResolver {
    public init() {}

    /// Resolves a spotlight target to a screen-space rect.
    /// - Parameters:
    ///   - gridToScreen: Maps a `GridPosition` to a screen-space center point.
    ///   - tileSize: Current tile size in screen points at the active zoom level.
    public func resolve(
        target: TutorialSpotlightTarget,
        gridToScreen: (GridPosition) -> CGPoint,
        tileSize: CGSize,
        uiAnchors: [String: CGRect]
    ) -> CGRect? {
        switch target {
        case .gridPosition(let position):
            let center = gridToScreen(position)
            return CGRect(
                x: center.x - tileSize.width * 0.5,
                y: center.y - tileSize.height * 0.5,
                width: tileSize.width,
                height: tileSize.height
            ).insetBy(dx: -4, dy: -4)

        case .gridRegion(let origin, let width, let height):
            let topLeft = gridToScreen(origin)
            let bottomRight = gridToScreen(
                GridPosition(x: origin.x + width, y: origin.y + height)
            )
            let halfTile = CGSize(width: tileSize.width * 0.5, height: tileSize.height * 0.5)
            return CGRect(
                x: topLeft.x - halfTile.width,
                y: topLeft.y - halfTile.height,
                width: (bottomRight.x - topLeft.x) + tileSize.width,
                height: (bottomRight.y - topLeft.y) + tileSize.height
            ).insetBy(dx: -8, dy: -8)

        case .uiElement(let anchorKey):
            return uiAnchors[anchorKey]?.insetBy(dx: -6, dy: -6)

        case .none:
            return nil
        }
    }
}
#endif
