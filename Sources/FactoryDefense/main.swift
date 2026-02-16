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

private struct FactoryDefenseRootView: View {
    @State private var didStartGame = false

    var body: some View {
        if didStartGame {
            FactoryDefenseGameplayView()
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

private struct FactoryDefenseGameplayView: View {
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

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Factory Defense")
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
                            TuningDashboardPanel(snapshot: .from(world: runtime.world))
                        }
                        .frame(maxWidth: .infinity)
                    }

                    Spacer()
                }
                .padding(16)
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
            return "Out of bounds"
        case .blocksCriticalPath:
            return "Blocks path"
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
    var highlightedCell: GridPosition?
    var placementResult: PlacementResult

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        if let renderer = context.coordinator.renderer {
            renderer.attach(to: view)
        }
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        renderer.worldState = world
        renderer.cameraState = cameraState
        renderer.setPlacementHighlight(cell: highlightedCell, result: placementResult)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        let renderer = FactoryRenderer()
    }
}
