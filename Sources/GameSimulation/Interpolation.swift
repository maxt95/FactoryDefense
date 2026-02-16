import Foundation

public struct InterpolatedWorldFrame: Sendable {
    public var previous: WorldState
    public var current: WorldState
    public var alpha: Double

    public init(previous: WorldState, current: WorldState, alpha: Double) {
        self.previous = previous
        self.current = current
        self.alpha = min(1, max(0, alpha))
    }

    public var blendedBaseIntegrity: Double {
        let p = Double(previous.run.baseIntegrity)
        let c = Double(current.run.baseIntegrity)
        return p + ((c - p) * alpha)
    }

    public var blendedCurrency: Double {
        let p = Double(previous.economy.currency)
        let c = Double(current.economy.currency)
        return p + ((c - p) * alpha)
    }
}

public final class SimulationInterpolationBridge {
    private var previous: WorldState
    private var current: WorldState

    public init(initial: WorldState) {
        self.previous = initial
        self.current = initial
    }

    public func record(previous: WorldState, current: WorldState) {
        self.previous = previous
        self.current = current
    }

    public func frame(alpha: Double) -> InterpolatedWorldFrame {
        InterpolatedWorldFrame(previous: previous, current: current, alpha: alpha)
    }
}
