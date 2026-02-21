#if canImport(SwiftUI)
import Foundation
import GameSimulation
import SwiftUI

// MARK: - Tutorial Phase

public enum TutorialPhase: String, Sendable {
    case inactive
    case active
    case waitingForAction
    case transitioning
}

// MARK: - Tutorial State Controller

@MainActor
public final class TutorialStateController: ObservableObject {
    @Published public var phase: TutorialPhase = .inactive
    @Published public var currentStepIndex: Int = 0

    public var onPauseRequested: (() -> Void)?
    public var onResumeRequested: (() -> Void)?

    private let sequence: TutorialSequence
    private var structureCountSnapshot: [StructureType: Int] = [:]

    private static let completedKey = "tutorial.completed"
    private static let skippedKey = "tutorial.skipped"

    public init(sequence: TutorialSequence = .defaultTutorial) {
        self.sequence = sequence
    }

    public var currentStep: TutorialStepDefinition? {
        guard phase != .inactive, sequence.steps.indices.contains(currentStepIndex) else {
            return nil
        }
        return sequence.steps[currentStepIndex]
    }

    public var totalSteps: Int {
        sequence.steps.count
    }

    public var isActive: Bool {
        phase != .inactive
    }

    // MARK: - Lifecycle

    public func beginIfNeeded() {
        let completed = UserDefaults.standard.bool(forKey: Self.completedKey)
        let skipped = UserDefaults.standard.bool(forKey: Self.skippedKey)
        guard !completed, !skipped else { return }

        currentStepIndex = 0
        phase = .active
        applySimulationMode()
    }

    public func advanceManually() {
        guard let step = currentStep, step.completionCondition == .tapToContinue else { return }
        advance()
    }

    public func evaluate(
        world: WorldState,
        interactionMode: GameplayInteractionMode,
        buildMenuSelection: String?,
        didCameraInteract: inout Bool
    ) {
        guard let step = currentStep, phase == .active || phase == .waitingForAction else { return }

        switch step.completionCondition {
        case .tapToContinue:
            break

        case .placeStructure(let structureType):
            let currentCount = world.entities.structures(of: structureType).count
            let snapshotCount = structureCountSnapshot[structureType, default: 0]
            if currentCount > snapshotCount {
                advance()
            }

        case .selectBuildEntry(let entryID):
            if buildMenuSelection == entryID, interactionMode == .build {
                advance()
            }

        case .cameraInteraction:
            if didCameraInteract {
                didCameraInteract = false
                advance()
            }

        case .worldPredicate:
            break
        }
    }

    public func skip() {
        UserDefaults.standard.set(true, forKey: Self.skippedKey)
        phase = .inactive
        onResumeRequested?()
    }

    public func reset() {
        UserDefaults.standard.removeObject(forKey: Self.completedKey)
        UserDefaults.standard.removeObject(forKey: Self.skippedKey)
        phase = .inactive
        currentStepIndex = 0
    }

    // MARK: - Dynamic Spotlight Resolution

    public func resolvedSpotlight(for step: TutorialStepDefinition, world: WorldState) -> TutorialSpotlightTarget {
        switch step.id {
        case "hq_overview":
            let basePos = world.board.basePosition
            return .gridRegion(
                origin: GridPosition(x: basePos.x - 1, y: basePos.y - 1),
                width: 3,
                height: 3
            )

        case "ore_patches":
            if let nearest = nearestOrePatch(to: world.board.basePosition, in: world) {
                let board = world.board
                let minX = max(0, nearest.position.x - 1)
                let minY = max(0, nearest.position.y - 1)
                let maxX = min(board.width - 1, nearest.position.x + 1)
                let maxY = min(board.height - 1, nearest.position.y + 1)
                return .gridRegion(
                    origin: GridPosition(x: minX, y: minY),
                    width: max(1, maxX - minX + 1),
                    height: max(1, maxY - minY + 1)
                )
            }
            return step.spotlight

        case "place_miner":
            if let placement = nearestValidMinerPlacement(to: world.board.basePosition, in: world) {
                return .gridPosition(placement)
            }
            return step.spotlight

        default:
            return step.spotlight
        }
    }

    // MARK: - Snapshot

    public func captureWorldSnapshot(world: WorldState) {
        for structureType in StructureType.allCases {
            structureCountSnapshot[structureType] = world.entities.structures(of: structureType).count
        }
    }

    // MARK: - Private

    private func advance() {
        let nextIndex = currentStepIndex + 1
        if nextIndex >= sequence.steps.count {
            UserDefaults.standard.set(true, forKey: Self.completedKey)
            phase = .inactive
            onResumeRequested?()
            return
        }

        phase = .transitioning
        currentStepIndex = nextIndex
        phase = .active
        applySimulationMode()
    }

    private func applySimulationMode() {
        guard let step = currentStep else { return }
        switch step.simulationMode {
        case .paused:
            onPauseRequested?()
        case .running:
            onResumeRequested?()
        }
    }

    private func nearestOrePatch(to position: GridPosition, in world: WorldState) -> OrePatch? {
        world.orePatches.min(by: { lhs, rhs in
            let distA = abs(lhs.position.x - position.x) + abs(lhs.position.y - position.y)
            let distB = abs(rhs.position.x - position.x) + abs(rhs.position.y - position.y)
            return distA < distB
        })
    }

    private func nearestValidMinerPlacement(to position: GridPosition, in world: WorldState) -> GridPosition? {
        let validator = PlacementValidator()
        let sortedPatches = world.orePatches
            .filter { $0.isRevealed && !$0.isExhausted }
            .sorted { lhs, rhs in
                let distA = abs(lhs.position.x - position.x) + abs(lhs.position.y - position.y)
                let distB = abs(rhs.position.x - position.x) + abs(rhs.position.y - position.y)
                if distA != distB {
                    return distA < distB
                }
                return lhs.id < rhs.id
            }

        for patch in sortedPatches {
            let candidates = [
                patch.position.translated(byX: 0, byY: -1),
                patch.position.translated(byX: 1, byY: 0),
                patch.position.translated(byX: 0, byY: 1),
                patch.position.translated(byX: -1, byY: 0)
            ]
            .filter { world.board.contains($0) }
            .sorted { lhs, rhs in
                let distA = abs(lhs.x - position.x) + abs(lhs.y - position.y)
                let distB = abs(rhs.x - position.x) + abs(rhs.y - position.y)
                if distA != distB {
                    return distA < distB
                }
                if lhs.y != rhs.y {
                    return lhs.y < rhs.y
                }
                return lhs.x < rhs.x
            }

            if let placement = candidates.first(where: {
                validator.canPlace(.miner, at: $0, targetPatchID: patch.id, in: world) == .ok
            }) {
                return placement
            }
        }
        return nil
    }
}
#endif
