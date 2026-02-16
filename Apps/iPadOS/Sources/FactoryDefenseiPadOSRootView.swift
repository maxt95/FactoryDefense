import MetalKit
import SwiftUI
import UIKit
import GameRendering
import GameSimulation
import GameUI
import GamePlatform

struct FactoryDefenseiPadOSRootView: View {
    @State private var didStartGame = false

    var body: some View {
        if didStartGame {
            FactoryDefenseiPadOSGameplayView()
        } else {
            FactoryDefenseMainMenu(
                title: "Factory Defense",
                onStart: { didStartGame = true }
            )
        }
    }
}

private struct FactoryDefenseMainMenu: View {
    let title: String
    let onStart: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.11, blue: 0.19), Color(red: 0.04, green: 0.06, blue: 0.11)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Button("Start", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding()
        }
    }
}

private struct FactoryDefenseiPadOSGameplayView: View {
    @StateObject private var runtime = GameRuntimeController()
    @State private var buildMenu = BuildMenuViewModel.productionPreset
    @State private var techTree = TechTreeViewModel.productionPreset
    @State private var onboarding = OnboardingGuideViewModel.starter
    @State private var overlayLayout = GameplayOverlayLayoutState.defaultLayout(
        viewportSize: CGSize(width: 1280, height: 900)
    )
    @State private var cameraState = WhiteboxCameraState()
    @State private var dragTranslation: CGSize = .zero
    @State private var zoomGestureScale: CGFloat = 1
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
                    onKeyboardPan: { dx, dy, viewport in
                        handleKeyboardPan(deltaX: dx, deltaY: dy, viewport: viewport)
                    }
                )
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            handleTap(at: value.location, viewport: proxy.size)
                        }
                )
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
                            let anchor = CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
                            zoomCamera(scale: Float(1 / delta), around: anchor, viewport: proxy.size)
                            zoomGestureScale = scale
                        }
                        .onEnded { _ in
                            zoomGestureScale = 1
                        }
                )

                if let inspector = selectedInspectorModel() {
                    ObjectInspectorPopup(
                        model: inspector,
                        onClose: { selectedEntityID = nil }
                    )
                    .frame(width: 320)
                    .position(inspectorPosition(for: inspector, viewport: proxy.size))
                }

                GameplayOverlayHost(
                    layoutState: $overlayLayout,
                    viewportSize: proxy.size,
                    safeAreaInsets: safeAreaInsets(from: proxy),
                    windows: overlayWindowDefinitions
                ) { windowID in
                    overlayContent(for: windowID)
                }
            }
            .onAppear {
                runtime.start()
                if buildMenu.selectedEntryID == nil, let first = buildMenu.entries.first {
                    buildMenu.select(entryID: first.id)
                }
                onboarding.update(from: runtime.world)
                enforceCameraConstraints(viewport: proxy.size)
                syncOverlayLayout(viewport: proxy.size, safeAreaInsets: safeAreaInsets(from: proxy))
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
                syncOverlayLayout(viewport: proxy.size, safeAreaInsets: safeAreaInsets(from: proxy))
            }
        }
    }

    private var overlayWindowDefinitions: [GameplayOverlayWindowDefinition] {
        [
            GameplayOverlayWindowDefinition(id: .topControls, title: "Controls", preferredWidth: 580, preferredHeight: 120),
            GameplayOverlayWindowDefinition(id: .resources, title: "Resources", preferredWidth: 860, preferredHeight: 260),
            GameplayOverlayWindowDefinition(id: .buildMenu, title: "Build", preferredWidth: 320, preferredHeight: 520),
            GameplayOverlayWindowDefinition(id: .buildingReference, title: "Buildings", preferredWidth: 300, preferredHeight: 520),
            GameplayOverlayWindowDefinition(id: .tileLegend, title: "Tile Legend", preferredWidth: 300, preferredHeight: 340),
            GameplayOverlayWindowDefinition(id: .techTree, title: "Tech Tree", preferredWidth: 360, preferredHeight: 320),
            GameplayOverlayWindowDefinition(id: .onboarding, title: "Objectives", preferredWidth: 360, preferredHeight: 340),
            GameplayOverlayWindowDefinition(id: .tuningDashboard, title: "Telemetry", preferredWidth: 260, preferredHeight: 260)
        ]
    }

    @ViewBuilder
    private func overlayContent(for windowID: GameplayOverlayWindowID) -> some View {
        switch windowID {
        case .topControls:
            HStack {
                Text("Factory Defense iPadOS")
                    .font(.headline)
                    .padding(10)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(placementLabel(runtime.placementResult))
                    .font(.caption)
                    .padding(10)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Spacer(minLength: 8)

                Button("Wave") { runtime.triggerWave() }
                    .buttonStyle(.borderedProminent)
                Button("Extract") { runtime.extract() }
                    .buttonStyle(.bordered)
            }
            .padding(10)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))

        case .resources:
            ResourceHUDPanel(world: runtime.world)

        case .buildMenu:
            BuildMenuPanel(viewModel: buildMenu, inventory: inventory) { entry in
                buildMenu.select(entryID: entry.id)
            }

        case .buildingReference:
            BuildingReferencePanel(world: runtime.world)

        case .tileLegend:
            TileLegendPanel()

        case .techTree:
            TechTreePanel(nodes: techTree.nodes(inventory: inventory))

        case .onboarding:
            OnboardingPanel(steps: onboarding.steps)

        case .tuningDashboard:
            TuningDashboardPanel(snapshot: .from(world: runtime.world))
        }
    }

    private func safeAreaInsets(from proxy: GeometryProxy) -> SafeAreaInsets {
        SafeAreaInsets(
            top: proxy.safeAreaInsets.top,
            leading: proxy.safeAreaInsets.leading,
            bottom: proxy.safeAreaInsets.bottom,
            trailing: proxy.safeAreaInsets.trailing
        )
    }

    private func syncOverlayLayout(viewport: CGSize, safeAreaInsets: SafeAreaInsets) {
        for definition in overlayWindowDefinitions {
            overlayLayout.ensureWindow(
                id: definition.id,
                defaultOrigin: defaultOrigin(for: definition.id),
                defaultSize: CGSize(width: definition.preferredWidth, height: definition.preferredHeight),
                viewportSize: viewport,
                safeAreaInsets: safeAreaInsets
            )
        }
        overlayLayout.clampToViewport(viewport, safeAreaInsets: safeAreaInsets)
    }

    private func defaultOrigin(for windowID: GameplayOverlayWindowID) -> CGPoint {
        switch windowID {
        case .topControls:
            return CGPoint(x: 16, y: 16)
        case .resources:
            return CGPoint(x: 16, y: 124)
        case .buildMenu:
            return CGPoint(x: 16, y: 356)
        case .buildingReference:
            return CGPoint(x: 348, y: 356)
        case .tileLegend:
            return CGPoint(x: 1032, y: 356)
        case .techTree:
            return CGPoint(x: 660, y: 356)
        case .onboarding:
            return CGPoint(x: 660, y: 668)
        case .tuningDashboard:
            return CGPoint(x: 660, y: 980)
        }
    }

    private func placementLabel(_ result: PlacementResult) -> String {
        switch result {
        case .ok:
            return "Valid"
        case .occupied:
            return "Occupied"
        case .outOfBounds:
            return "Out"
        case .blocksCriticalPath:
            return "Blocks"
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
        picker.gridPosition(
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

private struct MetalSurfaceView: UIViewRepresentable {
    var world: WorldState
    var cameraState: WhiteboxCameraState
    var highlightedCell: GridPosition?
    var highlightedStructure: StructureType?
    var placementResult: PlacementResult
    var onKeyboardPan: (Float, Float, CGSize) -> Void

    func makeUIView(context: Context) -> MTKView {
        let view = KeyboardPannableMTKView(frame: .zero)
        view.onKeyboardPan = onKeyboardPan
        if let renderer = context.coordinator.renderer {
            renderer.attach(to: view)
        }
        DispatchQueue.main.async {
            _ = view.becomeFirstResponder()
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        if let interactiveView = uiView as? KeyboardPannableMTKView {
            interactiveView.onKeyboardPan = onKeyboardPan
            _ = interactiveView.becomeFirstResponder()
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

private final class KeyboardPannableMTKView: MTKView {
    var onKeyboardPan: ((Float, Float, CGSize) -> Void)?

    override var canBecomeFirstResponder: Bool {
        true
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleKeyCommand(_:))),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleKeyCommand(_:))),
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(handleKeyCommand(_:))),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(handleKeyCommand(_:))),
            UIKeyCommand(input: "w", modifierFlags: [], action: #selector(handleKeyCommand(_:))),
            UIKeyCommand(input: "a", modifierFlags: [], action: #selector(handleKeyCommand(_:))),
            UIKeyCommand(input: "s", modifierFlags: [], action: #selector(handleKeyCommand(_:))),
            UIKeyCommand(input: "d", modifierFlags: [], action: #selector(handleKeyCommand(_:))),
            UIKeyCommand(input: "W", modifierFlags: [.shift], action: #selector(handleKeyCommand(_:))),
            UIKeyCommand(input: "A", modifierFlags: [.shift], action: #selector(handleKeyCommand(_:))),
            UIKeyCommand(input: "S", modifierFlags: [.shift], action: #selector(handleKeyCommand(_:))),
            UIKeyCommand(input: "D", modifierFlags: [.shift], action: #selector(handleKeyCommand(_:)))
        ]
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            _ = self?.becomeFirstResponder()
        }
    }

    @objc private func handleKeyCommand(_ sender: UIKeyCommand) {
        guard let input = sender.input else { return }
        switch input {
        case UIKeyCommand.inputLeftArrow, "a", "A":
            onKeyboardPan?(-1, 0, bounds.size)
        case UIKeyCommand.inputRightArrow, "d", "D":
            onKeyboardPan?(1, 0, bounds.size)
        case UIKeyCommand.inputUpArrow, "w", "W":
            onKeyboardPan?(0, -1, bounds.size)
        case UIKeyCommand.inputDownArrow, "s", "S":
            onKeyboardPan?(0, 1, bounds.size)
        default:
            return
        }
    }
}
