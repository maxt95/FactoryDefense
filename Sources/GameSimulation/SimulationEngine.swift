import Foundation

public struct WorldSnapshot: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 5

    public var schemaVersion: Int
    public var world: WorldState
    public var queuedCommands: [UInt64: [PlayerCommand]]

    public init(
        schemaVersion: Int = WorldSnapshot.currentSchemaVersion,
        world: WorldState,
        queuedCommands: [UInt64: [PlayerCommand]]
    ) {
        self.schemaVersion = schemaVersion
        self.world = world
        self.queuedCommands = queuedCommands
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case world
        case queuedCommands
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == WorldSnapshot.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported snapshot schema version \(schemaVersion). Expected \(WorldSnapshot.currentSchemaVersion)."
            )
        }

        self.schemaVersion = schemaVersion
        self.world = try container.decode(WorldState.self, forKey: .world)
        self.queuedCommands = try container.decode([UInt64: [PlayerCommand]].self, forKey: .queuedCommands)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(world, forKey: .world)
        try container.encode(queuedCommands, forKey: .queuedCommands)
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
            ProjectileSystem(),
            BottleneckSystem()
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
        if worldState.run.phase == .gameOver {
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
