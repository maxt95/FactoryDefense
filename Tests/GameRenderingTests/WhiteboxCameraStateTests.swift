import CoreGraphics
import XCTest
@testable import GameRendering
@testable import GameSimulation

final class WhiteboxCameraStateTests: XCTestCase {
    func testClampToSafePerimeterEnforcesDynamicMinimumZoom() {
        let board = makeBoard()
        let viewport = CGSize(width: 1920, height: 1080)
        var camera = WhiteboxCameraState(zoom: WhiteboxCameraState.minimumZoom)

        camera.clampToSafePerimeter(viewport: viewport, board: board)

        let minimum = camera.minimumZoomToHideBoardEdge(viewport: viewport, board: board)
        XCTAssertEqual(camera.zoom, minimum, accuracy: 0.0001)
    }

    func testClampToSafePerimeterKeepsEdgesOutsideViewport() {
        let board = makeBoard()
        let viewport = CGSize(width: 1280, height: 720)
        var camera = WhiteboxCameraState(pan: SIMD2<Float>(2_000, -2_000), zoom: 1.0)

        camera.clampToSafePerimeter(viewport: viewport, board: board)

        let safeTiles: Float = WhiteboxCameraState.defaultSafePerimeterTiles
        let tileWidth = 34.0 * camera.zoom
        let tileHeight = 22.0 * camera.zoom
        let boardPixelWidth = Float(board.width) * tileWidth
        let boardPixelHeight = Float(board.height) * tileHeight
        let safeX = safeTiles * tileWidth
        let safeY = safeTiles * tileHeight
        let originX = ((Float(viewport.width) - boardPixelWidth) * 0.5) + camera.pan.x
        let originY = ((Float(viewport.height) - boardPixelHeight) * 0.5) + camera.pan.y

        XCTAssertLessThanOrEqual(originX, -safeX + 0.01)
        XCTAssertGreaterThanOrEqual(originX + boardPixelWidth, Float(viewport.width) + safeX - 0.01)
        XCTAssertLessThanOrEqual(originY, -safeY + 0.01)
        XCTAssertGreaterThanOrEqual(originY + boardPixelHeight, Float(viewport.height) + safeY - 0.01)
    }

    func testBoardGrowthCompensationKeepsWorldPointStable() {
        let beforeBoard = makeBoard()
        var afterBoard = beforeBoard
        let insets = BoardExpansionInsets(left: 16, right: 0, top: 16, bottom: 0)
        afterBoard.applyExpansion(insets)

        let viewport = CGSize(width: 1440, height: 900)
        let cellBefore = beforeBoard.basePosition
        let cellAfter = cellBefore.translated(byX: insets.left, byY: insets.top)
        var camera = WhiteboxCameraState(pan: SIMD2<Float>(120, -45), zoom: 1.25)
        let picker = WhiteboxPicker()

        let beforePoint = picker.screenPosition(
            for: cellBefore,
            viewport: viewport,
            camera: camera,
            board: beforeBoard
        )

        camera.compensateForBoardGrowth(
            deltaWidth: afterBoard.width - beforeBoard.width,
            deltaHeight: afterBoard.height - beforeBoard.height,
            deltaBaseX: afterBoard.basePosition.x - beforeBoard.basePosition.x,
            deltaBaseY: afterBoard.basePosition.y - beforeBoard.basePosition.y
        )

        let afterPoint = picker.screenPosition(
            for: cellAfter,
            viewport: viewport,
            camera: camera,
            board: afterBoard
        )

        XCTAssertEqual(beforePoint.x, afterPoint.x, accuracy: 0.01)
        XCTAssertEqual(beforePoint.y, afterPoint.y, accuracy: 0.01)
    }

    func testZoomAroundAnchorKeepsGridCellScreenPositionStable() {
        let board = makeBoard()
        let viewport = CGSize(width: 1440, height: 900)
        var camera = WhiteboxCameraState(pan: SIMD2<Float>(140, -60), zoom: 1.0)
        let picker = WhiteboxPicker()
        let anchorCell = GridPosition(x: 42, y: 31)
        let anchorPoint = picker.screenPosition(
            for: anchorCell,
            viewport: viewport,
            camera: camera,
            board: board
        )

        camera.zoomBy(scale: 1.35, around: anchorPoint, viewport: viewport, board: board)

        let anchoredAfter = picker.screenPosition(
            for: anchorCell,
            viewport: viewport,
            camera: camera,
            board: board
        )
        XCTAssertEqual(anchoredAfter.x, anchorPoint.x, accuracy: 0.01)
        XCTAssertEqual(anchoredAfter.y, anchorPoint.y, accuracy: 0.01)
    }

    private func makeBoard() -> BoardState {
        BoardState(
            width: 96,
            height: 64,
            basePosition: GridPosition(x: 40, y: 32),
            spawnEdgeX: 56,
            spawnYMin: 27,
            spawnYMax: 36,
            blockedCells: [],
            restrictedCells: [GridPosition(x: 40, y: 32)],
            ramps: []
        )
    }
}
