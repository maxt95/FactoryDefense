import Foundation

public struct WorldSnapshot: Codable, Hashable, Sendable {
    public var world: WorldState
    public var queuedCommands: [UInt64: [PlayerCommand]]

    public init(world: WorldState, queuedCommands: [UInt64: [PlayerCommand]]) {
        self.world = world
        self.queuedCommands = queuedCommands
    }
}

public final class SimulationEngine {
    public var worldState: WorldState
    public let tickRate: UInt64
    public let interpolationBridge: SimulationInterpolationBridge

    private var queuedCommands: [UInt64: [PlayerCommand]]
    private let systems: [any SimulationSystem]

    public init(
        worldState: WorldState = .bootstrap(),
        tickRate: UInt64 = 20,
        systems: [any SimulationSystem] = [
            CommandSystem(),
            EconomySystem(),
            WaveSystem(),
            EnemyMovementSystem(),
            CombatSystem(),
            ProjectileSystem()
        ]
    ) {
        self.worldState = worldState
        self.tickRate = tickRate
        self.interpolationBridge = SimulationInterpolationBridge(initial: worldState)
        self.queuedCommands = [:]
        self.systems = systems
    }

    public func enqueue(_ command: PlayerCommand) {
        queuedCommands[command.tick, default: []].append(command)
    }

    @discardableResult
    public func step() -> [SimEvent] {
        let previousState = worldState
        if worldState.run.gameOver || worldState.run.extracted {
            worldState.tick += 1
            interpolationBridge.record(previous: previousState, current: worldState)
            return []
        }

        let tick = worldState.tick
        var commands = queuedCommands.removeValue(forKey: tick) ?? []
        commands.sort {
            if $0.actor != $1.actor {
                return $0.actor < $1.actor
            }
            return $0.deterministicSortToken < $1.deterministicSortToken
        }

        var emittedEvents: [SimEvent] = []
        let context = SystemContext(
            tickDurationSeconds: 1.0 / Double(tickRate),
            commands: commands,
            emitEvent: { emittedEvents.append($0) }
        )

        for system in systems {
            system.update(state: &worldState, context: context)
        }

        worldState.tick += 1
        interpolationBridge.record(previous: previousState, current: worldState)
        return emittedEvents
    }

    @discardableResult
    public func run(ticks: Int) -> [SimEvent] {
        var allEvents: [SimEvent] = []
        allEvents.reserveCapacity(ticks)
        for _ in 0..<ticks {
            allEvents += step()
        }
        return allEvents
    }

    public func makeSnapshot() -> WorldSnapshot {
        WorldSnapshot(world: worldState, queuedCommands: queuedCommands)
    }

    public func load(snapshot: WorldSnapshot) {
        worldState = snapshot.world
        queuedCommands = snapshot.queuedCommands
        interpolationBridge.record(previous: snapshot.world, current: snapshot.world)
    }

    public func interpolatedFrame(alpha: Double) -> InterpolatedWorldFrame {
        interpolationBridge.frame(alpha: alpha)
    }
}
