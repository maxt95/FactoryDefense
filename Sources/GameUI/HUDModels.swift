import Foundation
import GameSimulation

public struct ResourceChip: Sendable, Identifiable {
    public var id: String { itemID }
    public var itemID: String
    public var label: String
    public var quantity: Int

    public init(itemID: String, label: String, quantity: Int) {
        self.itemID = itemID
        self.label = label
        self.quantity = quantity
    }
}

public struct OreRingStatusChip: Sendable, Hashable, Identifiable {
    public var id: Int { ringIndex }
    public var ringIndex: Int
    public var state: OreRingVisibilityState
    public var remainingSurveyTicks: UInt64
    public var visiblePatchCount: Int

    public init(
        ringIndex: Int,
        state: OreRingVisibilityState,
        remainingSurveyTicks: UInt64,
        visiblePatchCount: Int
    ) {
        self.ringIndex = ringIndex
        self.state = state
        self.remainingSurveyTicks = remainingSurveyTicks
        self.visiblePatchCount = visiblePatchCount
    }
}

public struct HUDSnapshot: Sendable {
    public var tick: UInt64
    public var currency: Int
    public var hqHealth: Int
    public var hqMaxHealth: Int
    public var waveIndex: Int
    public var isWaveActive: Bool
    public var isGracePeriod: Bool
    public var nextWaveInTicks: UInt64
    public var graceRemainingTicks: UInt64
    public var surgeRemainingTicks: UInt64
    public var ammoLight: Int
    public var powerAvailable: Int
    public var powerDemand: Int
    public var oreRings: [OreRingStatusChip]
    public var allResources: [ResourceChip]

    public init(
        tick: UInt64,
        currency: Int,
        hqHealth: Int,
        hqMaxHealth: Int,
        waveIndex: Int,
        isWaveActive: Bool,
        isGracePeriod: Bool,
        nextWaveInTicks: UInt64,
        graceRemainingTicks: UInt64,
        surgeRemainingTicks: UInt64,
        ammoLight: Int,
        powerAvailable: Int,
        powerDemand: Int,
        oreRings: [OreRingStatusChip],
        allResources: [ResourceChip]
    ) {
        self.tick = tick
        self.currency = currency
        self.hqHealth = hqHealth
        self.hqMaxHealth = hqMaxHealth
        self.waveIndex = waveIndex
        self.isWaveActive = isWaveActive
        self.isGracePeriod = isGracePeriod
        self.nextWaveInTicks = nextWaveInTicks
        self.graceRemainingTicks = graceRemainingTicks
        self.surgeRemainingTicks = surgeRemainingTicks
        self.ammoLight = ammoLight
        self.powerAvailable = powerAvailable
        self.powerDemand = powerDemand
        self.oreRings = oreRings
        self.allResources = allResources
    }

    public var elapsedSeconds: Int {
        Int(tick / 20)
    }

    public var powerHeadroom: Int {
        powerAvailable - powerDemand
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
        let surgeRemaining: UInt64
        if world.threat.isWaveActive, let waveEnds = world.threat.waveEndsAtTick, waveEnds > world.tick {
            surgeRemaining = waveEnds - world.tick
        } else {
            surgeRemaining = 0
        }
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

        let resources = buildResourceChips(from: world.economy.inventories)
        let ringStatuses = buildOreRingStatuses(from: world)

        let snapshot = HUDSnapshot(
            tick: world.tick,
            currency: world.economy.currency,
            hqHealth: world.hqHealth,
            hqMaxHealth: world.hqMaxHealth,
            waveIndex: world.threat.waveIndex,
            isWaveActive: world.threat.isWaveActive,
            isGracePeriod: world.run.phase == .gracePeriod,
            nextWaveInTicks: nextWaveIn,
            graceRemainingTicks: graceRemaining,
            surgeRemainingTicks: surgeRemaining,
            ammoLight: ammo,
            powerAvailable: world.economy.powerAvailable,
            powerDemand: world.economy.powerDemand,
            oreRings: ringStatuses,
            allResources: resources
        )

        return HUDViewModel(snapshot: snapshot, warning: warning)
    }

    private static let resourceOrder: [String] = [
        "plate_iron", "gear", "circuit", "ammo_light",
        "ammo_heavy", "ammo_plasma",
        "ore_iron", "ore_copper", "ore_coal",
        "plate_copper", "plate_steel",
        "power_cell", "wall_kit", "turret_core"
    ]

    private static func buildResourceChips(from inventories: [String: Int]) -> [ResourceChip] {
        resourceOrder.map { itemID in
            ResourceChip(
                itemID: itemID,
                label: shortLabel(for: itemID),
                quantity: inventories[itemID, default: 0]
            )
        }
    }

    private static func buildOreRingStatuses(from world: WorldState) -> [OreRingStatusChip] {
        let maxRing = max(3, world.oreLifecycle.ringStates.keys.max() ?? 0)
        return (0...maxRing).map { ringIndex in
            let state = world.oreLifecycle.ringStates[ringIndex, default: ringIndex == 0 ? .revealed : .locked]
            let remainingSurveyTicks: UInt64
            if state == .surveying {
                let endsAt = world.oreLifecycle.surveyEndTickByRing[ringIndex] ?? world.tick
                remainingSurveyTicks = endsAt > world.tick ? (endsAt - world.tick) : 0
            } else {
                remainingSurveyTicks = 0
            }
            let visiblePatchCount = world.orePatches.filter {
                $0.revealRing == ringIndex && $0.isRevealed
            }.count
            return OreRingStatusChip(
                ringIndex: ringIndex,
                state: state,
                remainingSurveyTicks: remainingSurveyTicks,
                visiblePatchCount: visiblePatchCount
            )
        }
    }

    private static func shortLabel(for itemID: String) -> String {
        switch itemID {
        case "ore_iron": return "Iron Ore"
        case "ore_copper": return "Copper Ore"
        case "ore_coal": return "Coal"
        case "plate_iron": return "Iron Plate"
        case "plate_copper": return "Copper Plate"
        case "plate_steel": return "Steel Plate"
        case "gear": return "Gear"
        case "circuit": return "Circuit"
        case "power_cell": return "Power Cell"
        case "wall_kit": return "Wall Kit"
        case "turret_core": return "Turret Core"
        case "ammo_light": return "Light Ammo"
        case "ammo_heavy": return "Heavy Ammo"
        case "ammo_plasma": return "Plasma Ammo"
        default: return itemID
        }
    }
}
