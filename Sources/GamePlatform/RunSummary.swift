import Foundation

public struct RunSummarySnapshot: Codable, Hashable, Sendable {
    public var finalTick: UInt64
    public var wavesSurvived: Int
    public var enemiesDestroyed: Int
    public var structuresBuilt: Int
    public var ammoSpent: Int

    public init(
        finalTick: UInt64,
        wavesSurvived: Int,
        enemiesDestroyed: Int,
        structuresBuilt: Int,
        ammoSpent: Int
    ) {
        self.finalTick = finalTick
        self.wavesSurvived = max(0, wavesSurvived)
        self.enemiesDestroyed = max(0, enemiesDestroyed)
        self.structuresBuilt = max(0, structuresBuilt)
        self.ammoSpent = max(0, ammoSpent)
    }

    public var runDurationSeconds: Int {
        Int(finalTick / 20)
    }
}
