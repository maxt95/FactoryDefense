#if canImport(SwiftUI)
import Foundation
import GameSimulation

// MARK: - Spotlight Target

public enum TutorialSpotlightTarget: Codable, Hashable, Sendable {
    case gridPosition(GridPosition)
    case gridRegion(origin: GridPosition, width: Int, height: Int)
    case uiElement(anchorKey: String)
    case none
}

// MARK: - Completion Condition

public enum TutorialCompletionCondition: Codable, Hashable, Sendable {
    case tapToContinue
    case placeStructure(StructureType)
    case selectBuildEntry(entryID: String)
    case cameraInteraction
    case worldPredicate(predicateID: String)
}

// MARK: - Simulation Mode

public enum TutorialSimulationMode: String, Codable, Hashable, Sendable {
    case paused
    case running
}

// MARK: - Arrow Direction

public enum TutorialArrowDirection: String, Codable, Hashable, Sendable {
    case up, down, left, right
}

// MARK: - Step Definition

public struct TutorialStepDefinition: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var iconSystemName: String
    public var spotlight: TutorialSpotlightTarget
    public var arrowDirection: TutorialArrowDirection
    public var completionCondition: TutorialCompletionCondition
    public var simulationMode: TutorialSimulationMode
    public var dimOpacity: Double
    public var buttonLabel: String

    public init(
        id: String,
        title: String,
        body: String,
        iconSystemName: String = "info.circle",
        spotlight: TutorialSpotlightTarget = .none,
        arrowDirection: TutorialArrowDirection = .down,
        completionCondition: TutorialCompletionCondition = .tapToContinue,
        simulationMode: TutorialSimulationMode = .paused,
        dimOpacity: Double = 0.65,
        buttonLabel: String = "Next"
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.iconSystemName = iconSystemName
        self.spotlight = spotlight
        self.arrowDirection = arrowDirection
        self.completionCondition = completionCondition
        self.simulationMode = simulationMode
        self.dimOpacity = dimOpacity
        self.buttonLabel = buttonLabel
    }
}

// MARK: - Tutorial Sequence

public struct TutorialSequence: Sendable {
    public var steps: [TutorialStepDefinition]

    public init(steps: [TutorialStepDefinition]) {
        self.steps = steps
    }

