import AppKit
import MetalKit
import SwiftUI
import GameRendering
import GameSimulation
import GameUI
import GamePlatform

struct FactoryDefensemacOSRootView: View {
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
            FactoryDefensemacOSGameplayView(
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

private struct FactoryDefensemacOSGameplayView: View {
    private enum SelectionTarget: Equatable {
        case entity(EntityID)
        case orePatch(Int)
    }

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
    @State private var renderDiagnostic: String?
    @State private var selectedTarget: SelectionTarget?
    @State private var conveyorInputDirection: CardinalDirection = .west
    @State private var conveyorOutputDirection: CardinalDirection = .east
    @State private var didReportRunSummary = false
    @State private var hoveredGridPosition: GridPosition?

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
    private let picker = WhiteboxPicker()
    private let objectInspectorBuilder = ObjectInspectorBuilder()
    private let orePatchInspectorBuilder = OrePatchInspectorBuilder()
    private let dragDrawPlanner = GameplayDragDrawPlanner()
    private let snapResolver = ConveyorSnapResolver()

    private var selectedStructure: StructureType {
        interaction.selectedStructure(from: buildMenu)
    }

    private var inventory: [String: Int] {
        runtime.world.economy.inventories
    }

    private var dragPreviewAffordableCount: Int {
        guard interaction.isDragDrawActive else { return 0 }
        let affordable = interaction.previewAffordableCount(
            for: selectedStructure,
            inventory: runtime.world.economy.inventories
        )
        return min(affordable, interaction.dragPreviewPath.count)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MetalSurfaceView(
                    world: runtime.world,
                    cameraState: cameraState,
                    debugMode: enableDebugViews ? .tactical : .none,
                    highlightedCell: runtime.highlightedCell,
                    highlightedPath: interaction.dragPreviewPath,
                    highlightedAffordableCount: dragPreviewAffordableCount,
                    highlightedStructure: interaction.isBuildMode && runtime.highlightedCell != nil ? selectedStructure : nil,
                    placementResult: runtime.placementResult,
                    onTap: { location, viewport in
                        handleTap(at: location, viewport: viewport)
                    },
                    onPointerMove: { location, viewport in
                        handlePointerMove(at: location, viewport: viewport)
                    },
                    onScrollZoom: { delta, location, viewport in
                        let scale: Float = delta < 0 ? 0.92 : 1.08
                        zoomCamera(scale: scale, around: location, viewport: viewport)
                    },
                    onKeyboardPan: { dx, dy, viewport in
                        handleKeyboardPan(deltaX: dx, deltaY: dy, viewport: viewport)
                    },
                    onKeyAction: { action, viewport in
                        handleKeyAction(action, viewport: viewport)
                    }
                )
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
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
                            let inverted = Float(1 / delta)
                            let anchor = CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
                            zoomCamera(scale: inverted, around: anchor, viewport: proxy.size)
                            zoomGestureScale = scale
                        }
                        .onEnded { _ in
                            zoomGestureScale = 1
                        }
                )

                if interaction.mode == .interact {
                    if let inspector = selectedEntityInspectorModel() {
                        let inspectorPosition = inspectorPosition(for: inspector, viewport: proxy.size)
                        ObjectInspectorPopup(
                            model: inspector,
                            onClose: { selectedTarget = nil }
                        )
                        .frame(width: 320)
                        .position(inspectorPosition)
                    } else if let inspector = selectedOrePatchInspectorModel() {
                        let inspectorPosition = inspectorPosition(for: inspector, viewport: proxy.size)
                        OrePatchInspectorPopup(
                            model: inspector,
                            onClose: { selectedTarget = nil }
                        )
                        .frame(width: 320)
                        .position(inspectorPosition)
                    }
                }

                GameplayOverlayHost(
                    layoutState: $overlayLayout,
                    viewportSize: proxy.size,
                    safeAreaInsets: safeAreaInsets(from: proxy),
                    windows: overlayWindowDefinitions
                ) { windowID in
                    overlayContent(for: windowID)
                }

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
                validateSelection()
            }
            .onChange(of: runtime.latestEvents) { _, events in
                placementFeedback.consume(events: events)
            }
            .onChange(of: runtime.world.board) { oldBoard, newBoard in
                reconcileCameraForBoardChange(from: oldBoard, to: newBoard, viewport: proxy.size)
            }
            .onChange(of: buildMenu.selectedEntryID) { _, _ in
                refreshPlacementPreview(viewport: proxy.size)
            }
            .onChange(of: interaction.mode) { _, mode in
                switch mode {
                case .build:
                    selectedTarget = nil
                    refreshPlacementPreview(viewport: proxy.size)
                case .interact, .editBelts, .planBelt:
                    runtime.clearPlacementPreview()
                }
            }
            .onChange(of: selectedTarget) { _, _ in
                syncSelectedConveyorEditor()
            }
            .onChange(of: proxy.size) { _, _ in
                enforceCameraConstraints(viewport: proxy.size)
                syncOverlayLayout(viewport: proxy.size, safeAreaInsets: safeAreaInsets(from: proxy))
            }
            .alert(
                "Remove structure?",
                isPresented: Binding(
                    get: { interaction.pendingDemolishEntityID != nil },
                    set: { presented in
                        if !presented {
                            interaction.cancelDemolish()
                        }
                    }
                )
            ) {
                Button("Cancel", role: .cancel) {
                    interaction.cancelDemolish()
                }
                Button("Remove", role: .destructive) {
                    guard let entityID = interaction.confirmDemolish() else { return }
                    runtime.removeStructure(entityID: entityID)
                    if selectedDemolishableEntityID == entityID {
                        selectedTarget = nil
                    }
                }
            } message: {
                Text("This removes the selected structure and refunds 50% of its build cost.")
            }
            .onReceive(NotificationCenter.default.publisher(for: RenderDiagnostics.notificationName)) { note in
                renderDiagnostic = note.userInfo?[RenderDiagnostics.messageKey] as? String
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
                Text("Factory Defense macOS")
                    .font(.headline)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text("Placement: \(placementLabel(placementFeedback.displayedResult(current: runtime.placementResult)))")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if interaction.isDragDrawActive {
                    Text("Preview: \(interaction.dragPreviewPath.count) tiles")
                        .font(.caption)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Picker("Mode", selection: $interaction.mode) {
                    ForEach(GameplayInteractionMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 210)

                Button("Demolish") {
                    requestDemolishSelected()
                }
                .buttonStyle(.bordered)
                .disabled(selectedDemolishableEntityID == nil)

                if interaction.mode == .interact, let selectedConveyorEntityID {
                    Divider()
                        .frame(height: 20)
                    Text("Conveyor I/O")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Input", selection: $conveyorInputDirection) {
                        ForEach(CardinalDirection.allCases, id: \.self) { direction in
                            Text(direction.rawValue.capitalized).tag(direction)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 100)
                    Picker("Output", selection: $conveyorOutputDirection) {
                        ForEach(CardinalDirection.allCases, id: \.self) { direction in
                            Text(direction.rawValue.capitalized).tag(direction)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 100)
                    Button("Apply") {
                        runtime.configureConveyorIO(
                            entityID: selectedConveyorEntityID,
                            inputDirection: conveyorInputDirection,
                            outputDirection: conveyorOutputDirection
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(conveyorInputDirection == conveyorOutputDirection)
                }

                Spacer(minLength: 8)
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))

        case .resources:
            ResourceHUDPanel(world: runtime.world, techNodes: techTree.nodes(inventory: inventory))

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
            selectedTarget = nil
            return
        }

        switch interaction.mode {
        case .interact:
            runtime.clearPlacementPreview()
            if let tappedEntity = runtime.world.entities.selectableEntity(at: position) {
                if selectedTarget == .entity(tappedEntity.id) {
                    selectedTarget = nil
                } else {
                    selectedTarget = .entity(tappedEntity.id)
                }
            } else if let patch = orePatch(at: position) {
                if selectedTarget == .orePatch(patch.id) {
                    selectedTarget = nil
                } else {
                    selectedTarget = .orePatch(patch.id)
                }
            } else {
                selectedTarget = nil
            }
        case .build:
            selectedTarget = nil
            if dragDrawPlanner.supportsDragDraw(for: selectedStructure) {
                runtime.previewPlacement(structure: selectedStructure, at: position)
                return
            }
            runtime.placeStructure(selectedStructure, at: position)
            if interaction.completePlacementIfSuccessful(runtime.placementResult) {
                runtime.clearPlacementPreview()
            }
        case .editBelts:
            // Tap in edit-belts mode: no action (drag to flow-brush, F to reverse)
            break
        case .planBelt:
            if interaction.beltPlanner.startPin == nil {
                interaction.beltPlanner.setStart(position)
            } else {
                interaction.beltPlanner.setEnd(position)
            }
        }
    }

    private var hoveredConveyorEntityID: EntityID? {
        guard let pos = hoveredGridPosition,
              let entity = runtime.world.entities.selectableEntity(at: pos),
              entity.structureType == .conveyor else {
            return nil
        }
        return entity.id
    }

    private func handlePointerMove(at location: CGPoint, viewport: CGSize) {
        hoveredGridPosition = pickGrid(at: location, viewport: viewport)
        guard interaction.isBuildMode else {
            runtime.clearPlacementPreview()
            return
        }
        guard let position = hoveredGridPosition else {
            runtime.clearPlacementPreview()
            return
        }
        runtime.previewPlacement(structure: selectedStructure, at: position)
    }

    private func handleKeyAction(_ action: KeyAction, viewport: CGSize) {
        switch action {
        case .rotateCW:
            if interaction.mode == .build, interaction.isDragDrawActive {
                // During drag: cycle corner preference (future enhancement)
                return
            }
            if let entityID = hoveredConveyorEntityID {
                rotateConveyor(entityID: entityID, clockwise: true)
            }

        case .rotateCCW:
            if let entityID = hoveredConveyorEntityID {
                rotateConveyor(entityID: entityID, clockwise: false)
            }

        case .reverse:
            if interaction.mode == .editBelts, let entityID = hoveredConveyorEntityID {
                reverseConveyorRun(startingFrom: entityID)
            } else if let entityID = hoveredConveyorEntityID {
                reverseSingleConveyor(entityID: entityID)
            }

        case .toggleEditBelts:
            if interaction.mode == .editBelts {
                interaction.exitEditBeltsMode()
            } else {
                interaction.enterEditBeltsMode()
            }

        case .togglePlanBelt:
            if interaction.mode == .planBelt {
                interaction.exitPlanBeltMode()
            } else {
                interaction.enterPlanBeltMode()
            }

        case .confirm:
            if interaction.mode == .planBelt {
                let cells = interaction.beltPlanner.confirm()
                guard !cells.isEmpty else { return }
                runtime.placeConveyorPath(cells.map {
                    ConveyorPlacementCell(
                        position: $0.position,
                        inputDirection: $0.inputDirection,
                        outputDirection: $0.outputDirection,
                        isCorner: $0.isCorner
                    )
                })
            }

        case .cancel:
            switch interaction.mode {
            case .build:
                if interaction.isDragDrawActive {
                    interaction.cancelDragDraw()
                } else {
                    interaction.exitBuildMode()
                }
            case .editBelts:
                if interaction.flowBrush.isActive {
                    interaction.flowBrush.cancelStroke()
                } else {
                    interaction.exitEditBeltsMode()
                }
            case .planBelt:
                interaction.exitPlanBeltMode()
            case .interact:
                break
            }
        }
    }

    private func rotateConveyor(entityID: EntityID, clockwise: Bool) {
        guard let entity = runtime.world.entities.entity(id: entityID) else { return }
        let io = runtime.world.economy.conveyorIOByEntity[entityID]
            ?? ConveyorIOConfig.default(for: entity.rotation)
        let newOutput = clockwise ? io.outputDirection.right : io.outputDirection.left
        runtime.configureConveyorIO(
            entityID: entityID,
            inputDirection: newOutput.opposite,
            outputDirection: newOutput
        )
    }

    private func reverseSingleConveyor(entityID: EntityID) {
        guard let entity = runtime.world.entities.entity(id: entityID) else { return }
        let io = runtime.world.economy.conveyorIOByEntity[entityID]
            ?? ConveyorIOConfig.default(for: entity.rotation)
        runtime.configureConveyorIO(
            entityID: entityID,
            inputDirection: io.outputDirection,
            outputDirection: io.inputDirection
        )
    }

    private func reverseConveyorRun(startingFrom entityID: EntityID) {
        let changes = computeRunReversal(startingFrom: entityID)
        for change in changes {
            runtime.configureConveyorIO(
                entityID: change.entityID,
                inputDirection: change.newInput,
                outputDirection: change.newOutput
            )
        }
    }

    private struct RunReversalChange {
        var entityID: EntityID
        var newInput: CardinalDirection
        var newOutput: CardinalDirection
    }

    private func computeRunReversal(startingFrom entityID: EntityID) -> [RunReversalChange] {
        let entities = runtime.world.entities
        let conveyorIO = runtime.world.economy.conveyorIOByEntity
        var visited = Set<EntityID>()
        var queue = [entityID]
        var changes: [RunReversalChange] = []

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard !visited.contains(current) else { continue }
            visited.insert(current)

            guard let entity = entities.entity(id: current),
                  entity.structureType == .conveyor else { continue }

            let io = conveyorIO[current] ?? ConveyorIOConfig.default(for: entity.rotation)
            changes.append(RunReversalChange(
                entityID: current,
                newInput: io.outputDirection,
                newOutput: io.inputDirection
            ))

            // Follow connections in both directions
            let outputPos = entity.position.translated(by: io.outputDirection)
            let inputPos = entity.position.translated(by: io.inputDirection)

            for neighborPos in [outputPos, inputPos] {
                guard let neighbor = entities.selectableEntity(at: neighborPos),
                      neighbor.structureType == .conveyor,
                      !visited.contains(neighbor.id) else { continue }

                // Verify it's actually connected
                let neighborIO = conveyorIO[neighbor.id]
                    ?? ConveyorIOConfig.default(for: neighbor.rotation)
                let neighborOutputPos = neighbor.position.translated(by: neighborIO.outputDirection)
                let neighborInputPos = neighbor.position.translated(by: neighborIO.inputDirection)

                if neighborOutputPos == entity.position || neighborInputPos == entity.position {
                    queue.append(neighbor.id)
                }
            }
        }
        return changes
    }

    private func handleDragChanged(_ value: DragGesture.Value, viewport: CGSize) {
        if interaction.isBuildMode, dragDrawPlanner.supportsDragDraw(for: selectedStructure) {
            if !interaction.isDragDrawActive,
               let start = pickGrid(at: value.startLocation, viewport: viewport) {
                interaction.beginDragDraw(at: start)
            }
            if let current = pickGrid(at: value.location, viewport: viewport) {
                if selectedStructure == .conveyor {
                    interaction.accumulateConveyorDragCell(current)
                } else {
                    interaction.updateDragDraw(at: current)
                }
                runtime.previewPlacement(structure: selectedStructure, at: current)
            } else {
                runtime.clearPlacementPreview()
            }
            return
        }

        if interaction.mode == .editBelts {
            if !interaction.flowBrush.isActive,
               let start = pickGrid(at: value.startLocation, viewport: viewport) {
                interaction.flowBrush.beginStroke(at: start)
            }
            if let current = pickGrid(at: value.location, viewport: viewport) {
                interaction.flowBrush.extendStroke(to: current)
            }
            return
        }

        let deltaX = value.translation.width - dragTranslation.width
        let deltaY = value.translation.height - dragTranslation.height
        cameraState.panBy(deltaX: -Float(deltaX), deltaY: -Float(deltaY))
        enforceCameraConstraints(viewport: viewport)
        dragTranslation = value.translation
        handlePointerMove(at: value.location, viewport: viewport)
    }

    private func handleDragEnded(_ value: DragGesture.Value, viewport: CGSize) {
        defer { dragTranslation = .zero }

        // Handle flow brush stroke completion in edit-belts mode
        if interaction.mode == .editBelts, interaction.flowBrush.isActive {
            if let current = pickGrid(at: value.location, viewport: viewport) {
                interaction.flowBrush.extendStroke(to: current)
            }
            let changes = interaction.flowBrush.finishStroke()
            applyFlowBrushChanges(changes)
            return
        }

        guard interaction.isBuildMode, dragDrawPlanner.supportsDragDraw(for: selectedStructure) else {
            interaction.cancelDragDraw()
            return
        }

        if let current = pickGrid(at: value.location, viewport: viewport) {
            if selectedStructure == .conveyor {
                interaction.accumulateConveyorDragCell(current)
            } else {
                interaction.updateDragDraw(at: current)
            }
        }

        selectedTarget = nil

        if selectedStructure == .conveyor {
            let cells = interaction.finishConveyorDragDraw(using: dragDrawPlanner)
            guard !cells.isEmpty else { return }
            runtime.placeConveyorPath(cells.map {
                ConveyorPlacementCell(
                    position: $0.position,
                    inputDirection: $0.inputDirection,
                    outputDirection: $0.outputDirection,
                    isCorner: $0.isCorner
                )
            })
        } else {
            let path = interaction.finishDragDraw(using: dragDrawPlanner)
            guard !path.isEmpty else { return }
            runtime.placeStructurePath(selectedStructure, along: path)
        }

        // Stay in build mode after conveyor/wall drag-draw
        refreshPlacementPreview(viewport: viewport)
    }

    private func applyFlowBrushChanges(_ changes: [FlowBrushChange]) {
        for change in changes {
            guard let entity = runtime.world.entities.selectableEntity(at: change.position),
                  entity.structureType == .conveyor else { continue }
            runtime.configureConveyorIO(
                entityID: entity.id,
                inputDirection: change.newInput,
                outputDirection: change.newOutput
            )
        }
    }

    private func refreshPlacementPreview(viewport: CGSize) {
        guard interaction.isBuildMode else {
            runtime.clearPlacementPreview()
            return
        }
        if let highlighted = runtime.highlightedCell {
            runtime.previewPlacement(structure: selectedStructure, at: highlighted)
            return
        }
        guard let centerCell = pickGrid(
            at: CGPoint(x: viewport.width * 0.5, y: viewport.height * 0.5),
            viewport: viewport
        ) else {
            runtime.clearPlacementPreview()
            return
        }
        runtime.previewPlacement(structure: selectedStructure, at: centerCell)
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

    private func selectedEntityInspectorModel() -> ObjectInspectorViewModel? {
        guard case .entity(let selectedEntityID)? = selectedTarget else { return nil }
        return objectInspectorBuilder.build(entityID: selectedEntityID, in: runtime.world)
    }

    private func selectedOrePatchInspectorModel() -> OrePatchInspectorViewModel? {
        guard case .orePatch(let patchID)? = selectedTarget else { return nil }
        return orePatchInspectorBuilder.build(patchID: patchID, in: runtime.world)
    }

    private var selectedDemolishableEntityID: EntityID? {
        guard case .entity(let entityID)? = selectedTarget,
              let entity = runtime.world.entities.entity(id: entityID),
              entity.category == .structure,
              entity.structureType != .hq else {
            return nil
        }
        return entityID
    }

    private var selectedConveyorEntityID: EntityID? {
        guard case .entity(let entityID)? = selectedTarget,
              runtime.world.entities.entity(id: entityID)?.structureType == .conveyor else {
            return nil
        }
        return entityID
    }

    private func syncSelectedConveyorEditor() {
        guard let selectedConveyorEntityID,
              let conveyor = runtime.world.entities.entity(id: selectedConveyorEntityID) else { return }
        let io = runtime.world.economy.conveyorIOByEntity[selectedConveyorEntityID]
            ?? ConveyorIOConfig.default(for: conveyor.rotation)
        conveyorInputDirection = io.inputDirection
        conveyorOutputDirection = io.outputDirection
    }

    private func requestDemolishSelected() {
        guard let entityID = selectedDemolishableEntityID else { return }
        interaction.requestDemolish(entityID: entityID)
    }

    private func orePatch(at position: GridPosition) -> OrePatch? {
        runtime.world.orePatches.first(where: { $0.position.x == position.x && $0.position.y == position.y })
    }

    private func validateSelection() {
        guard let selectedTarget else { return }
        switch selectedTarget {
        case .entity(let entityID):
            if runtime.world.entities.entity(id: entityID) == nil {
                self.selectedTarget = nil
            }
        case .orePatch(let patchID):
            if !runtime.world.orePatches.contains(where: { $0.id == patchID }) {
                self.selectedTarget = nil
            }
        }
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

    private func inspectorPosition(for model: OrePatchInspectorViewModel, viewport: CGSize) -> CGPoint {
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
    var debugMode: DebugVisualizationMode
    var highlightedCell: GridPosition?
    var highlightedPath: [GridPosition]
    var highlightedAffordableCount: Int
    var highlightedStructure: StructureType?
    var placementResult: PlacementResult
    var onTap: (CGPoint, CGSize) -> Void
    var onPointerMove: (CGPoint, CGSize) -> Void
    var onScrollZoom: (CGFloat, CGPoint, CGSize) -> Void
    var onKeyboardPan: (Float, Float, CGSize) -> Void
    var onKeyAction: (KeyAction, CGSize) -> Void

    func makeNSView(context: Context) -> MTKView {
        let view = ScrollableMTKView(frame: .zero)
        view.onTap = onTap
        view.onPointerMove = onPointerMove
        view.onScrollZoom = onScrollZoom
        view.onKeyboardPan = onKeyboardPan
        view.onKeyAction = onKeyAction
        if let renderer = context.coordinator.renderer {
            renderer.debugMode = debugMode
            renderer.attach(to: view)
        }
        view.window?.makeFirstResponder(view)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        if let interactiveView = nsView as? ScrollableMTKView {
            interactiveView.onTap = onTap
            interactiveView.onPointerMove = onPointerMove
            interactiveView.onScrollZoom = onScrollZoom
            interactiveView.onKeyboardPan = onKeyboardPan
            interactiveView.onKeyAction = onKeyAction
            interactiveView.window?.makeFirstResponder(interactiveView)
        }
        renderer.worldState = world
        renderer.cameraState = cameraState
        renderer.debugMode = debugMode
        renderer.setPlacementHighlight(
            cell: highlightedCell,
            path: highlightedPath,
            affordableCount: highlightedAffordableCount,
            structure: highlightedStructure,
            result: placementResult
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        let renderer = FactoryRenderer()
    }
}

/// Key action events emitted by ScrollableMTKView for game-specific shortcuts.
enum KeyAction {
    case rotateCW          // R
    case rotateCCW         // Shift+R
    case reverse           // F
    case toggleEditBelts   // E
    case togglePlanBelt    // P
    case confirm           // Enter/Return
    case cancel            // Escape
}

private final class ScrollableMTKView: MTKView {
    var onTap: ((CGPoint, CGSize) -> Void)?
    var onPointerMove: ((CGPoint, CGSize) -> Void)?
    var onScrollZoom: ((CGFloat, CGPoint, CGSize) -> Void)?
    var onKeyboardPan: ((Float, Float, CGSize) -> Void)?
    var onKeyAction: ((KeyAction, CGSize) -> Void)?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        window?.acceptsMouseMovedEvents = true
        refreshTrackingArea()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTrackingArea()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let local = convert(event.locationInWindow, from: nil)
        let y = isFlipped ? local.y : (bounds.height - local.y)
        onTap?(CGPoint(x: local.x, y: y), bounds.size)
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let y = isFlipped ? local.y : (bounds.height - local.y)
        onPointerMove?(CGPoint(x: local.x, y: y), bounds.size)
        super.mouseMoved(with: event)
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
        case 15: // R
            if event.modifierFlags.contains(.shift) {
                onKeyAction?(.rotateCCW, bounds.size)
            } else {
                onKeyAction?(.rotateCW, bounds.size)
            }
        case 3: // F
            onKeyAction?(.reverse, bounds.size)
        case 14: // E
            onKeyAction?(.toggleEditBelts, bounds.size)
        case 35: // P
            onKeyAction?(.togglePlanBelt, bounds.size)
        case 36: // Return/Enter
            onKeyAction?(.confirm, bounds.size)
        case 53: // Escape
            onKeyAction?(.cancel, bounds.size)
        default:
            super.keyDown(with: event)
        }
    }

    private func refreshTrackingArea() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }
}
