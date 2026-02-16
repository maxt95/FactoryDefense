import AppKit
import MetalKit
import SwiftUI
import GameRendering
import GameSimulation
import GameUI
import GamePlatform

@main
struct FactoryDefenseApp: App {
    var body: some Scene {
        WindowGroup {
            FactoryDefenseRootView()
                .frame(minWidth: 1024, minHeight: 640)
        }
        .windowResizability(.contentSize)
    }
}

private struct RunConfiguration: Hashable {
    var difficulty: Difficulty
    var seed: RunSeed
}

private enum AppScreen: Hashable {
    case mainMenu
    case difficultySelect
    case gameplay(RunConfiguration)
    case runSummary(RunSummarySnapshot)
}

private struct FactoryDefenseRootView: View {
    @State private var screen: AppScreen = .mainMenu
    @AppStorage("settings.enableDebugViews") private var enableDebugViews = false

    var body: some View {
        switch screen {
        case .mainMenu:
            FactoryDefenseMainMenu(
                title: "Factory Defense",
                enableDebugViews: $enableDebugViews,
                onStart: { screen = .difficultySelect },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        case .difficultySelect:
            FactoryDefenseDifficultySelect(
                onSelectDifficulty: { difficulty in
                    let run = RunConfiguration(
                        difficulty: difficulty,
                        seed: RunSeed.random(in: RunSeed.min ... RunSeed.max)
                    )
                    screen = .gameplay(run)
                },
                onBack: { screen = .mainMenu }
            )
        case .gameplay(let run):
            FactoryDefenseGameplayView(
                initialWorld: .bootstrap(difficulty: run.difficulty, seed: run.seed),
                enableDebugViews: enableDebugViews,
                onRunEnded: { summary in
                    screen = .runSummary(summary)
                }
            )
            .id("gameplay-\(run.difficulty.rawValue)-\(run.seed)")
        case .runSummary(let summary):
            FactoryDefenseRunSummaryView(
                summary: summary,
                onNewRun: { screen = .difficultySelect },
                onMainMenu: { screen = .mainMenu }
            )
        }
    }
}

private struct FactoryDefenseMainMenu: View {
    let title: String
    @Binding var enableDebugViews: Bool
    let onStart: () -> Void
    let onQuit: () -> Void
    @State private var showsSettings = false

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

                    Button("Settings") {
                        showsSettings = true
                    }
                    .buttonStyle(.bordered)
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
        .sheet(isPresented: $showsSettings) {
            FactoryDefenseSettingsView(enableDebugViews: $enableDebugViews)
        }
    }
}

private struct FactoryDefenseSettingsView: View {
    @Binding var enableDebugViews: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2.weight(.semibold))

            Toggle("Enable Debug Views", isOn: $enableDebugViews)
                .toggleStyle(.switch)

            Text("When enabled, gameplay runs with tactical debug overlays.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
    }
}

private struct FactoryDefenseDifficultySelect: View {
    let onSelectDifficulty: (Difficulty) -> Void
    let onBack: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.12, blue: 0.18), Color(red: 0.05, green: 0.07, blue: 0.11)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("Select Difficulty")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(spacing: 12) {
                    Button("Easy") { onSelectDifficulty(.easy) }
                        .buttonStyle(.borderedProminent)
                    Button("Normal") { onSelectDifficulty(.normal) }
                        .buttonStyle(.borderedProminent)
                    Button("Hard") { onSelectDifficulty(.hard) }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)

                Button("Back", action: onBack)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}

private struct FactoryDefenseRunSummaryView: View {
    let summary: RunSummarySnapshot
    let onNewRun: () -> Void
    let onMainMenu: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.11, blue: 0.17), Color(red: 0.04, green: 0.06, blue: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Run Summary")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 10) {
                    summaryRow("Waves survived", "\(summary.wavesSurvived)")
                    summaryRow("Run duration", formattedDuration(summary.runDurationSeconds))
                    summaryRow("Enemies destroyed", "\(summary.enemiesDestroyed)")
                    summaryRow("Structures built", "\(summary.structuresBuilt)")
                    summaryRow("Ammo spent", "\(summary.ammoSpent)")
                }
                .frame(maxWidth: 360)

                HStack(spacing: 12) {
                    Button("New Run", action: onNewRun)
                        .buttonStyle(.borderedProminent)
                    Button("Main Menu", action: onMainMenu)
                        .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text(value)
                .foregroundStyle(.white)
                .fontWeight(.semibold)
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        let remaining = clamped % 60
        let paddedSeconds = remaining < 10 ? "0\(remaining)" : "\(remaining)"
        return "\(minutes)m \(paddedSeconds)s"
    }
}

