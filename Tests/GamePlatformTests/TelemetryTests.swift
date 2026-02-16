import XCTest
@testable import GamePlatform

final class TelemetryTests: XCTestCase {
    func testJSONLinesTelemetrySinkWritesSamples() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("telemetry.jsonl")

        let sink = JSONLinesTelemetrySink(fileURL: fileURL)
        try sink.writeFrameSample(
            FrameTelemetrySample(
                timestamp: Date(),
                frameIndex: 1,
                cpuFrameMS: 4.2,
                gpuFrameMS: 6.9
            )
        )
        try sink.writeSimulationSample(
            SimulationTelemetrySample(
                timestamp: Date(),
                tick: 20,
                baseIntegrity: 95,
                enemyCount: 3,
                projectileCount: 2,
                currency: 10
            )
        )

        let data = try Data(contentsOf: fileURL)
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
    }

    func testPerformanceScenarioRunnerProducesReport() throws {
        let runner = PerformanceScenarioRunner()
        let report = try runner.run(.stressA)

        XCTAssertEqual(report.scenarioName, "stress_a")
        XCTAssertEqual(report.ticksSimulated, 2_000)
        XCTAssertGreaterThan(report.wallClockMS, 0)
        XCTAssertLessThan(report.avgTickMS, 25.0)
    }
}
