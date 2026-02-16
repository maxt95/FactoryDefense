import MetalKit
import SwiftUI
import GameRendering
import GameSimulation
import GameUI

struct FactoryDefensemacOSRootView: View {
    @State private var buildMenu = BuildMenuViewModel.productionPreset
    @State private var techTree = TechTreeViewModel.productionPreset
    @State private var onboarding = OnboardingGuideViewModel.starter
    @State private var inventory: [String: Int] = [
        "plate_iron": 70,
        "plate_steel": 40,
        "gear": 44,
        "circuit": 34,
        "ammo_light": 180,
        "ammo_heavy": 45,
        "wall_kit": 26,
        "turret_core": 16
    ]

    private let previewWorld = WorldState.bootstrap()

    var body: some View {
        ZStack {
            MetalSurfaceView()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Factory Defense macOS")
                        .font(.headline)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                }

                HStack(alignment: .top, spacing: 10) {
                    BuildMenuPanel(viewModel: buildMenu, inventory: inventory) { entry in
                        buildMenu.select(entryID: entry.id)
                    }
                    .frame(width: 320)

                    VStack(spacing: 10) {
                        TechTreePanel(nodes: techTree.nodes(inventory: inventory))
                        OnboardingPanel(steps: onboarding.steps)
                        TuningDashboardPanel(snapshot: .from(world: previewWorld))
                    }
                    .frame(maxWidth: .infinity)
                }

                Spacer()
            }
            .padding(16)
        }
        .onAppear {
            onboarding.update(from: previewWorld)
        }
    }
}

private struct MetalSurfaceView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        if let renderer = context.coordinator.renderer {
            renderer.attach(to: view)
        }
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        let renderer = FactoryRenderer()
    }
}