private struct FactoryDefenseGameplayView: View {
    @StateObject private var runtime: GameRuntimeController
    @State private var buildMenu = BuildMenuViewModel.productionPreset
    @State private var techTree = TechTreeViewModel.productionPreset
    @State private var onboarding = OnboardingGuideViewModel.starter
    @State private var interaction = GameplayInteractionState()
    @StateObject private var placementFeedback = PlacementFeedbackController()
    @State private var overlayLayout = GameplayOverlayLayoutState.defaultLayout(
        viewportSize: CGSize(width: 1280, height: 720)
    )
    @State private var cameraState = WhiteboxCameraState()
    @State private var dragTranslation: CGSize = .zero
    @State private var zoomGestureScale: CGFloat = 1
    @State private var didReportRunSummary = false

    let enableDebugViews: Bool
    let onRunEnded: (RunSummarySnapshot) -> Void

    init(
        initialWorld: WorldState,
        enableDebugViews: Bool,
        onRunEnded: @escaping (RunSummarySnapshot) -> Void
    ) {
        _runtime = StateObject(wrappedValue: GameRuntimeController(initialWorld: initialWorld))
        self.enableDebugViews = enableDebugViews
        self.onRunEnded = onRunEnded
    }

    private static let keyboardPanStep: Float = 56
    private let dragDrawPlanner = GameplayDragDrawPlanner()

