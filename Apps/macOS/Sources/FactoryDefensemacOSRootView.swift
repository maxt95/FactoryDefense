import AppKit
import MetalKit
import SwiftUI
import GameRendering
import GameSimulation
import GameUI

struct FactoryDefensemacOSRootView: View {
    @State private var didStartGame = false

    var body: some View {
        if didStartGame {
            FactoryDefensemacOSGameplayView()
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

private struct FactoryDefensemacOSGameplayView: View {
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
