import CoreGraphics
import XCTest
@testable import GameUI

final class OverlayWindowingTests: XCTestCase {
    func testDefaultLayoutCreatesAllWindowStates() {
        let layout = GameplayOverlayLayoutState.defaultLayout(
            viewportSize: CGSize(width: 1366, height: 768)
        )

        for windowID in GameplayOverlayWindowID.allCases {
            XCTAssertNotNil(layout.windowState(for: windowID), "Missing default state for \(windowID)")
        }
    }

    func testFocusRaisesWindowToFront() {
        var layout = GameplayOverlayLayoutState.defaultLayout(
            viewportSize: CGSize(width: 1366, height: 768)
        )

        let before = layout.zIndex(for: .buildMenu)
        layout.focus(windowID: .buildMenu)
        let after = layout.zIndex(for: .buildMenu)
        let maximum = GameplayOverlayWindowID.allCases.map { layout.zIndex(for: $0) }.max() ?? 0

        XCTAssertGreaterThan(after, before)
        XCTAssertEqual(after, maximum)
    }

    func testSetDragPositionMovesWindowOrigin() {
        var layout = GameplayOverlayLayoutState.defaultLayout(
            viewportSize: CGSize(width: 1800, height: 1200)
        )
        guard let initial = layout.windowState(for: .topControls)?.origin else {
            return XCTFail("Expected top controls state")
        }

        let moved = CGPoint(x: initial.x + 140, y: initial.y + 90)
        layout.setDragPosition(
            windowID: .topControls,
            origin: moved,
            viewportSize: CGSize(width: 1800, height: 1200)
        )

        guard let updated = layout.windowState(for: .topControls)?.origin else {
            return XCTFail("Expected updated top controls state")
        }
        XCTAssertEqual(updated.x, moved.x, accuracy: 0.001)
        XCTAssertEqual(updated.y, moved.y, accuracy: 0.001)
    }

    func testClampingKeepsWindowInsideViewport() {
        let viewport = CGSize(width: 640, height: 480)
        var layout = GameplayOverlayLayoutState.defaultLayout(viewportSize: viewport)

        layout.setDragPosition(
            windowID: .buildMenu,
            origin: CGPoint(x: 10_000, y: 10_000),
            viewportSize: viewport
        )

        guard let state = layout.windowState(for: .buildMenu) else {
            return XCTFail("Expected build menu state")
        }

        let margin: CGFloat = 12
        XCTAssertGreaterThanOrEqual(state.origin.x, margin)
        XCTAssertGreaterThanOrEqual(state.origin.y, margin)
        XCTAssertLessThanOrEqual(state.origin.x + state.size.width, viewport.width - margin + 0.001)
        XCTAssertLessThanOrEqual(state.origin.y + state.size.height, viewport.height - margin + 0.001)
    }

    func testClampOnViewportResizeKeepsAllWindowsVisible() {
        var layout = GameplayOverlayLayoutState.defaultLayout(
            viewportSize: CGSize(width: 1600, height: 1000)
        )

        let resized = CGSize(width: 700, height: 500)
        layout.clampToViewport(resized)

        for windowID in GameplayOverlayWindowID.allCases {
            guard let state = layout.windowState(for: windowID) else {
                return XCTFail("Missing state after resize for \(windowID)")
            }
            let margin: CGFloat = 12
            XCTAssertGreaterThanOrEqual(state.origin.x, margin)
            XCTAssertGreaterThanOrEqual(state.origin.y, margin)
            XCTAssertLessThanOrEqual(state.origin.x + state.size.width, resized.width - margin + 0.001)
            XCTAssertLessThanOrEqual(state.origin.y + state.size.height, resized.height - margin + 0.001)
        }
    }

    func testUpdateWindowSizeAppliesRequestedDimensions() {
        let viewport = CGSize(width: 1800, height: 1200)
        var layout = GameplayOverlayLayoutState.defaultLayout(viewportSize: viewport)

        layout.updateWindowSize(
            id: .resources,
            size: CGSize(width: 700, height: 300),
            viewportSize: viewport
        )

        guard let state = layout.windowState(for: .resources) else {
            return XCTFail("Expected resources state")
        }
        XCTAssertEqual(state.size.width, 700, accuracy: 0.001)
        XCTAssertEqual(state.size.height, 300, accuracy: 0.001)
    }

    func testUpdateWindowSizeClampsToMinAndViewport() {
        let viewport = CGSize(width: 500, height: 360)
        var layout = GameplayOverlayLayoutState.defaultLayout(viewportSize: viewport)

        layout.updateWindowSize(
            id: .buildMenu,
            size: CGSize(width: 10_000, height: 10_000),
            viewportSize: viewport
        )
        layout.updateWindowSize(
            id: .buildMenu,
            size: .zero,
            viewportSize: viewport
        )

        guard let state = layout.windowState(for: .buildMenu) else {
            return XCTFail("Expected build menu state")
        }

        XCTAssertGreaterThanOrEqual(state.size.width, 120)
        XCTAssertGreaterThanOrEqual(state.size.height, 64)
        let margin: CGFloat = 12
        XCTAssertLessThanOrEqual(state.origin.x + state.size.width, viewport.width - margin + 0.001)
        XCTAssertLessThanOrEqual(state.origin.y + state.size.height, viewport.height - margin + 0.001)
    }

    func testSessionOnlyLayoutStateDoesNotPersistAcrossNewInstances() {
        let baseline = GameplayOverlayLayoutState.defaultLayout(
            viewportSize: CGSize(width: 1366, height: 768)
        )
        var moved = baseline
        moved.setDragPosition(
            windowID: .resources,
            origin: CGPoint(x: 200, y: 240),
            viewportSize: CGSize(width: 1366, height: 768)
        )
        let fresh = GameplayOverlayLayoutState.defaultLayout(
            viewportSize: CGSize(width: 1366, height: 768)
        )

        guard
            let movedOrigin = moved.windowState(for: .resources)?.origin,
            let baselineOrigin = baseline.windowState(for: .resources)?.origin,
            let freshOrigin = fresh.windowState(for: .resources)?.origin
        else {
            return XCTFail("Expected resource window states")
        }

        XCTAssertNotEqual(movedOrigin, baselineOrigin)
        XCTAssertEqual(freshOrigin, baselineOrigin)
    }
}
