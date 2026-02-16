import AppKit
import MetalKit
import SwiftUI
import GameRendering
import GameSimulation
import GameUI
import GamePlatform

struct FactoryDefensemacOSRootView: View {
    @State private var didStartGame = false

    var body: some View {
        if didStartGame {
            FactoryDefensemacOSGameplayView()
        } else {
            FactoryDefenseMainMenu(
                title: "Factory Defense",
                onStart: { didStartGame = true },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        }
    }
}

private struct FactoryDefenseMainMenu: View {
    let title: String
    let onStart: () -> Void
    let onQuit: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.12, blue: 0.18), Color(red: 0.05, green: 0.07, blue: 0.11)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                VStack(spacing: 10) {
                    Button("Start", action: onStart)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                    Button("Quit", action: onQuit)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}

private struct FactoryDefensemacOSGameplayView: View {
    @StateObject private var runtime = GameRuntimeController()
    @State private var buildMenu = BuildMenuViewModel.productionPreset
    @State private var techTree = TechTreeViewModel.productionPreset
    @State private var onboarding = OnboardingGuideViewModel.starter
    @State private var cameraState = WhiteboxCameraState()
    @State private var dragTranslation: CGSize = .zero
    @State private var zoomGestureScale: CGFloat = 1
    @State private var renderDiagnostic: String?
    @State private var selectedEntityID: EntityID?

    private static let keyboardPanStep: Float = 56
    private let picker = WhiteboxPicker()
    private let objectInspectorBuilder = ObjectInspectorBuilder()

    private var selectedStructure: StructureType {
        buildMenu.selectedEntry()?.structure ?? .wall
    }

    private var inventory: [String: Int] {
        runtime.world.economy.inventories
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MetalSurfaceView(
                    world: runtime.world,
                    cameraState: cameraState,
                    highlightedCell: runtime.highlightedCell,
                    highlightedStructure: runtime.highlightedCell == nil ? nil : selectedStructure,
                    placementResult: runtime.placementResult,
                    onTap: { location, viewport in
                        handleTap(at: location, viewport: viewport)
                    },
                    onScrollZoom: { delta, location, viewport in
                        let scale: Float = delta < 0 ? 0.92 : 1.08
                        zoomCamera(scale: scale, around: location, viewport: viewport)
                    },
                    onKeyboardPan: { dx, dy, viewport in
                        handleKeyboardPan(deltaX: dx, deltaY: dy, viewport: viewport)
                    }
                )
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let deltaX = value.translation.width - dragTranslation.width
                            let deltaY = value.translation.height - dragTranslation.height
                            cameraState.panBy(deltaX: -Float(deltaX), deltaY: -Float(deltaY))
                            enforceCameraConstraints(viewport: proxy.size)
                            dragTranslation = value.translation
                            previewPlacement(at: value.location, viewport: proxy.size)
                        }
                        .onEnded { _ in
                            dragTranslation = .zero
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            let delta = scale / zoomGestureScale
                            guard delta.isFinite, delta > 0 else { return }
                            let inverted = Float(1 / delta)
                            let anchor = CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
                            zoomCamera(scale: inverted, around: anchor, viewport: proxy.size)
                            zoomGestureScale = scale
                        }
                        .onEnded { _ in
                            zoomGestureScale = 1
                        }
                )

                if let inspector = selectedInspectorModel() {
                    let inspectorPosition = inspectorPosition(for: inspector, viewport: proxy.size)
                    ObjectInspectorPopup(
                        model: inspector,
                        onClose: { selectedEntityID = nil }
                    )
                    .frame(width: 320)
                    .position(inspectorPosition)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Factory Defense macOS")
                            .font(.headline)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text("Placement: \(placementLabel(runtime.placementResult))")
                            .font(.caption)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Spacer()

                        Button("Wave") {
                            runtime.triggerWave()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Extract") {
                            runtime.extract()
                        }
                        .buttonStyle(.bordered)
                    }

                    ResourceHUDPanel(world: runtime.world)

