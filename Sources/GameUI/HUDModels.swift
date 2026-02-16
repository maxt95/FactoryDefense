import Foundation
import GameSimulation

public struct HUDSnapshot: Sendable {
    public var tick: UInt64
    public var currency: Int
    public var baseIntegrity: Int
    public var waveIndex: Int
    public var isWaveActive: Bool
    public var nextWaveInTicks: UInt64
    public var raidCooldownRemaining: UInt64
    public var ammoLight: Int

    public init(
        tick: UInt64,
        currency: Int,
        baseIntegrity: Int,
        waveIndex: Int,
        isWaveActive: Bool,
        nextWaveInTicks: UInt64,
        raidCooldownRemaining: UInt64,
        ammoLight: Int
    ) {
        self.tick = tick
        self.currency = currency
        self.baseIntegrity = baseIntegrity
        self.waveIndex = waveIndex
        self.isWaveActive = isWaveActive
        self.nextWaveInTicks = nextWaveInTicks
        self.raidCooldownRemaining = raidCooldownRemaining
        self.ammoLight = ammoLight
    }
}

public enum WarningBanner: String, Sendable {
    case none
    case lowAmmo
    case baseCritical
    case raidImminent
}

public struct HUDViewModel: Sendable {
    public var snapshot: HUDSnapshot
    public var warning: WarningBanner

    public init(snapshot: HUDSnapshot, warning: WarningBanner) {
        self.snapshot = snapshot
        self.warning = warning
    }

    public static func build(from world: WorldState) -> HUDViewModel {
        let nextWaveIn = world.threat.nextWaveTick > world.tick ? world.threat.nextWaveTick - world.tick : 0
        let raidRemaining = world.threat.raidCooldownUntilTick > world.tick
            ? world.threat.raidCooldownUntilTick - world.tick
            : 0
        let ammo = world.economy.inventories["ammo_light", default: 0]

        let warning: WarningBanner
        if world.run.baseIntegrity <= 20 {
            warning = .baseCritical
        } else if ammo < 10 && world.threat.isWaveActive {
            warning = .lowAmmo
        } else if raidRemaining < 40 {
            warning = .raidImminent
        } else {
            warning = .none
        }

        let snapshot = HUDSnapshot(
            tick: world.tick,
            currency: world.economy.currency,
            baseIntegrity: world.run.baseIntegrity,
            waveIndex: world.threat.waveIndex,
            isWaveActive: world.threat.isWaveActive,
            nextWaveInTicks: nextWaveIn,
            raidCooldownRemaining: raidRemaining,
            ammoLight: ammo
        )

        return HUDViewModel(snapshot: snapshot, warning: warning)
    }
}
