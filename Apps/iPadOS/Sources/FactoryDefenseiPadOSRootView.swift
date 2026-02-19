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
    private enum SelectionTarget: Equatable {
        case entity(EntityID)
        case orePatch(Int)
    }

    @StateObject private var runtime = GameRuntimeController()
    @State private var buildMenu = BuildMenuViewModel.productionPreset
    @State private var techTree = TechTreeViewModel.productionPreset
    @State private var onboarding = OnboardingGuideViewModel.starter
    @State private var interaction = GameplayInteractionState()
    @StateObject private var placementFeedback = PlacementFeedbackController()
    @State private var overlayLayout = GameplayOverlayLayoutState.defaultLayout(
        viewportSize: CGSize(width: 1280, height: 900)
    )
    @State private var cameraState = WhiteboxCameraState()
    @State private var dragTranslation: CGSize = .zero
    @State private var zoomGestureScale: CGFloat = 1
    @State private var selectedTarget: SelectionTarget?
    @State private var conveyorInputDirection: CardinalDirection = .west
    @State private var conveyorOutputDirection: CardinalDirection = .east

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
                    Spacer()
                    HStack(alignment: .bottom) {
                        ModeIndicatorView(
                            mode: interaction.mode,
                            structureName: interaction.isBuildMode ? buildMenu.selectedEntry()?.title : nil
                        )
                        Spacer()
                        GameClockView(tick: runtime.world.tick)
                    }
                    .padding(16)
                }
                .allowsHitTesting(false)

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
                        ObjectInspectorPopup(
                            model: inspector,
                            onClose: { selectedTarget = nil },
                            onSelectRecipe: { recipeID in
                                runtime.pinRecipe(entityID: inspector.entityID, recipeID: recipeID)
                            }
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
        }
    }

    private var hudModel: HUDViewModel {
        HUDViewModel.build(from: runtime.world)
    }

    private var overlayWindowDefinitions: [GameplayOverlayWindowDefinition] {
        [
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
        case .buildMenu:
            return CGPoint(x: 16, y: 96)
        case .buildingReference:
            return CGPoint(x: 348, y: 96)
        case .tileLegend:
            return CGPoint(x: 1032, y: 96)
        case .techTree:
            return CGPoint(x: 660, y: 96)
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

    private var inspectorPopupWidth: CGFloat { 320 }

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
        let horizontalPadding: CGFloat = 12
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
