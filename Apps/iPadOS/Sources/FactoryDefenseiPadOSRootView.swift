import MetalKit
import SwiftUI
import GameRendering
import GameSimulation
import GameUI

struct FactoryDefenseiPadOSRootView: View {
    @State private var buildMenu = BuildMenuViewModel.productionPreset
    @State private var techTree = TechTreeViewModel.productionPreset
    @State private var onboarding = OnboardingGuideViewModel.starter
    @State private var inventory: [String: Int] = [
        "plate_iron": 50,
        "plate_steel": 28,
        "gear": 30,
        "circuit": 22,
        "ammo_light": 120,
        "ammo_heavy": 30,
        "wall_kit": 18,
        "turret_core": 10
    ]

    private let previewWorld = WorldState.bootstrap()

    var body: some View {
        ZStack {
            MetalSurfaceView()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Factory Defense iPadOS")
                        .font(.headline)
                        .padding(10)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                    }
                }

                TuningDashboardPanel(snapshot: .from(world: previewWorld))
            }
            .padding()
        }
        .onAppear {
            onboarding.update(from: previewWorld)
        }
    }
}

private struct MetalSurfaceView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        if let renderer = context.coordinator.renderer {
            renderer.attach(to: view)
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        let renderer = FactoryRenderer()
    }
}
