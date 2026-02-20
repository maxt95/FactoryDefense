import MetalKit
import SwiftUI
import UIKit
import GameRendering
import GameSimulation
import GameUI
import GamePlatform

struct FactoryDefenseRootView: View {
    @State private var screen: AppScreen = .mainMenu

    var body: some View {
        switch screen {
        case .mainMenu:
            FactoryDefenseMainMenu(
                title: "Factory Defense",
                onStart: { screen = .difficultySelect }
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
                onRunEnded: { summary in
                    screen = .runSummary(summary)
                },
                onQuit: { screen = .mainMenu }
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
    let onStart: () -> Void
    @State private var cardScale: CGFloat = 0.94
    @State private var cardOpacity: Double = 0
    @State private var cardOffsetY: CGFloat = -8

    var body: some View {
        ZStack {
            MainMenuBackground()

            VStack(spacing: 24) {
                // Title
                VStack(spacing: 8) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(HUDColor.accentTeal)

                    Text(title.uppercased())
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(HUDColor.primaryText)

                    Text("Build. Defend. Survive.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HUDColor.secondaryText)
                }

                // Divider
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                HUDColor.border.opacity(0),
                                HUDColor.accentTeal.opacity(0.4),
                                HUDColor.border.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 180, height: 1)

                // Start button
                MainMenuButton(
                    title: "Start Game",
                    icon: "play.fill",
                    action: onStart
                )
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 38)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(HUDColor.background.opacity(0.92))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        HUDColor.accentTeal.opacity(0.25),
                                        HUDColor.border,
                                        HUDColor.accentTeal.opacity(0.25)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: HUDColor.accentTeal.opacity(0.08), radius: 60, y: 10)
                    .shadow(color: Color.black.opacity(0.6), radius: 40, y: 8)
            }
            .scaleEffect(cardScale)
            .opacity(cardOpacity)
            .offset(y: cardOffsetY)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    cardScale = 1.0
                    cardOpacity = 1.0
                    cardOffsetY = 0
                }
            }
            .padding()
        }
    }
}

// MARK: - Main Menu Background

private struct MainMenuBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { context, size in
                let baseGradient = Gradient(colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.13),
                    Color(red: 0.03, green: 0.05, blue: 0.09)
                ])
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        baseGradient,
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: size.height)
                    )
                )

                let time = timeline.date.timeIntervalSinceReferenceDate
                drawOrb(
                    in: &context, size: size, time: time,
                    cx: 0.25, cy: 0.30, radius: 0.35,
                    color: HUDColor.accentTeal, opacity: 0.06, speed: 0.15
                )
                drawOrb(
                    in: &context, size: size, time: time,
                    cx: 0.75, cy: 0.70, radius: 0.30,
                    color: HUDColor.accentBlue, opacity: 0.04, speed: 0.12
                )
                drawOrb(
                    in: &context, size: size, time: time,
                    cx: 0.50, cy: 0.55, radius: 0.25,
                    color: HUDColor.accentTeal, opacity: 0.03, speed: 0.08
                )
            }
        }
        .ignoresSafeArea()
    }

    private func drawOrb(
        in context: inout GraphicsContext,
        size: CGSize, time: TimeInterval,
        cx: CGFloat, cy: CGFloat, radius: CGFloat,
        color: Color, opacity: CGFloat, speed: CGFloat
    ) {
        let x = (cx + sin(time * speed) * 0.08) * size.width
        let y = (cy + cos(time * speed * 0.7) * 0.06) * size.height
        let r = radius * min(size.width, size.height)

        let gradient = Gradient(stops: [
            .init(color: color.opacity(opacity), location: 0),
            .init(color: color.opacity(0), location: 1)
        ])

        context.fill(
            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(
                gradient,
                center: CGPoint(x: x, y: y),
                startRadius: 0,
                endRadius: r
            )
        )
    }
}

// MARK: - Main Menu Button