                    HStack(alignment: .top, spacing: 10) {
                        BuildMenuPanel(viewModel: buildMenu, inventory: inventory) { entry in
                            buildMenu.select(entryID: entry.id)
                        }
                        .frame(width: 320)

                        BuildingReferencePanel(world: runtime.world)
                            .frame(width: 300)

                        VStack(spacing: 10) {
                            TechTreePanel(nodes: techTree.nodes(inventory: inventory))
                            OnboardingPanel(steps: onboarding.steps)
                            TuningDashboardPanel(snapshot: .from(world: runtime.world))
                        }
                        .frame(maxWidth: .infinity)
                    }

                    Spacer()
                }
                .padding(16)

                if let renderDiagnostic {
                    VStack {
                        HStack {
                            Text(renderDiagnostic)
                                .font(.caption)
                                .padding(8)
                                .background(Color.red.opacity(0.78))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(16)
                }
            }
            .onAppear {
                runtime.start()
                if buildMenu.selectedEntryID == nil, let first = buildMenu.entries.first {
                    buildMenu.select(entryID: first.id)
                }
                onboarding.update(from: runtime.world)
                enforceCameraConstraints(viewport: proxy.size)
            }
            .onDisappear {
                runtime.stop()
            }
            .onChange(of: runtime.world.tick) { _, _ in
                onboarding.update(from: runtime.world)
                if let selectedEntityID, runtime.world.entities.entity(id: selectedEntityID) == nil {
                    self.selectedEntityID = nil
                }
            }
            .onChange(of: runtime.world.board) { oldBoard, newBoard in
                reconcileCameraForBoardChange(from: oldBoard, to: newBoard, viewport: proxy.size)
            }
            .onChange(of: buildMenu.selectedEntryID) { _, _ in
                if let highlighted = runtime.highlightedCell {
                    runtime.previewPlacement(structure: selectedStructure, at: highlighted)
                }
            }
            .onChange(of: proxy.size) { _, _ in
                enforceCameraConstraints(viewport: proxy.size)
            }
            .onReceive(NotificationCenter.default.publisher(for: RenderDiagnostics.notificationName)) { note in
                renderDiagnostic = note.userInfo?[RenderDiagnostics.messageKey] as? String
            }
        }
    }

    private func placementLabel(_ result: PlacementResult) -> String {
        switch result {
        case .ok:
            return "Valid"
        case .occupied:
            return "Occupied"
        case .outOfBounds:
            return "Out of bounds"
        case .blocksCriticalPath:
            return "Blocks path"
        case .restrictedZone:
            return "Restricted"
        case .insufficientResources:
            return "Insufficient resources"
        }
    }

    private func handleTap(at location: CGPoint, viewport: CGSize) {
        guard let position = pickGrid(at: location, viewport: viewport) else {
            runtime.clearPlacementPreview()
            selectedEntityID = nil
            return
        }
        if let tappedEntity = runtime.world.entities.selectableEntity(at: position) {
            runtime.clearPlacementPreview()
            selectedEntityID = selectedEntityID == tappedEntity.id ? nil : tappedEntity.id
            return
        }
        selectedEntityID = nil
        runtime.placeStructure(selectedStructure, at: position)
    }

    private func previewPlacement(at location: CGPoint, viewport: CGSize) {
        guard let position = pickGrid(at: location, viewport: viewport) else {
            runtime.clearPlacementPreview()
            return
        }
        runtime.previewPlacement(structure: selectedStructure, at: position)
    }

    private func handleKeyboardPan(deltaX: Float, deltaY: Float, viewport: CGSize) {
        cameraState.panBy(
            deltaX: -deltaX * Self.keyboardPanStep,
            deltaY: -deltaY * Self.keyboardPanStep
        )
        enforceCameraConstraints(viewport: viewport)
    }

    private func zoomCamera(scale: Float, around anchor: CGPoint, viewport: CGSize) {
        cameraState.zoomBy(
            scale: scale,
            around: anchor,
            viewport: viewport,
            board: runtime.world.board
        )
    }

    private func enforceCameraConstraints(viewport: CGSize) {
        cameraState.clampToSafePerimeter(viewport: viewport, board: runtime.world.board)
    }

    private func reconcileCameraForBoardChange(from oldBoard: BoardState, to newBoard: BoardState, viewport: CGSize) {
        guard oldBoard != newBoard else {
            enforceCameraConstraints(viewport: viewport)
            return
        }
        cameraState.compensateForBoardGrowth(
            deltaWidth: newBoard.width - oldBoard.width,
            deltaHeight: newBoard.height - oldBoard.height,
            deltaBaseX: newBoard.basePosition.x - oldBoard.basePosition.x,
            deltaBaseY: newBoard.basePosition.y - oldBoard.basePosition.y
        )
        cameraState.clampToSafePerimeter(viewport: viewport, board: newBoard)
    }

    private func pickGrid(at location: CGPoint, viewport: CGSize) -> GridPosition? {
        return picker.gridPosition(
            at: location,
            viewport: viewport,
            board: runtime.world.board,
            camera: cameraState
        )
    }

    private func selectedInspectorModel() -> ObjectInspectorViewModel? {
        guard let selectedEntityID else { return nil }
        return objectInspectorBuilder.build(entityID: selectedEntityID, in: runtime.world)
    }

    private func inspectorPosition(for model: ObjectInspectorViewModel, viewport: CGSize) -> CGPoint {
        let anchor = picker.screenPosition(
            for: model.anchorPosition,
            viewport: viewport,
            camera: cameraState,
            board: runtime.world.board
        )
        let tileHeight = CGFloat(max(0.001, cameraState.zoom)) * 22
        let lift = tileHeight * (CGFloat(model.anchorHeightTiles) + 1.4)
        let halfWidth: CGFloat = 160
        let xPadding: CGFloat = 12
        let x = min(max(halfWidth + xPadding, anchor.x), viewport.width - (halfWidth + xPadding))
        let y = max(72, anchor.y - lift)
        return CGPoint(x: x, y: y)
    }
}

