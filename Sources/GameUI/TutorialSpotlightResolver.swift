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
            let boundedWidth = max(1, width)
            let boundedHeight = max(1, height)
            let xRange = origin.x..<(origin.x + boundedWidth)
            let yRange = origin.y..<(origin.y + boundedHeight)

            var minCenterX: CGFloat = .greatestFiniteMagnitude
            var maxCenterX: CGFloat = -.greatestFiniteMagnitude
            var minCenterY: CGFloat = .greatestFiniteMagnitude
            var maxCenterY: CGFloat = -.greatestFiniteMagnitude

            for y in yRange {
                for x in xRange {
                    let center = gridToScreen(GridPosition(x: x, y: y))
                    minCenterX = min(minCenterX, center.x)
                    maxCenterX = max(maxCenterX, center.x)
                    minCenterY = min(minCenterY, center.y)
                    maxCenterY = max(maxCenterY, center.y)
                }
            }

            guard minCenterX.isFinite, maxCenterX.isFinite, minCenterY.isFinite, maxCenterY.isFinite else {
                return nil
            }

            let halfTile = CGSize(width: tileSize.width * 0.5, height: tileSize.height * 0.5)
            return CGRect(
                x: minCenterX - halfTile.width,
                y: minCenterY - halfTile.height,
                width: (maxCenterX - minCenterX) + tileSize.width,
                height: (maxCenterY - minCenterY) + tileSize.height
            ).insetBy(dx: -8, dy: -8)

        case .uiElement(let anchorKey):
            return uiAnchors[anchorKey]?.insetBy(dx: -6, dy: -6)

        case .none:
            return nil
        }
    }
}
#endif