    public static let defaultTutorial = TutorialSequence(steps: [
        TutorialStepDefinition(
            id: "welcome",
            title: "Welcome, Commander!",
            body: "Your factory is under threat. Enemies will attack from the east in waves — but you have a grace period to prepare.\n\nBuild production chains, power your machines, and arm your defenses before the first surge arrives.",
            iconSystemName: "shield.checkered",
            spotlight: .none,
            arrowDirection: .down,
            completionCondition: .tapToContinue,
            simulationMode: .paused,
            dimOpacity: 0.70,
            buttonLabel: "Let's Go"
        ),
        TutorialStepDefinition(
            id: "camera_controls",
            title: "Look Around",
            body: "Drag to pan the camera and pinch to zoom in and out. Get a feel for your surroundings — you'll need to scout ore patches and plan your layout.",
            iconSystemName: "hand.draw",
            spotlight: .none,
            arrowDirection: .down,
            completionCondition: .cameraInteraction,
            simulationMode: .paused,
            dimOpacity: 0.30,
            buttonLabel: "Next"
        ),
        TutorialStepDefinition(
            id: "hq_overview",
            title: "Your Headquarters",
            body: "This is your HQ — protect it at all costs. If enemies reach it and destroy it, the run is over.\n\nEnemies spawn from the eastern edge and march toward your base.",
            iconSystemName: "building.2",
            spotlight: .gridRegion(origin: GridPosition(x: 0, y: 0), width: 3, height: 3),
            arrowDirection: .down,
            completionCondition: .tapToContinue,
            simulationMode: .paused,
            dimOpacity: 0.65,
            buttonLabel: "Got It"
        ),
        TutorialStepDefinition(
            id: "ore_patches",
            title: "Ore Patches",
            body: "See those colored deposits? Iron (orange), copper (teal), and coal (dark) are the raw materials your factory needs.\n\nYou'll place miners on these patches to extract ore.",
            iconSystemName: "mountain.2",
            spotlight: .gridPosition(GridPosition(x: 0, y: 0)),
            arrowDirection: .down,
            completionCondition: .tapToContinue,
            simulationMode: .paused,
            dimOpacity: 0.65,
            buttonLabel: "Next"
        ),
        TutorialStepDefinition(
            id: "open_build_menu",
            title: "Open the Build Menu",
            body: "Tap the Build menu and find the Miner under the Production category. Select it to enter build mode.",
            iconSystemName: "hammer",
            spotlight: .uiElement(anchorKey: "buildMenu"),
            arrowDirection: .right,
            completionCondition: .selectBuildEntry(entryID: "miner"),
            simulationMode: .paused,
            dimOpacity: 0.55,
            buttonLabel: "Next"
        ),
        TutorialStepDefinition(
            id: "place_miner",
            title: "Place a Miner",
            body: "Now tap on an ore patch to place your first miner. It will begin extracting resources automatically once powered.",
            iconSystemName: "square.grid.3x3.topleft.filled",
            spotlight: .gridPosition(GridPosition(x: 0, y: 0)),
            arrowDirection: .down,
            completionCondition: .placeStructure(.miner),
            simulationMode: .running,
            dimOpacity: 0.40,
            buttonLabel: "Next"
        ),
        TutorialStepDefinition(
            id: "power_intro",
            title: "Power Up",
            body: "Your miner needs electricity! Open the Build menu and place a Power Plant nearby. Watch the power indicator in the HUD — keep supply above demand.",
            iconSystemName: "bolt.fill",
            spotlight: .uiElement(anchorKey: "hudPower"),
            arrowDirection: .down,
            completionCondition: .placeStructure(.powerPlant),
            simulationMode: .running,
            dimOpacity: 0.40,
            buttonLabel: "Next"
        ),
        TutorialStepDefinition(
            id: "smelting_overview",
            title: "Refine Your Ore",
            body: "Raw ore isn't useful on its own. Build a Smelter to turn ore into metal plates, then connect buildings with Conveyors to move materials automatically.",
            iconSystemName: "flame",
            spotlight: .none,
            arrowDirection: .down,
            completionCondition: .tapToContinue,
            simulationMode: .paused,
            dimOpacity: 0.65,
            buttonLabel: "Next"
        ),
        TutorialStepDefinition(
            id: "production_chain",
            title: "The Production Chain",
            body: "Plates feed into Assemblers to produce gears and circuits. Those components feed Ammo Modules, which supply your turrets.\n\nMiner → Smelter → Assembler → Ammo Module",
            iconSystemName: "arrow.triangle.branch",
            spotlight: .uiElement(anchorKey: "hudResources"),
            arrowDirection: .down,
            completionCondition: .tapToContinue,
            simulationMode: .paused,
            dimOpacity: 0.65,
            buttonLabel: "Next"
        ),
        TutorialStepDefinition(
            id: "defense_overview",
            title: "Build Your Defenses",
            body: "Place Walls to funnel enemies into kill zones, then add Turret Mounts behind them. Turrets consume ammo automatically from nearby Ammo Modules.\n\nA strong defense buys time for your economy to grow.",
            iconSystemName: "shield.lefthalf.filled",
            spotlight: .none,
            arrowDirection: .down,
            completionCondition: .tapToContinue,
            simulationMode: .paused,
            dimOpacity: 0.65,
            buttonLabel: "Next"
        ),
        TutorialStepDefinition(
            id: "ready",
            title: "You're Ready!",
            body: "The grace period timer shows how long until the first wave. Use every second to expand your production and fortify your defenses.\n\nGood luck, Commander!",
            iconSystemName: "flag.checkered",
            spotlight: .uiElement(anchorKey: "graceTimer"),
            arrowDirection: .up,
            completionCondition: .tapToContinue,
            simulationMode: .running,
            dimOpacity: 0.40,
            buttonLabel: "Begin"
        )
    ])
}
#endif
