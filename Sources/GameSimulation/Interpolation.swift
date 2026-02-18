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
        let p = Double(previous.hqHealth)
        let c = Double(current.hqHealth)
        return p + ((c - p) * alpha)
    }

    public var blendedCurrency: Double {
        let p = Double(previous.economy.currency)
        let c = Double(current.economy.currency)
        return p + ((c - p) * alpha)
    }

    public var blendedPlayerPosition: SIMD3<Float> {
        let p = previous.player.worldPosition
        let c = current.player.worldPosition
        let a = Float(alpha)
        return p + (c - p) * a
    }

    public var blendedPlayerFacing: Float {
        let p = previous.player.facingRadians
        let c = current.player.facingRadians
        return lerpAngle(from: p, to: c, t: Float(alpha))
    }

    public var blendedPlayerPitch: Float {
        let p = previous.player.pitchRadians
        let c = current.player.pitchRadians
        let a = Float(alpha)
        return p + (c - p) * a
    }
}

private func lerpAngle(from a: Float, to b: Float, t: Float) -> Float {
    var diff = b - a
    while diff > .pi { diff -= 2 * .pi }
    while diff < -.pi { diff += 2 * .pi }
    return a + diff * t
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