private struct MetalSurfaceView: NSViewRepresentable {
    var world: WorldState
    var cameraState: WhiteboxCameraState
    var highlightedCell: GridPosition?
    var highlightedStructure: StructureType?
    var placementResult: PlacementResult
    var onTap: (CGPoint, CGSize) -> Void
    var onScrollZoom: (CGFloat, CGPoint, CGSize) -> Void
    var onKeyboardPan: (Float, Float, CGSize) -> Void

    func makeNSView(context: Context) -> MTKView {
        let view = ScrollableMTKView(frame: .zero)
        view.onTap = onTap
        view.onScrollZoom = onScrollZoom
        view.onKeyboardPan = onKeyboardPan
        if let renderer = context.coordinator.renderer {
            renderer.attach(to: view)
        }
        view.window?.makeFirstResponder(view)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        if let interactiveView = nsView as? ScrollableMTKView {
            interactiveView.onTap = onTap
            interactiveView.onScrollZoom = onScrollZoom
            interactiveView.onKeyboardPan = onKeyboardPan
            interactiveView.window?.makeFirstResponder(interactiveView)
        }
        renderer.worldState = world
        renderer.cameraState = cameraState
        renderer.setPlacementHighlight(cell: highlightedCell, structure: highlightedStructure, result: placementResult)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        let renderer = FactoryRenderer()
    }
}

private final class ScrollableMTKView: MTKView {
    var onTap: ((CGPoint, CGSize) -> Void)?
    var onScrollZoom: ((CGFloat, CGPoint, CGSize) -> Void)?
    var onKeyboardPan: ((Float, Float, CGSize) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let local = convert(event.locationInWindow, from: nil)
        let y = isFlipped ? local.y : (bounds.height - local.y)
        onTap?(CGPoint(x: local.x, y: y), bounds.size)
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let y = isFlipped ? local.y : (bounds.height - local.y)
        onScrollZoom?(event.scrollingDeltaY, CGPoint(x: local.x, y: y), bounds.size)
        super.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 0, 123: // A, Left
            onKeyboardPan?(-1, 0, bounds.size)
        case 2, 124: // D, Right
            onKeyboardPan?(1, 0, bounds.size)
        case 13, 126: // W, Up
            onKeyboardPan?(0, -1, bounds.size)
        case 1, 125: // S, Down
            onKeyboardPan?(0, 1, bounds.size)
        default:
            super.keyDown(with: event)
        }
    }
}