private struct MainMenuButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(HUDColor.primaryText)
            .frame(width: 220, height: 48)
            .background(isHovered ? HUDColor.accentTeal.opacity(0.30) : HUDColor.accentTeal.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(
                        isHovered ? HUDColor.accentTeal.opacity(0.6) : HUDColor.accentTeal.opacity(0.35),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: isHovered ? HUDColor.accentTeal.opacity(0.2) : .clear,
                radius: 10, y: 2
            )
            .scaleEffect(isHovered ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

private struct FactoryDefenseGameplayView: View {
    private enum SelectionTarget: Equatable {
        case entity(EntityID)
        case orePatch(Int)
    }

    private static let isTablet = UIDevice.current.userInterfaceIdiom == .pad

    @StateObject private var runtime: GameRuntimeController
    @State private var buildMenu = BuildMenuViewModel.productionPreset
    @State private var techTree = TechTreeViewModel.productionPreset
    @State private var onboarding = OnboardingGuideViewModel.starter
    @State private var interaction = GameplayInteractionState()
    @StateObject private var placementFeedback = PlacementFeedbackController()
    @State private var overlayLayout = GameplayOverlayLayoutState.defaultLayout(
        viewportSize: isTablet ? CGSize(width: 1280, height: 900) : CGSize(width: 1170, height: 860)
    )
    @State private var cameraState = WhiteboxCameraState()
    @State private var dragTranslation: CGSize = .zero
    @State private var zoomGestureScale: CGFloat = 1
    @State private var selectedTarget: SelectionTarget?
    @State private var activeTechTreeResearchCenterID: EntityID? = nil
    @State private var conveyorInputDirection: CardinalDirection = .west
    @State private var conveyorOutputDirection: CardinalDirection = .east
    @State private var didReportRunSummary = false
    @State private var isPaused = false
    @Environment(\.scenePhase) private var scenePhase

    let onRunEnded: (RunSummarySnapshot) -> Void
    let onQuit: () -> Void

    init(
        initialWorld: WorldState,
        onRunEnded: @escaping (RunSummarySnapshot) -> Void,
        onQuit: @escaping () -> Void
    ) {
        _runtime = StateObject(wrappedValue: GameRuntimeController(initialWorld: initialWorld))
        self.onRunEnded = onRunEnded
        self.onQuit = onQuit
    }

    private static let keyboardPanStep: Float = 56
    private let picker = WhiteboxPicker()
    private let objectInspectorBuilder = ObjectInspectorBuilder()
    private let orePatchInspectorBuilder = OrePatchInspectorBuilder()
    private let dragDrawPlanner = GameplayDragDrawPlanner()

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
                    highlightedCell: runtime.highlightedCell,
                    highlightedPath: interaction.dragPreviewPath,
                    highlightedAffordableCount: dragPreviewAffordableCount,
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
                            let anchor = CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
                            zoomCamera(scale: Float(1 / delta), around: anchor, viewport: proxy.size)
                            zoomGestureScale = scale
                        }
                        .onEnded { _ in
                            zoomGestureScale = 1
                        }
                )

                // Fixed HUD layer
                VStack(spacing: 0) {
                    FixedHUDBar(
                        snapshot: hudModel.snapshot,
                        warning: hudModel.warning
                    )
                    .allowsHitTesting(false)
                    Spacer()
                    HStack(alignment: .bottom) {
                        ModeIndicatorView(
                            mode: interaction.mode,
                            structureName: interaction.isBuildMode ? buildMenu.selectedEntry()?.title : nil
                        )
                        .allowsHitTesting(false)
                        Spacer()
                        PauseHUDButton { pauseGame() }
                        GameClockView(tick: runtime.world.tick)
                            .allowsHitTesting(false)
                    }
                    .padding(16)
                }

                if interaction.mode == .interact {
                    if let quickEditID = interaction.quickEditTarget,
                       let entity = runtime.world.entities.entity(id: quickEditID),
                       entity.structureType == .conveyor {
                        let widgetPos = quickEditWidgetPosition(for: entity, viewport: proxy.size)
                        ConveyorQuickEditWidget(
                            entityID: quickEditID,
                            onRotateCW: { rotateConveyor(entityID: quickEditID, clockwise: true) },
                            onRotateCCW: { rotateConveyor(entityID: quickEditID, clockwise: false) },
                            onReverse: { reverseSingleConveyor(entityID: quickEditID) },
                            onDismiss: { interaction.quickEditTarget = nil }
                        )
                        .position(widgetPos)
                    } else if let inspector = selectedEntityInspectorModel() {
                        let isResearchCenter = runtime.world.entities.entity(id: inspector.entityID)?.structureType == .researchCenter
                        ObjectInspectorPopup(
                            model: inspector,
                            onClose: { selectedTarget = nil },
                            onSelectRecipe: { recipeID in
                                runtime.pinRecipe(entityID: inspector.entityID, recipeID: recipeID)
                            },
                            actionLabel: isResearchCenter ? "Open Research" : nil,
                            onAction: isResearchCenter ? {
                                let entityID = inspector.entityID
                                selectedTarget = nil
                                activeTechTreeResearchCenterID = entityID
                                runtime.stop()
                            } : nil
                        )
                        .frame(width: inspectorPopupWidth)
                        .position(inspectorPosition(for: inspector, viewport: proxy.size))
                    } else if let inspector = selectedOrePatchInspectorModel() {
                        OrePatchInspectorPopup(
                            model: inspector,
                            onClose: { selectedTarget = nil }
                        )
                        .frame(width: inspectorPopupWidth)
                        .position(inspectorPosition(for: inspector, viewport: proxy.size))
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

                // Full-screen tech tree
                if let rcID = activeTechTreeResearchCenterID {
                    TechTreeFullScreenView(
                        techTree: $techTree,
                        researchCenterEntityID: rcID,
                        researchCenterBuffer: runtime.world.economy.structureInputBuffers[rcID, default: [:]],
                        onClose: { closeTechTree() },
                        onUnlock: { nodeID in
                            handleTechUnlock(nodeID: nodeID, researchCenterID: rcID)
                        }
                    )
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: activeTechTreeResearchCenterID != nil)
                }

                // Pause menu overlay
                if isPaused {
                    PauseMenuOverlay(
                        onResume: { resumeGame() },
                        onSettings: { },
                        onQuit: {
                            isPaused = false
                            onQuit()
                        }
                    )
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: isPaused)
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
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active, !isPaused {
                    pauseGame()
                }
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
        }
    }

    private var hudModel: HUDViewModel {
        HUDViewModel.build(from: runtime.world)
    }

    private var overlayWindowDefinitions: [GameplayOverlayWindowDefinition] {
        [
            GameplayOverlayWindowDefinition(id: .buildMenu, title: "Build", preferredWidth: 290, preferredHeight: 520),
            GameplayOverlayWindowDefinition(id: .buildingReference, title: "Buildings", preferredWidth: 290, preferredHeight: 520),
            GameplayOverlayWindowDefinition(id: .tileLegend, title: "Tile Legend", preferredWidth: 280, preferredHeight: 340),
            GameplayOverlayWindowDefinition(id: .onboarding, title: "Objectives", preferredWidth: 360, preferredHeight: 340),
            GameplayOverlayWindowDefinition(id: .tuningDashboard, title: "Telemetry", preferredWidth: 220, preferredHeight: 260)
        ]
    }

    @ViewBuilder
    private func overlayContent(for windowID: GameplayOverlayWindowID) -> some View {
        switch windowID {
        case .buildMenu:
            BuildMenuPanel(viewModel: buildMenu, inventory: inventory) { entry in
                interaction.selectBuildEntry(entry.id, in: &buildMenu)
            }

        case .buildingReference:
            BuildingReferencePanel(world: runtime.world)

        case .tileLegend:
            TileLegendPanel()

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
        case .buildMenu:
            return CGPoint(x: 16, y: 96)
        case .buildingReference:
            return CGPoint(x: 348, y: 96)
        case .tileLegend:
            return CGPoint(x: 1032, y: 96)
        case .onboarding:
            return CGPoint(x: 660, y: 408)
        case .tuningDashboard:
            return CGPoint(x: 660, y: 720)
        }
    }

    private func handleTap(at location: CGPoint, viewport: CGSize) {
        guard let position = pickGrid(at: location, viewport: viewport) else {
            runtime.clearPlacementPreview()
            selectedTarget = nil
            interaction.quickEditTarget = nil
            return
        }

        switch interaction.mode {
        case .interact:
            runtime.clearPlacementPreview()
            if let tappedEntity = runtime.world.entities.selectableEntity(at: position) {
                if tappedEntity.structureType == .conveyor {
                    if interaction.quickEditTarget == tappedEntity.id {
                        interaction.quickEditTarget = nil
                    } else {
                        interaction.quickEditTarget = tappedEntity.id
                        selectedTarget = nil
                    }
                    return
                }
                interaction.quickEditTarget = nil
                selectedTarget = selectionTarget(at: position)
            } else if let patch = orePatch(at: position) {
                interaction.quickEditTarget = nil
                if selectedTarget == .orePatch(patch.id) {
                    selectedTarget = nil
                } else {
                    selectedTarget = .orePatch(patch.id)
                }
            } else {
                selectedTarget = nil
                interaction.quickEditTarget = nil
            }
        case .build:
            selectedTarget = nil
            interaction.quickEditTarget = nil
            if dragDrawPlanner.supportsDragDraw(for: selectedStructure) {
                runtime.previewPlacement(structure: selectedStructure, at: position)
                return
            }
            runtime.placeStructure(selectedStructure, at: position)
            if interaction.completePlacementIfSuccessful(runtime.placementResult) {
                runtime.clearPlacementPreview()
            }
        case .editBelts:
            break
        case .planBelt:
            if interaction.beltPlanner.startPin == nil {
                interaction.beltPlanner.setStart(position)
            } else {
                interaction.beltPlanner.setEnd(position)
            }
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
        previewPlacement(at: value.location, viewport: viewport)
    }

    private func handleDragEnded(_ value: DragGesture.Value, viewport: CGSize) {
        defer { dragTranslation = .zero }

        // Handle flow brush stroke completion
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

    private func pauseGame() {
        isPaused = true
        runtime.stop()
    }

    private func resumeGame() {
        isPaused = false
        runtime.start()
    }

    private func closeTechTree() {
        activeTechTreeResearchCenterID = nil
        runtime.start()
    }

    private func handleTechUnlock(nodeID: String, researchCenterID: EntityID) -> Bool {
        guard let node = techTree.nodeDefs.first(where: { $0.id == nodeID }) else { return false }
        guard !techTree.unlockedNodeIDs.contains(nodeID) else { return true }
        guard node.prerequisites.allSatisfy({ techTree.unlockedNodeIDs.contains($0) }) else { return false }

        if nodeID.hasPrefix("geology_survey_") {
            let buffer = runtime.world.economy.structureInputBuffers[researchCenterID, default: [:]]
            guard node.costs.allSatisfy({ buffer[$0.itemID, default: 0] >= $0.quantity }) else { return false }
            runtime.startOreSurvey(nodeID: nodeID, researchCenterID: researchCenterID)
            techTree.unlockedNodeIDs.insert(nodeID)
            return true
        }

        guard runtime.deductFromInputBuffer(entityID: researchCenterID, costs: node.costs) else { return false }
        techTree.unlockedNodeIDs.insert(nodeID)
        return true
    }

    private func pickGrid(at location: CGPoint, viewport: CGSize) -> GridPosition? {
        picker.gridPosition(
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

    private func quickEditWidgetPosition(for entity: Entity, viewport: CGSize) -> CGPoint {
        let anchor = picker.screenPosition(
            for: entity.position,
            viewport: viewport,
            camera: cameraState,
            board: runtime.world.board
        )
        let tileHeight = CGFloat(max(0.001, cameraState.zoom)) * 22
        let lift = tileHeight * 2.5
        return CGPoint(x: anchor.x, y: max(50, anchor.y - lift))
    }

    private func selectionTarget(at position: GridPosition) -> SelectionTarget? {
        let tappedEntities = runtime.world.entities.selectableEntities(at: position)
        if !tappedEntities.isEmpty {
            let entityIDs = tappedEntities.map(\.id)
            if case .entity(let selectedEntityID)? = selectedTarget,
               let selectedIndex = entityIDs.firstIndex(of: selectedEntityID) {
                if entityIDs.count == 1 {
                    return nil
                }
                let nextIndex = (selectedIndex + 1) % entityIDs.count
                return .entity(entityIDs[nextIndex])
            }
            return .entity(entityIDs[0])
        }

        guard let patch = orePatch(at: position) else { return nil }
        if selectedTarget == .orePatch(patch.id) {
            return nil
        }
        return .orePatch(patch.id)
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

    private var inspectorPopupWidth: CGFloat { Self.isTablet ? 320 : 300 }

    private func estimatedInspectorHeight(for model: ObjectInspectorViewModel) -> CGFloat {
        let rowCount = model.sections.reduce(0) { $0 + $1.rows.count }
        let sectionCount = model.sections.count
        return min(460, max(180, 74 + CGFloat(rowCount) * 22 + CGFloat(sectionCount) * 26))
    }

    private func estimatedInspectorHeight(for model: OrePatchInspectorViewModel) -> CGFloat {
        let rowCount = model.sections.reduce(0) { $0 + $1.rows.count }
        let sectionCount = model.sections.count
        return min(340, max(160, 70 + CGFloat(rowCount) * 22 + CGFloat(sectionCount) * 24))
    }

    private func inspectorAnchorX(_ anchorX: CGFloat, popupWidth: CGFloat, viewport: CGSize) -> CGFloat {
        let halfWidth = popupWidth * 0.5
        let horizontalPadding: CGFloat = Self.isTablet ? 12 : 10
        return min(max(halfWidth + horizontalPadding, anchorX), viewport.width - (halfWidth + horizontalPadding))
    }

    private func inspectorAnchorY(
        anchorY: CGFloat,
        anchorHeightTiles: Int,
        popupHeight: CGFloat,
        viewport: CGSize
    ) -> CGFloat {
        let tileHeight = CGFloat(max(0.001, cameraState.zoom)) * 22
        let objectTopY = anchorY - tileHeight * (CGFloat(max(1, anchorHeightTiles)) + 0.35)
        let clearance = max(14, tileHeight * 0.7)
        let halfHeight = popupHeight * 0.5
        let unclampedY = objectTopY - clearance - halfHeight
        let bottomPadding: CGFloat = 8
        let maxY = viewport.height - halfHeight - bottomPadding
        return min(unclampedY, maxY)
    }

    private func inspectorPosition(for model: ObjectInspectorViewModel, viewport: CGSize) -> CGPoint {
        let anchor = picker.screenPosition(
            for: model.anchorPosition,
            viewport: viewport,
            camera: cameraState,
            board: runtime.world.board
        )
        let popupWidth = inspectorPopupWidth
        let popupHeight = estimatedInspectorHeight(for: model)
        return CGPoint(
            x: inspectorAnchorX(anchor.x, popupWidth: popupWidth, viewport: viewport),
            y: inspectorAnchorY(
                anchorY: anchor.y,
                anchorHeightTiles: model.anchorHeightTiles,
                popupHeight: popupHeight,
                viewport: viewport
            )
        )
    }

    private func inspectorPosition(for model: OrePatchInspectorViewModel, viewport: CGSize) -> CGPoint {
        let anchor = picker.screenPosition(
            for: model.anchorPosition,
            viewport: viewport,
            camera: cameraState,
            board: runtime.world.board
        )
        let popupWidth = inspectorPopupWidth
        let popupHeight = estimatedInspectorHeight(for: model)
        return CGPoint(
            x: inspectorAnchorX(anchor.x, popupWidth: popupWidth, viewport: viewport),
            y: inspectorAnchorY(
                anchorY: anchor.y,
                anchorHeightTiles: model.anchorHeightTiles,
                popupHeight: popupHeight,
                viewport: viewport
            )
        )
    }
}

private struct FactoryDefenseDifficultySelect: View {
    let onSelectDifficulty: (Difficulty) -> Void
    let onBack: () -> Void
    @State private var cardScale: CGFloat = 0.94
    @State private var cardOpacity: Double = 0
    @State private var cardOffsetY: CGFloat = -8

    var body: some View {
        ZStack {
            MainMenuBackground()

            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(HUDColor.accentTeal)

                    Text("SELECT DIFFICULTY")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(HUDColor.primaryText)
                }

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                HUDColor.border.opacity(0),
                                HUDColor.accentTeal.opacity(0.4),
                                HUDColor.border.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 180, height: 1)

                VStack(spacing: 10) {
                    DifficultyOptionButton(
                        name: "Easy",
                        subtitle: "Slower waves, forgiving economy",
                        accent: HUDColor.accentGreen,
                        action: { onSelectDifficulty(.easy) }
                    )
                    DifficultyOptionButton(
                        name: "Normal",
                        subtitle: "Balanced challenge",
                        accent: HUDColor.accentTeal,
                        action: { onSelectDifficulty(.normal) }
                    )
                    DifficultyOptionButton(
                        name: "Hard",
                        subtitle: "Relentless waves, tight resources",
                        accent: HUDColor.accentRed,
                        action: { onSelectDifficulty(.hard) }
                    )
                }

                MainMenuButton(
                    title: "Back",
                    icon: "chevron.left",
                    action: onBack
                )
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(HUDColor.background.opacity(0.92))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        HUDColor.accentTeal.opacity(0.25),
                                        HUDColor.border,
                                        HUDColor.accentTeal.opacity(0.25)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: HUDColor.accentTeal.opacity(0.08), radius: 60, y: 10)
                    .shadow(color: Color.black.opacity(0.6), radius: 40, y: 8)
            }
            .scaleEffect(cardScale)
            .opacity(cardOpacity)
            .offset(y: cardOffsetY)
            .onAppear {
                withAnimation(.easeOut(duration: 0.45)) {
                    cardScale = 1.0
                    cardOpacity = 1.0
                    cardOffsetY = 0
                }
            }
            .padding()
        }
    }
}

private struct DifficultyOptionButton: View {
    let name: String
    let subtitle: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(HUDColor.primaryText)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HUDColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 220, height: 64)
            .background(accent.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(accent.opacity(0.30), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 10) {
                    summaryRow("Waves survived", "\(summary.wavesSurvived)")
                    summaryRow("Run duration", formattedDuration(summary.runDurationSeconds))
                    summaryRow("Enemies destroyed", "\(summary.enemiesDestroyed)")
                    summaryRow("Structures built", "\(summary.structuresBuilt)")
                    summaryRow("Ammo spent", "\(summary.ammoSpent)")
                }
                .frame(maxWidth: 320)

                VStack(spacing: 10) {
                    MainMenuButton(
                        title: "New Run",
                        icon: "arrow.counterclockwise",
                        action: onNewRun
                    )
                    MainMenuButton(
                        title: "Main Menu",
                        icon: "house.fill",
                        action: onMainMenu
                    )
                }
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding()
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

private struct MetalSurfaceView: UIViewRepresentable {
    var world: WorldState
    var cameraState: WhiteboxCameraState
    var highlightedCell: GridPosition?
    var highlightedPath: [GridPosition]
    var highlightedAffordableCount: Int
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
