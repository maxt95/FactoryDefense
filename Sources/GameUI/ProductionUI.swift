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
            id: "assembler",
            title: "Assembler",
            structure: .assembler,
            category: .production,
            costs: [ItemStack(itemID: "plate_iron", quantity: 4), ItemStack(itemID: "circuit", quantity: 2)]
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
            id: "splitter",
            title: "Splitter",
            structure: .splitter,
            category: .logistics,
            costs: [ItemStack(itemID: "plate_iron", quantity: 1)]
        ),
        BuildMenuEntry(
            id: "merger",
            title: "Merger",
            structure: .merger,
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
        ),
        BuildMenuEntry(
            id: "research_center",
            title: "Research Center",
            structure: .researchCenter,
            category: .utility,
            costs: [ItemStack(itemID: "plate_iron", quantity: 8), ItemStack(itemID: "circuit", quantity: 4)]
        ),
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
        )
    ], selectedEntryID: "miner")
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
        OnboardingStep(id: "defense", title: "Fortify", detail: "Add walls and turret mounts on weak lanes.")
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
            baseIntegrity: world.hqHealth,
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
                .foregroundStyle(HUDColor.primaryText)

            ForEach(BuildMenuCategory.allCases, id: \.self) { category in
                if let entries = viewModel.groupedEntries()[category], !entries.isEmpty {
                    Text(category.rawValue.capitalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HUDColor.primaryText)
                        .padding(.top, 4)

                    ForEach(entries) { entry in
                        let affordable = viewModel.isAffordable(entry, inventory: inventory)
                        let isSelected = viewModel.selectedEntryID == entry.id
                        Button(action: { onSelect(entry) }) {
                            HStack {
                                Text(entry.title)
                                    .foregroundStyle(HUDColor.primaryText)
                                Spacer()
                                Text(costLabel(entry.costs))
                                    .foregroundStyle(HUDColor.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        .background(
                            isSelected
                                ? HUDColor.accentTeal.opacity(0.20)
                                : affordable ? HUDColor.accentGreen.opacity(0.15) : HUDColor.accentRed.opacity(0.15)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(HUDColor.border, lineWidth: 1)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
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
                .foregroundStyle(HUDColor.primaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(nodes) { node in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(node.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(HUDColor.primaryText)
                            Text(statusLabel(node.status))
                                .font(.caption)
                                .foregroundStyle(HUDColor.secondaryText)
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
        case .locked: return HUDColor.surface
        case .available: return HUDColor.accentAmber.opacity(0.20)
        case .unlocked: return HUDColor.accentGreen.opacity(0.20)
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
                .foregroundStyle(HUDColor.primaryText)

            ForEach(steps) { step in
                HStack(spacing: 8) {
                    Image(systemName: step.isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(step.isComplete ? HUDColor.accentGreen : HUDColor.secondaryText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.subheadline)
                            .foregroundStyle(HUDColor.primaryText)
                        Text(step.detail)
                            .font(.caption)
                            .foregroundStyle(HUDColor.secondaryText)
                    }
                }
            }
        }
        .padding(10)
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
                .foregroundStyle(HUDColor.primaryText)
            statRow("Ammo:", value: "\(snapshot.ammoStock)")
            statRow("Enemies:", value: "\(snapshot.enemyCount)")
            statRow("Projectiles:", value: "\(snapshot.projectileCount)")
            statRow("Base HP:", value: "\(snapshot.baseIntegrity)")
            statRow("Power Headroom:", value: "\(snapshot.powerHeadroom)")
        }
        .padding(10)
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(HUDColor.secondaryText)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(HUDColor.primaryText)
        }
    }
}

public struct TileLegendPanel: View {
    public init() {}

    public var body: some View {
        let sample = sampleColors

        VStack(alignment: .leading, spacing: 8) {
            Text("Tile Legend")
                .font(.headline)
                .foregroundStyle(HUDColor.primaryText)

            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(row.color)
                        .frame(width: 14, height: 14)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(HUDColor.border, lineWidth: 1)
                        }
                        .padding(.top, 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HUDColor.primaryText)
                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(HUDColor.secondaryText)
                        Text(row.formula)
                            .font(.caption2.monospaced())
                            .foregroundStyle(HUDColor.secondaryText)
                    }
                }
                .padding(6)
                .background(HUDColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            Text("Ore Deposits")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HUDColor.primaryText)
                .padding(.top, 4)

            ForEach(oreRows) { row in
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(row.color)
                        .frame(width: 14, height: 14)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(HUDColor.border, lineWidth: 1)
                        }
                        .padding(.top, 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HUDColor.primaryText)
                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(HUDColor.secondaryText)
                    }
                }
                .padding(6)
                .background(HUDColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            Text(
                "Order: walkable -> spawn blend -> blocked override -> restricted blend -> ramp boost -> base override -> border darken (x0.68 near edges) -> preview blend."
            )
            .font(.caption2)
            .foregroundStyle(HUDColor.secondaryText)

            Text(
                "Ramp sample: walkable + 0.16 (elevation 2) = \(sample.rampSample.label)"
            )
            .font(.caption2.monospaced())
            .foregroundStyle(HUDColor.secondaryText)
        }
        .padding(10)
    }

    private var rows: [TileLegendRow] {
        let sample = sampleColors
        return [
            TileLegendRow(
                id: "walkable",
                label: "Walkable",
                detail: "Default buildable terrain.",
                formula: "RGB(0.160, 0.180, 0.200)",
                color: sample.walkable.color
            ),
            TileLegendRow(
                id: "spawn",
                label: "Spawn Lane",
                detail: "Enemy entry edge.",
                formula: "mix(walkable, RGB(0.360,0.200,0.180), 0.55) = \(sample.spawnLane.label)",
                color: sample.spawnLane.color
            ),
            TileLegendRow(
                id: "blocked",
                label: "Blocked",
                detail: "Unwalkable terrain.",
                formula: "RGB(0.080, 0.090, 0.100) (override)",
                color: sample.blocked.color
            ),
            TileLegendRow(
                id: "restricted",
                label: "Restricted",
                detail: "Placement is not allowed.",
                formula: "mix(current, RGB(0.400,0.320,0.100), 0.70) -> walkable sample \(sample.restrictedOnWalkable.label)",
                color: sample.restrictedOnWalkable.color
            ),
            TileLegendRow(
                id: "ramp",
                label: "Ramp",
                detail: "Adds brightness by elevation.",
                formula: "current += min(elevation * 0.08, 0.32) per RGB channel",
                color: sample.rampSample.color
            ),
            TileLegendRow(
                id: "base",
                label: "Base",
                detail: "Protect this tile.",
                formula: "RGB(0.120, 0.420, 0.460) (override)",
                color: sample.base.color
            ),
            TileLegendRow(
                id: "preview-valid",
                label: "Preview Valid",
                detail: "Placement footprint when valid.",
                formula: "mix(current, RGB(0.110,0.560,0.190), 0.75) -> walkable sample \(sample.previewValidOnWalkable.label)",
                color: sample.previewValidOnWalkable.color
            ),
            TileLegendRow(
                id: "preview-invalid",
                label: "Preview Invalid",
                detail: "Placement footprint when invalid.",
                formula: "mix(current, RGB(0.620,0.120,0.120), 0.75) -> walkable sample \(sample.previewInvalidOnWalkable.label)",
                color: sample.previewInvalidOnWalkable.color
            )
        ]
    }

    private var sampleColors: TileLegendSampleColors {
        let walkable = RGBColor(0.16, 0.18, 0.20)
        let spawnTint = RGBColor(0.36, 0.20, 0.18)
        let blocked = RGBColor(0.08, 0.09, 0.10)
        let restrictedTint = RGBColor(0.40, 0.32, 0.10)
        let base = RGBColor(0.12, 0.42, 0.46)
        let previewValidAccent = RGBColor(0.11, 0.56, 0.19)
        let previewInvalidAccent = RGBColor(0.62, 0.12, 0.12)

        return TileLegendSampleColors(
            walkable: walkable,
            spawnLane: walkable.mixed(with: spawnTint, factor: 0.55),
            blocked: blocked,
            restrictedOnWalkable: walkable.mixed(with: restrictedTint, factor: 0.70),
            rampSample: walkable.adding(0.16),
            base: base,
            previewValidOnWalkable: walkable.mixed(with: previewValidAccent, factor: 0.75),
            previewInvalidOnWalkable: walkable.mixed(with: previewInvalidAccent, factor: 0.75)
        )
    }

    private var oreRows: [OreLegendRow] {
        [
            OreLegendRow(
                id: "ore_iron",
                label: "Iron Ore",
                detail: "Rust-orange deposit.",
                color: oreColor("ore_iron")
            ),
            OreLegendRow(
                id: "ore_copper",
                label: "Copper Ore",
                detail: "Teal-green deposit.",
                color: oreColor("ore_copper")
            ),
            OreLegendRow(
                id: "ore_coal",
                label: "Coal",
                detail: "Dark-charcoal deposit.",
                color: oreColor("ore_coal")
            )
        ]
    }

    private func oreColor(_ oreType: ItemID) -> Color {
        let color = OrePresentation.color(for: oreType)
        return Color(red: Double(color.x), green: Double(color.y), blue: Double(color.z))
    }

    private struct TileLegendSampleColors {
        var walkable: RGBColor
        var spawnLane: RGBColor
        var blocked: RGBColor
        var restrictedOnWalkable: RGBColor
        var rampSample: RGBColor
        var base: RGBColor
        var previewValidOnWalkable: RGBColor
        var previewInvalidOnWalkable: RGBColor
    }

    private struct RGBColor {
        var r: Double
        var g: Double
        var b: Double

        init(_ r: Double, _ g: Double, _ b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }

        var color: Color {
            Color(red: r, green: g, blue: b)
        }

        var label: String {
            String(format: "RGB(%.3f, %.3f, %.3f)", r, g, b)
        }

        func mixed(with other: RGBColor, factor: Double) -> RGBColor {
            let t = min(max(factor, 0), 1)
            let inverse = 1 - t
            return RGBColor(
                (r * inverse) + (other.r * t),
                (g * inverse) + (other.g * t),
                (b * inverse) + (other.b * t)
            )
        }

        func adding(_ value: Double) -> RGBColor {
            RGBColor(r + value, g + value, b + value)
        }
    }

    private struct TileLegendRow: Identifiable {
        var id: String
        var label: String
        var detail: String
        var formula: String
        var color: Color
    }

    private struct OreLegendRow: Identifiable {
        var id: String
        var label: String
        var detail: String
        var color: Color
    }
}

public struct BuildingReferencePanel: View {
    public var world: WorldState

    public init(world: WorldState) {
        self.world = world
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Building Reference")
                .font(.headline)
                .foregroundStyle(HUDColor.primaryText)

            ForEach(referenceRows) { row in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(row.color)
                        .frame(width: 12, height: 12)
                        .padding(.top, 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HUDColor.primaryText)
                        Text(row.info)
                            .font(.caption)
                            .foregroundStyle(HUDColor.secondaryText)
                    }

                    Spacer()

                    Text("x\(row.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(HUDColor.secondaryText)
                }
                .padding(6)
                .background(HUDColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(10)
    }

    private var referenceRows: [ReferenceRow] {
        StructureType.allCases.map { structure in
            let count = world.entities.structures(of: structure).count
            return ReferenceRow(
                id: structure,
                label: structureLabel(structure),
                info: "\(structure.blocksMovement ? "Blocks path" : "No block") • \(structure.footprint.width)x\(structure.footprint.height)",
                count: count,
                color: structureColor(structure)
            )
        }
    }

    private func structureLabel(_ structure: StructureType) -> String {
        switch structure {
        case .hq: return "Headquarters"
        case .wall: return "Wall"
        case .turretMount: return "Turret Mount"
        case .miner: return "Miner"
        case .smelter: return "Smelter"
        case .assembler: return "Assembler"
        case .ammoModule: return "Ammo Module"
        case .powerPlant: return "Power Plant"
        case .conveyor: return "Conveyor"
        case .splitter: return "Splitter"
        case .merger: return "Merger"
        case .storage: return "Storage"
        case .researchCenter: return "Research Center"
        }
    }

    private func structureColor(_ structure: StructureType) -> Color {
        switch structure {
        case .hq:
            return Color(red: 0.18, green: 0.62, blue: 0.62)
        case .wall:
            return Color(red: 0.60, green: 0.60, blue: 0.60)
        case .turretMount:
            return Color(red: 0.20, green: 0.50, blue: 0.80)
        case .miner:
            return Color(red: 0.80, green: 0.60, blue: 0.20)
        case .smelter:
            return Color(red: 0.90, green: 0.30, blue: 0.10)
        case .assembler:
            return Color(red: 0.30, green: 0.70, blue: 0.30)
        case .ammoModule:
            return Color(red: 0.80, green: 0.20, blue: 0.20)
        case .powerPlant:
            return Color(red: 0.90, green: 0.90, blue: 0.20)
        case .conveyor:
            return Color(red: 0.50, green: 0.50, blue: 0.70)
        case .splitter:
            return Color(red: 0.35, green: 0.55, blue: 0.78)
        case .merger:
            return Color(red: 0.48, green: 0.52, blue: 0.80)
        case .storage:
            return Color(red: 0.60, green: 0.40, blue: 0.20)
        case .researchCenter:
            return Color(red: 0.55, green: 0.28, blue: 0.72)
        }
    }

    private struct ReferenceRow: Identifiable {
        let id: StructureType
        let label: String
        let info: String
        let count: Int
        let color: Color
    }
}
#endif