    private var selectedStructure: StructureType {
        interaction.selectedStructure(from: buildMenu)
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
                    debugMode: enableDebugViews ? .tactical : .none,
                    highlightedCell: runtime.highlightedCell,
                    highlightedStructure: interaction.isBuildMode && runtime.highlightedCell != nil ? selectedStructure : nil,
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
                            handleDragChanged(value, viewport: proxy.size)
                        }
                        .onEnded { value in
                            handleDragEnded(value, viewport: proxy.size)
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
            .onChange(of: runtime.runSummary) { _, summary in
                guard let summary, !didReportRunSummary else { return }
                didReportRunSummary = true
                onRunEnded(summary)
            }
            .onChange(of: runtime.world.tick) { _, _ in
                onboarding.update(from: runtime.world)
            }
            .onChange(of: runtime.latestEvents) { _, events in
                placementFeedback.consume(events: events)
            }
            .onChange(of: runtime.world.board) { oldBoard, newBoard in
                reconcileCameraForBoardChange(from: oldBoard, to: newBoard, viewport: proxy.size)
            }
            .onChange(of: buildMenu.selectedEntryID) { _, _ in
                if interaction.isBuildMode, let highlighted = runtime.highlightedCell {
                    runtime.previewPlacement(structure: selectedStructure, at: highlighted)
                } else {
                    runtime.clearPlacementPreview()
                }
            }
            .onChange(of: interaction.mode) { _, mode in
                switch mode {
                case .build:
                    if let highlighted = runtime.highlightedCell {
                        runtime.previewPlacement(structure: selectedStructure, at: highlighted)
                    }
                case .interact:
                    runtime.clearPlacementPreview()
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
            GameplayOverlayWindowDefinition(id: .topControls, title: "Controls", preferredWidth: 560, preferredHeight: 120),
            GameplayOverlayWindowDefinition(id: .resources, title: "Resources", preferredWidth: 860, preferredHeight: 260),
            GameplayOverlayWindowDefinition(id: .buildMenu, title: "Build", preferredWidth: 320, preferredHeight: 520),
            GameplayOverlayWindowDefinition(id: .buildingReference, title: "Buildings", preferredWidth: 300, preferredHeight: 520),
            GameplayOverlayWindowDefinition(id: .tileLegend, title: "Tile Legend", preferredWidth: 300, preferredHeight: 340),
            GameplayOverlayWindowDefinition(id: .techTree, title: "Tech Tree", preferredWidth: 360, preferredHeight: 320),
            GameplayOverlayWindowDefinition(id: .onboarding, title: "Objectives", preferredWidth: 360, preferredHeight: 340),
            GameplayOverlayWindowDefinition(id: .tuningDashboard, title: "Telemetry", preferredWidth: 240, preferredHeight: 260)
        ]
    }

    @ViewBuilder
    private func overlayContent(for windowID: GameplayOverlayWindowID) -> some View {
        switch windowID {
        case .topControls:
            HStack {
                Text("Factory Defense")
                    .font(.headline)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text("Placement: \(placementLabel(placementFeedback.displayedResult(current: runtime.placementResult)))")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Picker("Mode", selection: $interaction.mode) {
                    ForEach(GameplayInteractionMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 210)

                Spacer(minLength: 8)

                Button("Wave") { runtime.triggerWave() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))

        case .resources:
            ResourceHUDPanel(world: runtime.world)

        case .buildMenu:
            BuildMenuPanel(viewModel: buildMenu, inventory: inventory) { entry in
                interaction.selectBuildEntry(entry.id, in: &buildMenu)
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
            return "Out of bounds"
        case .blocksCriticalPath:
            return "Blocks path"
        case .restrictedZone:
            return "Restricted"
        case .insufficientResources:
            return "Insufficient resources"
        case .invalidMinerPlacement:
            return "Needs adjacent ore patch"
        case .invalidTurretMountPlacement:
            return "Requires wall segment"
        case .invalidRemoval:
            return "Cannot remove"
        }
    }

    private func handleTap(at location: CGPoint, viewport: CGSize) {
        guard let position = pickGrid(at: location, viewport: viewport) else {
            runtime.clearPlacementPreview()
            return
        }

        guard interaction.isBuildMode else {
            runtime.clearPlacementPreview()
            return
        }

        runtime.placeStructure(selectedStructure, at: position)
        if interaction.completePlacementIfSuccessful(runtime.placementResult) {
            runtime.clearPlacementPreview()
        }
    }

    private func previewPlacement(at location: CGPoint, viewport: CGSize) {
        guard interaction.isBuildMode else {
            runtime.clearPlacementPreview()
            return
        }
        guard let position = pickGrid(at: location, viewport: viewport) else {
            runtime.clearPlacementPreview()
            return
        }
        runtime.previewPlacement(structure: selectedStructure, at: position)
    }

    private func handleDragChanged(_ value: DragGesture.Value, viewport: CGSize) {
        if interaction.isBuildMode, dragDrawPlanner.supportsDragDraw(for: selectedStructure) {
            if !interaction.isDragDrawActive,
               let start = pickGrid(at: value.startLocation, viewport: viewport) {
                interaction.beginDragDraw(at: start)
            }
            if let current = pickGrid(at: value.location, viewport: viewport) {
                interaction.updateDragDraw(at: current)
                runtime.previewPlacement(structure: selectedStructure, at: current)
            } else {
                runtime.clearPlacementPreview()
            }
            return
        }

        let deltaX = value.translation.width - dragTranslation.width
        let deltaY = value.translation.height - dragTranslation.height
        cameraState.panBy(deltaX: -Float(deltaX), deltaY: -Float(deltaY))
        enforceCameraConstraints(viewport: viewport)
        dragTranslation = value.translation
        previewPlacement(at: value.location, viewport: viewport)
    }

    private func handleDragEnded(_ value: DragGesture.Value, viewport: CGSize) {
        defer { dragTranslation = .zero }

        guard interaction.isBuildMode, dragDrawPlanner.supportsDragDraw(for: selectedStructure) else {
            interaction.cancelDragDraw()
            return
        }

        if let current = pickGrid(at: value.location, viewport: viewport) {
            interaction.updateDragDraw(at: current)
        }
        let path = interaction.finishDragDraw(using: dragDrawPlanner)
        guard path.count > 1 else { return }

        runtime.placeStructurePath(selectedStructure, along: path)
        if let end = path.last {
            runtime.previewPlacement(structure: selectedStructure, at: end)
        } else {
            runtime.clearPlacementPreview()
        }
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
        // macOS gesture coordinates read about half a tile high versus rendered board cells.
        let zoom = max(0.001, CGFloat(cameraState.zoom))
        let adjustedLocation = CGPoint(
            x: location.x,
            y: location.y + (22.0 * zoom * 0.5)
        )
        return WhiteboxPicker().gridPosition(
            at: adjustedLocation,
            viewport: viewport,
            board: runtime.world.board,
            camera: cameraState
        )
    }
}

private struct MetalSurfaceView: NSViewRepresentable {
    var world: WorldState
    var cameraState: WhiteboxCameraState
    var debugMode: DebugVisualizationMode
    var highlightedCell: GridPosition?
    var highlightedStructure: StructureType?
    var placementResult: PlacementResult
    var onKeyboardPan: (Float, Float, CGSize) -> Void

    func makeNSView(context: Context) -> MTKView {
        let view = KeyboardPannableMTKView(frame: .zero)
        view.onKeyboardPan = onKeyboardPan
        if let renderer = context.coordinator.renderer {
            renderer.debugMode = debugMode
            renderer.attach(to: view)
        }
        view.window?.makeFirstResponder(view)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        if let interactiveView = nsView as? KeyboardPannableMTKView {
            interactiveView.onKeyboardPan = onKeyboardPan
            interactiveView.window?.makeFirstResponder(interactiveView)
        }
        renderer.worldState = world
        renderer.cameraState = cameraState
        renderer.debugMode = debugMode
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

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
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
