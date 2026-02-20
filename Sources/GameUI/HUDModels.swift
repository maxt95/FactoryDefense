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

public struct GroupedBottleneckAlert: Sendable, Identifiable {
    public var id: String { kind.rawValue }
    public var kind: BottleneckSignalKind
    public var severity: BottleneckSignalSeverity
    public var count: Int
    public var message: String
    public var representativeEntityID: EntityID?

    public init(
        kind: BottleneckSignalKind,
        severity: BottleneckSignalSeverity,
        count: Int,
        message: String,
        representativeEntityID: EntityID? = nil
    ) {
        self.kind = kind
        self.severity = severity
        self.count = count
        self.message = message
        self.representativeEntityID = representativeEntityID
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
    public var allResources: [ResourceChip]
    public var groupedAlerts: [GroupedBottleneckAlert]

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
        allResources: [ResourceChip],
        groupedAlerts: [GroupedBottleneckAlert] = []
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
        self.allResources = allResources
        self.groupedAlerts = groupedAlerts
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
    case ammoDryFire
    case inputStarved
    case outputBlocked
    case conveyorStall
    case wallNetworkUnderfed
    case surgeBacklogHigh
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

        // Legacy overrides that aren't bottleneck signals
        let warning: WarningBanner
        if world.hqHealth <= 100 {
            warning = .baseCritical
        } else if world.run.phase == .playing && nextWaveIn > 0 && nextWaveIn <= 80 {
            warning = .surgeImminent
        } else if let topSignal = world.bottleneck.activeSignals.first {
            warning = warningBanner(for: topSignal.kind)
        } else {
            warning = .none
        }

        let groupedAlerts = buildGroupedAlerts(from: world.bottleneck.activeSignals)
        let resources = buildResourceChips(from: world.economy.inventories)

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
            allResources: resources,
            groupedAlerts: groupedAlerts
        )

        return HUDViewModel(snapshot: snapshot, warning: warning)
    }

    private static func warningBanner(for kind: BottleneckSignalKind) -> WarningBanner {
        switch kind {
        case .ammoDryFire: return .ammoDryFire
        case .inputStarved: return .inputStarved
        case .outputBlocked: return .outputBlocked
        case .powerShortage: return .powerShortage
        case .minerNoOre: return .patchExhausted
        case .conveyorStall: return .conveyorStall
        case .wallNetworkUnderfed: return .wallNetworkUnderfed
        case .surgeBacklogHigh: return .surgeBacklogHigh
        }
    }

    static func buildGroupedAlerts(from signals: [BottleneckSignal]) -> [GroupedBottleneckAlert] {
        var grouped: [BottleneckSignalKind: (count: Int, severity: BottleneckSignalSeverity, entityID: EntityID?)] = [:]

        for signal in signals {
            if let existing = grouped[signal.kind] {
                grouped[signal.kind] = (
                    count: existing.count + 1,
                    severity: max(existing.severity, signal.severity),
                    entityID: existing.entityID
                )
            } else {
                grouped[signal.kind] = (count: 1, severity: signal.severity, entityID: signal.entityID)
            }
        }

        return grouped
            .sorted { $0.key.priority < $1.key.priority }
            .prefix(4)
            .map { kind, group in
                GroupedBottleneckAlert(
                    kind: kind,
                    severity: group.severity,
                    count: group.count,
                    message: alertMessage(for: kind, count: group.count),
                    representativeEntityID: group.entityID
                )
            }
    }

    private static func alertMessage(for kind: BottleneckSignalKind, count: Int) -> String {
        switch kind {
        case .ammoDryFire:
            return "Turrets dry firing"
        case .inputStarved:
            return count == 1 ? "1 building starved" : "\(count) buildings starved"
        case .outputBlocked:
            return count == 1 ? "1 output blocked" : "\(count) outputs blocked"
        case .powerShortage:
            return "Power shortage"
        case .minerNoOre:
            return count == 1 ? "1 miner idle (no ore)" : "\(count) miners idle (no ore)"
        case .conveyorStall:
            return count == 1 ? "1 conveyor stalled" : "\(count) conveyors stalled"
        case .wallNetworkUnderfed:
            return count == 1 ? "1 wall network low ammo" : "\(count) wall networks low ammo"
        case .surgeBacklogHigh:
            return "Spawn backlog high"
        }
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
