import Foundation
import GameContent
import GameSimulation

public enum BuildMenuCategory: String, CaseIterable, Sendable {
    case defense
    case production
    case logistics
    case utility
}

public struct BuildMenuEntry: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var structure: StructureType
    public var category: BuildMenuCategory
    public var costs: [ItemStack]

    public init(id: String, title: String, structure: StructureType, category: BuildMenuCategory, costs: [ItemStack]) {
        self.id = id
        self.title = title
        self.structure = structure
        self.category = category
        self.costs = costs
    }
}

public struct BuildMenuViewModel: Sendable {
    public var entries: [BuildMenuEntry]
    public var selectedEntryID: String?

    public init(entries: [BuildMenuEntry], selectedEntryID: String? = nil) {
        self.entries = entries
        self.selectedEntryID = selectedEntryID
    }

    public mutating func select(entryID: String) {
        selectedEntryID = entryID
    }

    public func selectedEntry() -> BuildMenuEntry? {
        guard let selectedEntryID else { return nil }
        return entries.first(where: { $0.id == selectedEntryID })
    }

    public func isAffordable(_ entry: BuildMenuEntry, inventory: [ItemID: Int]) -> Bool {
        for cost in entry.costs {
            if inventory[cost.itemID, default: 0] < cost.quantity {
                return false
            }
        }
        return true
    }

    public func groupedEntries() -> [BuildMenuCategory: [BuildMenuEntry]] {
        Dictionary(grouping: entries, by: \ .category)
    }

    public static let productionPreset = BuildMenuViewModel(entries: [
        BuildMenuEntry(
            id: "turret_mount",
            title: "Turret Mount",
            structure: .turretMount,
            category: .defense,
            costs: [ItemStack(itemID: "turret_core", quantity: 1), ItemStack(itemID: "plate_steel", quantity: 2)]
        ),
        BuildMenuEntry(
            id: "wall",
            title: "Wall",
            structure: .wall,
            category: .defense,
            costs: [ItemStack(itemID: "wall_kit", quantity: 1)]
        ),
        BuildMenuEntry(
            id: "miner",
            title: "Miner",
            structure: .miner,
            category: .production,
            costs: [ItemStack(itemID: "plate_iron", quantity: 6), ItemStack(itemID: "gear", quantity: 3)]
        ),
        BuildMenuEntry(
            id: "smelter",
            title: "Smelter",
            structure: .smelter,
            category: .production,
            costs: [ItemStack(itemID: "plate_steel", quantity: 4)]
        ),
        BuildMenuEntry(
            id: "ammo_module",
            title: "Ammo Module",
            structure: .ammoModule,
            category: .production,
            costs: [ItemStack(itemID: "circuit", quantity: 2), ItemStack(itemID: "plate_steel", quantity: 2)]
        ),
        BuildMenuEntry(
            id: "conveyor",
            title: "Conveyor",
            structure: .conveyor,
            category: .logistics,
            costs: [ItemStack(itemID: "plate_iron", quantity: 1)]
        ),
        BuildMenuEntry(
            id: "storage",
            title: "Storage",
            structure: .storage,
            category: .logistics,
            costs: [ItemStack(itemID: "plate_steel", quantity: 3), ItemStack(itemID: "gear", quantity: 2)]
        ),
        BuildMenuEntry(
            id: "power_plant",
            title: "Power Plant",
            structure: .powerPlant,
            category: .utility,
            costs: [ItemStack(itemID: "circuit", quantity: 2), ItemStack(itemID: "plate_copper", quantity: 4)]
        )
    ])
}

public enum TechNodeStatus: String, Sendable {
    case locked
    case available
    case unlocked
}

public struct TechNodePresentation: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var status: TechNodeStatus
    public var costs: [ItemStack]

    public init(id: String, title: String, status: TechNodeStatus, costs: [ItemStack]) {
        self.id = id
        self.title = title
        self.status = status
        self.costs = costs
    }
}

public struct TechTreeViewModel: Sendable {
    public var nodeDefs: [TechNodeDef]
    public var unlockedNodeIDs: Set<String>

