import Foundation
import GameSimulation

public enum InputDevice: String, Sendable {
    case touch
    case mouse
    case keyboard
    case gamepad
}

public enum InputGesture: Sendable {
    case tapGrid(position: GridPosition)
    case dragPan(deltaX: Float, deltaY: Float)
    case pinch(scale: Float)
    case placeStructure(type: StructureType, position: GridPosition)
    case placeConveyor(position: GridPosition, direction: CardinalDirection)
    case configureConveyorIO(entityID: EntityID, inputDirection: CardinalDirection, outputDirection: CardinalDirection)
    case rotateBuilding(entityID: EntityID)
    case rotateBuildSelection
    case removeStructure(entityID: EntityID)
    case pinRecipe(entityID: EntityID, recipeID: String)
    case cancelBuildMode
    case confirmDemolish
    case dragDrawPath(points: [GridPosition], structure: StructureType)
    case triggerWave
}

public struct InputEvent: Sendable {
    public var timestamp: TimeInterval
    public var device: InputDevice
    public var gesture: InputGesture

    public init(timestamp: TimeInterval, device: InputDevice, gesture: InputGesture) {
        self.timestamp = timestamp
        self.device = device
        self.gesture = gesture
    }
}

public protocol InputMapper {
    func map(event: InputEvent, tick: UInt64, actor: PlayerID) -> PlayerCommand?
}

public struct DefaultInputMapper: InputMapper {
    public var defaultStructureOnTap: StructureType?

    public init(defaultStructureOnTap: StructureType? = nil) {
        self.defaultStructureOnTap = defaultStructureOnTap
    }

    public func map(event: InputEvent, tick: UInt64, actor: PlayerID) -> PlayerCommand? {
        switch event.gesture {
        case .tapGrid(let position):
            guard let structure = defaultStructureOnTap else { return nil }
            return PlayerCommand(
                tick: tick,
                actor: actor,
                payload: .placeStructure(BuildRequest(structure: structure, position: position))
            )
        case .placeStructure(let type, let position):
            return PlayerCommand(
                tick: tick,
                actor: actor,
                payload: .placeStructure(BuildRequest(structure: type, position: position))
            )
        case .placeConveyor(let position, let direction):
            return PlayerCommand(
                tick: tick,
                actor: actor,
                payload: .placeConveyor(position: position, direction: direction)
            )
        case .configureConveyorIO(let entityID, let inputDirection, let outputDirection):
            return PlayerCommand(
                tick: tick,
                actor: actor,
                payload: .configureConveyorIO(
                    entityID: entityID,
                    inputDirection: inputDirection,
                    outputDirection: outputDirection
                )
            )
        case .rotateBuilding(let entityID):
            return PlayerCommand(
                tick: tick,
                actor: actor,
                payload: .rotateBuilding(entityID: entityID)
            )
        case .removeStructure(let entityID):
            return PlayerCommand(
                tick: tick,
                actor: actor,
                payload: .removeStructure(entityID: entityID)
            )
        case .pinRecipe(let entityID, let recipeID):
            return PlayerCommand(
                tick: tick,
                actor: actor,
                payload: .pinRecipe(entityID: entityID, recipeID: recipeID)
            )
        case .triggerWave:
            return PlayerCommand(tick: tick, actor: actor, payload: .triggerWave)
        case .dragDrawPath(let points, let structure):
            guard let first = points.first else { return nil }
            return PlayerCommand(
                tick: tick,
                actor: actor,
                payload: .placeStructure(BuildRequest(structure: structure, position: first))
            )
        case .dragPan, .pinch, .rotateBuildSelection, .cancelBuildMode, .confirmDemolish:
            return nil
        }
    }
}
