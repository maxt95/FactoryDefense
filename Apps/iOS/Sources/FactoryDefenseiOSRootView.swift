import MetalKit
import SwiftUI
import GameRendering
import GameSimulation
import GameUI

struct FactoryDefenseiOSRootView: View {
    @State private var didStartGame = false

    var body: some View {
        if didStartGame {
            FactoryDefenseiOSGameplayView()
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
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Button("Start", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(34)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding()
        }
    }
}

private struct FactoryDefenseiOSGameplayView: View {
    @State private var buildMenu = BuildMenuViewModel.productionPreset
    @State private var techTree = TechTreeViewModel.productionPreset
    @State private var onboarding = OnboardingGuideViewModel.starter
    @State private var inventory: [String: Int] = [
        "plate_iron": 40,
        "plate_steel": 20,
        "gear": 24,
        "circuit": 20,
        "ammo_light": 80,
        "ammo_heavy": 22,
        "wall_kit": 12,
        "turret_core": 8
    ]

    private let previewWorld = WorldState.bootstrap()

    var body: some View {
        ZStack {
            MetalSurfaceView()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Factory Defense")
                        .font(.headline)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        BuildMenuPanel(viewModel: buildMenu, inventory: inventory) { entry in
                            buildMenu.select(entryID: entry.id)
                        }
                        .frame(width: 290)

                        TechTreePanel(nodes: techTree.nodes(inventory: inventory))
                            .frame(width: 340)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    OnboardingPanel(steps: onboarding.steps)
                        .frame(maxWidth: .infinity)
                    TuningDashboardPanel(snapshot: .from(world: previewWorld))
                        .frame(width: 170)
                }
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
