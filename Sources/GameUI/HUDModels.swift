import Foundation
import GameSimulation

public struct HUDSnapshot: Sendable {
    public var tick: UInt64
    public var currency: Int
    public var hqHealth: Int
    public var waveIndex: Int
    public var isWaveActive: Bool
    public var nextWaveInTicks: UInt64
    public var graceRemainingTicks: UInt64
    public var ammoLight: Int

    public init(
        tick: UInt64,
        currency: Int,
        hqHealth: Int,
        waveIndex: Int,
        isWaveActive: Bool,
        nextWaveInTicks: UInt64,
        graceRemainingTicks: UInt64,
        ammoLight: Int
    ) {
        self.tick = tick
        self.currency = currency
        self.hqHealth = hqHealth
        self.waveIndex = waveIndex
        self.isWaveActive = isWaveActive
        self.nextWaveInTicks = nextWaveInTicks
        self.graceRemainingTicks = graceRemainingTicks
        self.ammoLight = ammoLight
    }
}

public enum WarningBanner: String, Sendable {
    case none
    case lowAmmo
    case baseCritical
    case surgeImminent
    case powerShortage
    case patchExhausted
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
        let graceRemaining = world.run.phase == .gracePeriod && world.threat.graceEndsAtTick > world.tick
            ? world.threat.graceEndsAtTick - world.tick
            : 0
        let ammo = world.economy.inventories["ammo_light", default: 0]
        let powerShortage = world.economy.powerDemand > world.economy.powerAvailable
        let hasExhaustedPatch = world.orePatches.contains(where: { $0.isExhausted })

        let warning: WarningBanner
        if world.hqHealth <= 100 {
            warning = .baseCritical
        } else if powerShortage {
            warning = .powerShortage
        } else if ammo < 10 && world.threat.isWaveActive {
            warning = .lowAmmo
        } else if hasExhaustedPatch {
            warning = .patchExhausted
        } else if world.run.phase == .playing && nextWaveIn > 0 && nextWaveIn <= 80 {
            warning = .surgeImminent
        } else {
            warning = .none
        }

        let snapshot = HUDSnapshot(
            tick: world.tick,
            currency: world.economy.currency,
            hqHealth: world.hqHealth,
            waveIndex: world.threat.waveIndex,
            isWaveActive: world.threat.isWaveActive,
            nextWaveInTicks: nextWaveIn,
            graceRemainingTicks: graceRemaining,
            ammoLight: ammo
        )

        return HUDViewModel(snapshot: snapshot, warning: warning)
    }
}
