import Foundation
import GameSimulation

public struct FrameTelemetrySample: Codable, Hashable, Sendable {
    public var timestamp: Date
    public var frameIndex: UInt64
    public var cpuFrameMS: Double
    public var gpuFrameMS: Double?

    public init(timestamp: Date, frameIndex: UInt64, cpuFrameMS: Double, gpuFrameMS: Double?) {
        self.timestamp = timestamp
        self.frameIndex = frameIndex
        self.cpuFrameMS = cpuFrameMS
        self.gpuFrameMS = gpuFrameMS
    }
}

public struct SimulationTelemetrySample: Codable, Hashable, Sendable {
    public var timestamp: Date
    public var tick: UInt64
    public var baseIntegrity: Int
    public var enemyCount: Int
    public var projectileCount: Int
    public var currency: Int

    public init(timestamp: Date, tick: UInt64, baseIntegrity: Int, enemyCount: Int, projectileCount: Int, currency: Int) {
        self.timestamp = timestamp
        self.tick = tick
        self.baseIntegrity = baseIntegrity
        self.enemyCount = enemyCount
        self.projectileCount = projectileCount
        self.currency = currency
    }
}

public protocol TelemetrySink {
    func writeFrameSample(_ sample: FrameTelemetrySample) throws
    func writeSimulationSample(_ sample: SimulationTelemetrySample) throws
}

public final class JSONLinesTelemetrySink: TelemetrySink {
    public let fileURL: URL
    private let encoder: JSONEncoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func writeFrameSample(_ sample: FrameTelemetrySample) throws {
        try write(sample)
    }

    public func writeSimulationSample(_ sample: SimulationTelemetrySample) throws {
        try write(sample)
    }

    private func write<T: Encodable>(_ payload: T) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(payload)

        if FileManager.default.fileExists(atPath: fileURL.path()) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
            try handle.close()
        } else {
            var firstLine = Data()
            firstLine.append(data)
            firstLine.append(0x0A)
            try firstLine.write(to: fileURL, options: [.atomic])
        }
    }
}

public struct PerformanceScenario: Sendable {
    public var name: String
    public var ticks: Int
    public var setupCommands: [PlayerCommand]

    public init(name: String, ticks: Int, setupCommands: [PlayerCommand]) {
        self.name = name
        self.ticks = ticks
        self.setupCommands = setupCommands
    }

    public static let stressA = PerformanceScenario(
        name: "stress_a",
        ticks: 2_000,
        setupCommands: [
            PlayerCommand(tick: 1, actor: PlayerID(1), payload: .triggerWave),
            PlayerCommand(tick: 5, actor: PlayerID(1), payload: .placeStructure(BuildRequest(structure: .turretMount, position: GridPosition(x: 6, y: 1)))),
            PlayerCommand(tick: 6, actor: PlayerID(1), payload: .placeStructure(BuildRequest(structure: .turretMount, position: GridPosition(x: 6, y: 3)))),
            PlayerCommand(tick: 7, actor: PlayerID(1), payload: .placeStructure(BuildRequest(structure: .turretMount, position: GridPosition(x: 6, y: 5)))),
            PlayerCommand(tick: 8, actor: PlayerID(1), payload: .placeStructure(BuildRequest(structure: .conveyor, position: GridPosition(x: 2, y: 1)))),
            PlayerCommand(tick: 9, actor: PlayerID(1), payload: .placeStructure(BuildRequest(structure: .storage, position: GridPosition(x: 2, y: 2)))),
            PlayerCommand(tick: 10, actor: PlayerID(1), payload: .placeStructure(BuildRequest(structure: .assembler, position: GridPosition(x: 3, y: 2))))
        ]
    )
}

public struct PerformanceScenarioReport: Sendable {
    public var scenarioName: String
    public var ticksSimulated: Int
    public var wallClockMS: Double
    public var avgTickMS: Double

    public init(scenarioName: String, ticksSimulated: Int, wallClockMS: Double, avgTickMS: Double) {
        self.scenarioName = scenarioName
        self.ticksSimulated = ticksSimulated
        self.wallClockMS = wallClockMS
        self.avgTickMS = avgTickMS
    }
}

public final class PerformanceScenarioRunner {
    public init() {}

    public func run(_ scenario: PerformanceScenario, sink: TelemetrySink? = nil) throws -> PerformanceScenarioReport {
        let engine = SimulationEngine(worldState: .bootstrap())
        for command in scenario.setupCommands {
            engine.enqueue(command)
        }

        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<scenario.ticks {
            _ = engine.step()
            let world = engine.worldState
            let sample = SimulationTelemetrySample(
                timestamp: Date(),
                tick: world.tick,
                baseIntegrity: world.run.baseIntegrity,
                enemyCount: world.combat.enemies.count,
                projectileCount: world.combat.projectiles.count,
                currency: world.economy.currency
            )
            try sink?.writeSimulationSample(sample)
        }
        let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1_000

        return PerformanceScenarioReport(
            scenarioName: scenario.name,
            ticksSimulated: scenario.ticks,
            wallClockMS: elapsedMS,
            avgTickMS: elapsedMS / max(1.0, Double(scenario.ticks))
        )
    }
}