    public init(nodeDefs: [TechNodeDef], unlockedNodeIDs: Set<String>) {
        self.nodeDefs = nodeDefs
        self.unlockedNodeIDs = unlockedNodeIDs
    }

    public func nodes(inventory: [ItemID: Int]) -> [TechNodePresentation] {
        let byID = Dictionary(uniqueKeysWithValues: nodeDefs.map { ($0.id, $0) })

        return nodeDefs.map { node in
            let status: TechNodeStatus
            if unlockedNodeIDs.contains(node.id) {
                status = .unlocked
            } else {
                let prereqsMet = node.prerequisites.allSatisfy { unlockedNodeIDs.contains($0) }
                let costsMet = node.costs.allSatisfy { inventory[$0.itemID, default: 0] >= $0.quantity }
                status = (prereqsMet && costsMet) ? .available : .locked
            }

            return TechNodePresentation(
                id: node.id,
                title: prettify(nodeID: node.id),
                status: status,
                costs: byID[node.id]?.costs ?? []
            )
        }
    }

    public mutating func unlock(nodeID: String, inventory: inout [ItemID: Int]) -> Bool {
        guard let node = nodeDefs.first(where: { $0.id == nodeID }) else { return false }
        guard !unlockedNodeIDs.contains(nodeID) else { return true }
        guard node.prerequisites.allSatisfy({ unlockedNodeIDs.contains($0) }) else { return false }

        for cost in node.costs {
            if inventory[cost.itemID, default: 0] < cost.quantity {
                return false
            }
        }

        for cost in node.costs {
            inventory[cost.itemID, default: 0] -= cost.quantity
        }

        unlockedNodeIDs.insert(nodeID)
        return true
    }

    private func prettify(nodeID: String) -> String {
        nodeID
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

public extension TechTreeViewModel {
    static let productionPreset = TechTreeViewModel(
        nodeDefs: [
            TechNodeDef(id: "root", costs: [], prerequisites: [], unlocks: ["logistics_1", "defense_1"]),
            TechNodeDef(id: "logistics_1", costs: [ItemStack(itemID: "plate_iron", quantity: 20)], prerequisites: ["root"], unlocks: ["conveyor_mk2"]),
            TechNodeDef(id: "defense_1", costs: [ItemStack(itemID: "ammo_light", quantity: 40)], prerequisites: ["root"], unlocks: ["heavy_ammo"]),
            TechNodeDef(id: "conveyor_mk2", costs: [ItemStack(itemID: "gear", quantity: 12)], prerequisites: ["logistics_1"], unlocks: []),
            TechNodeDef(id: "heavy_ammo", costs: [ItemStack(itemID: "ammo_heavy", quantity: 25)], prerequisites: ["defense_1"], unlocks: [])
        ],
        unlockedNodeIDs: ["root"]
    )
}

public struct OnboardingStep: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var isComplete: Bool

    public init(id: String, title: String, detail: String, isComplete: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isComplete = isComplete
    }
}

public struct OnboardingGuideViewModel: Sendable {
    public var steps: [OnboardingStep]

    public init(steps: [OnboardingStep]) {
        self.steps = steps
    }

    public static let starter = OnboardingGuideViewModel(steps: [
        OnboardingStep(id: "mine", title: "Start Mining", detail: "Place miners and gather iron/copper ore."),
        OnboardingStep(id: "power", title: "Stabilize Power", detail: "Keep available power above demand."),
        OnboardingStep(id: "ammo", title: "Automate Ammo", detail: "Build ammo modules before wave spikes."),
        OnboardingStep(id: "defense", title: "Fortify", detail: "Add walls and turret mounts on weak lanes."),
        OnboardingStep(id: "extract", title: "Extract", detail: "Reach milestone and extract to bank rewards.")
    ])

    public mutating func update(from world: WorldState) {
        for index in steps.indices {
            let id = steps[index].id
            switch id {
            case "mine":
                steps[index].isComplete = world.economy.inventories["ore_iron", default: 0] >= 20
            case "power":
                steps[index].isComplete = world.economy.powerAvailable >= world.economy.powerDemand && world.economy.powerDemand > 0
            case "ammo":
                steps[index].isComplete = world.economy.inventories["ammo_light", default: 0] >= 25
            case "defense":
                steps[index].isComplete = world.entities.structures(of: .wall).count >= 3 && world.entities.structures(of: .turretMount).count >= 2
            case "extract":
                steps[index].isComplete = world.run.extracted
            default:
                break
            }
        }
    }
}

public struct TuningDashboardSnapshot: Sendable {
    public var ammoStock: Int
    public var enemyCount: Int
    public var projectileCount: Int
    public var baseIntegrity: Int
    public var powerHeadroom: Int

