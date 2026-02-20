#if canImport(SwiftUI)
import CoreGraphics
import GameRendering
import GameSimulation

// MARK: - Spotlight Resolver

public struct TutorialSpotlightResolver {
    private let picker = WhiteboxPicker()

    public init() {}

    public func resolve(
        target: TutorialSpotlightTarget,
        viewport: CGSize,
        camera: WhiteboxCameraState,
        board: BoardState,
        uiAnchors: [String: CGRect]
    ) -> CGRect? {
        switch target {
        case .gridPosition(let position):
            let center = picker.screenPosition(for: position, viewport: viewport, camera: camera, board: board)
            let tileSize = tileSizeAtZoom(camera.zoom)
            return CGRect(
                x: center.x - tileSize.width * 0.5,
                y: center.y - tileSize.height * 0.5,
                width: tileSize.width,
                height: tileSize.height
            ).insetBy(dx: -4, dy: -4)

        case .gridRegion(let origin, let width, let height):
            let topLeft = picker.screenPosition(for: origin, viewport: viewport, camera: camera, board: board)
            let bottomRight = picker.screenPosition(
                for: GridPosition(x: origin.x + width, y: origin.y + height),
                viewport: viewport,
                camera: camera,
                board: board
            )
            let tileSize = tileSizeAtZoom(camera.zoom)
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

    private func tileSizeAtZoom(_ zoom: Float) -> CGSize {
        let z = max(0.001, CGFloat(zoom))
        return CGSize(width: 34 * z, height: 22 * z)
    }
}
#endif
