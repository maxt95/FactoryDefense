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
    case triggerWave
    case extract
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
        case .triggerWave:
            return PlayerCommand(tick: tick, actor: actor, payload: .triggerWave)
        case .extract:
            return PlayerCommand(tick: tick, actor: actor, payload: .extract)
        case .dragPan, .pinch:
            return nil
        }
    }
}