    public init(ammoStock: Int, enemyCount: Int, projectileCount: Int, baseIntegrity: Int, powerHeadroom: Int) {
        self.ammoStock = ammoStock
        self.enemyCount = enemyCount
        self.projectileCount = projectileCount
        self.baseIntegrity = baseIntegrity
        self.powerHeadroom = powerHeadroom
    }

    public static func from(world: WorldState) -> TuningDashboardSnapshot {
        TuningDashboardSnapshot(
            ammoStock: world.economy.inventories["ammo_light", default: 0],
            enemyCount: world.combat.enemies.count,
            projectileCount: world.combat.projectiles.count,
            baseIntegrity: world.run.baseIntegrity,
            powerHeadroom: world.economy.powerAvailable - world.economy.powerDemand
        )
    }
}

#if canImport(SwiftUI)
import SwiftUI

public struct BuildMenuPanel: View {
    public var viewModel: BuildMenuViewModel
    public var inventory: [ItemID: Int]
    public var onSelect: (BuildMenuEntry) -> Void

    public init(viewModel: BuildMenuViewModel, inventory: [ItemID: Int], onSelect: @escaping (BuildMenuEntry) -> Void) {
        self.viewModel = viewModel
        self.inventory = inventory
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Build")
                .font(.headline)

            ForEach(BuildMenuCategory.allCases, id: \.self) { category in
                if let entries = viewModel.groupedEntries()[category], !entries.isEmpty {
                    Text(category.rawValue.capitalized)
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)

                    ForEach(entries) { entry in
                        let affordable = viewModel.isAffordable(entry, inventory: inventory)
                        Button(action: { onSelect(entry) }) {
                            HStack {
                                Text(entry.title)
                                Spacer()
                                Text(costLabel(entry.costs))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        .background(affordable ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func costLabel(_ costs: [ItemStack]) -> String {
        costs.map { "\($0.quantity)x \($0.itemID)" }.joined(separator: " • ")
    }
}

public struct TechTreePanel: View {
    public var nodes: [TechNodePresentation]

    public init(nodes: [TechNodePresentation]) {
        self.nodes = nodes
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tech Tree")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(nodes) { node in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(node.title)
                                .font(.subheadline.weight(.semibold))
                            Text(statusLabel(node.status))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .frame(width: 150, alignment: .leading)
                        .background(backgroundColor(node.status))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func statusLabel(_ status: TechNodeStatus) -> String {
        switch status {
        case .locked: return "Locked"
        case .available: return "Available"
        case .unlocked: return "Unlocked"
        }
    }

    private func backgroundColor(_ status: TechNodeStatus) -> Color {
        switch status {
        case .locked: return Color.gray.opacity(0.2)
        case .available: return Color.orange.opacity(0.25)
        case .unlocked: return Color.green.opacity(0.25)
        }
    }
}

public struct OnboardingPanel: View {
    public var steps: [OnboardingStep]

    public init(steps: [OnboardingStep]) {
        self.steps = steps
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Run Objectives")
                .font(.headline)

            ForEach(steps) { step in
                HStack(spacing: 8) {
                    Image(systemName: step.isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(step.isComplete ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.subheadline)
                        Text(step.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

public struct TuningDashboardPanel: View {
    public var snapshot: TuningDashboardSnapshot

    public init(snapshot: TuningDashboardSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Balance Telemetry")
                .font(.headline)
            Text("Ammo: \(snapshot.ammoStock)")
            Text("Enemies: \(snapshot.enemyCount)")
            Text("Projectiles: \(snapshot.projectileCount)")
            Text("Base HP: \(snapshot.baseIntegrity)")
            Text("Power Headroom: \(snapshot.powerHeadroom)")
        }
        .font(.caption)
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
#endif
