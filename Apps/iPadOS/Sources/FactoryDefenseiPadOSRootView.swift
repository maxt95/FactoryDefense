import MetalKit
import SwiftUI
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
    @State private var cameraState = WhiteboxCameraState()
    @State private var dragTranslation: CGSize = .zero
    @State private var zoomGestureScale: CGFloat = 1

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
                    placementResult: runtime.placementResult
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
                            cameraState.panBy(deltaX: Float(deltaX), deltaY: Float(deltaY))
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
                            cameraState.zoomBy(scale: Float(delta))
                            zoomGestureScale = scale
                        }
                        .onEnded { _ in
                            zoomGestureScale = 1
                        }
                )

                VStack(alignment: .leading, spacing: 10) {
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

                        Spacer()

                        Button("Wave") { runtime.triggerWave() }
                            .buttonStyle(.borderedProminent)
                        Button("Extract") { runtime.extract() }
                            .buttonStyle(.bordered)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        BuildMenuPanel(viewModel: buildMenu, inventory: inventory) { entry in
                            buildMenu.select(entryID: entry.id)
                        }
                        .frame(width: 320)

                        VStack(spacing: 10) {
                            TechTreePanel(nodes: techTree.nodes(inventory: inventory))
                            OnboardingPanel(steps: onboarding.steps)
                        }
                    }

                    TuningDashboardPanel(snapshot: .from(world: runtime.world))
                }
                .padding()
            }
            .onAppear {
                runtime.start()
                if buildMenu.selectedEntryID == nil, let first = buildMenu.entries.first {
                    buildMenu.select(entryID: first.id)
                }
                onboarding.update(from: runtime.world)
            }
            .onDisappear {
                runtime.stop()
            }
            .onChange(of: runtime.world.tick) { _, _ in
                onboarding.update(from: runtime.world)
            }
            .onChange(of: buildMenu.selectedEntryID) { _, _ in
                if let highlighted = runtime.highlightedCell {
                    runtime.previewPlacement(structure: selectedStructure, at: highlighted)
                }
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
            return "Out"
        case .blocksCriticalPath:
            return "Blocks"
        case .restrictedZone:
            return "Restricted"
        }
    }

    private func handleTap(at location: CGPoint, viewport: CGSize) {
        guard let position = pickGrid(at: location, viewport: viewport) else {
            runtime.clearPlacementPreview()
            return
        }
        runtime.placeStructure(selectedStructure, at: position)
    }

    private func previewPlacement(at location: CGPoint, viewport: CGSize) {
        guard let position = pickGrid(at: location, viewport: viewport) else {
            runtime.clearPlacementPreview()
            return
        }
        runtime.previewPlacement(structure: selectedStructure, at: position)
    }

    private func pickGrid(at location: CGPoint, viewport: CGSize) -> GridPosition? {
        WhiteboxPicker().gridPosition(
            at: location,
            viewport: viewport,
            board: runtime.world.board,
            camera: cameraState
        )
    }
}

private struct MetalSurfaceView: UIViewRepresentable {
    var world: WorldState
    var cameraState: WhiteboxCameraState
    var highlightedCell: GridPosition?
    var highlightedStructure: StructureType?
    var placementResult: PlacementResult

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        if let renderer = context.coordinator.renderer {
            renderer.attach(to: view)
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
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
