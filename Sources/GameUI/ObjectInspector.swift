import Foundation
import GameContent
import GameSimulation

public struct ObjectInspectorRow: Identifiable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var value: String

    public init(id: String? = nil, label: String, value: String) {
        self.id = id ?? label
        self.label = label
        self.value = value
    }
}

public struct ObjectInspectorSection: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var rows: [ObjectInspectorRow]

    public init(id: String? = nil, title: String, rows: [ObjectInspectorRow]) {
        self.id = id ?? title
        self.title = title
        self.rows = rows
    }
}

public struct ObjectInspectorViewModel: Identifiable, Sendable {
    public var id: EntityID { entityID }
    public var entityID: EntityID
    public var title: String
    public var subtitle: String
    public var anchorPosition: GridPosition
    public var anchorHeightTiles: Int
    public var sections: [ObjectInspectorSection]

    public init(
        entityID: EntityID,
        title: String,
        subtitle: String,
        anchorPosition: GridPosition,
        anchorHeightTiles: Int,
        sections: [ObjectInspectorSection]
    ) {
        self.entityID = entityID
        self.title = title
        self.subtitle = subtitle
        self.anchorPosition = anchorPosition
        self.anchorHeightTiles = max(1, anchorHeightTiles)
        self.sections = sections
    }
}

public struct ObjectInspectorBuilder: Sendable {
    private let recipeDurationByID: [String: Double]

    public init(recipeDurationByID: [String: Double]? = nil) {
        if let recipeDurationByID {
            self.recipeDurationByID = recipeDurationByID
        } else {
            self.recipeDurationByID = Dictionary(
                uniqueKeysWithValues: EconomySystem.defaultRecipes.map { ($0.id, Double($0.seconds)) }
            )
        }
    }

    public func build(entityID: EntityID, in world: WorldState) -> ObjectInspectorViewModel? {
        guard let entity = world.entities.entity(id: entityID) else { return nil }

        switch entity.category {
        case .structure:
            return structureModel(for: entity, in: world)
        case .enemy:
            return enemyModel(for: entity, in: world)
        case .projectile:
            return projectileModel(for: entity, in: world)
        case .player:
            return nil
        }
    }

    private func structureModel(for entity: Entity, in world: WorldState) -> ObjectInspectorViewModel? {
        guard let structureType = entity.structureType else { return nil }

        let footprint = structureType.footprint
        var sections: [ObjectInspectorSection] = [
            ObjectInspectorSection(
                title: "Stats",
                rows: [
                    ObjectInspectorRow(label: "Entity ID", value: "#\(entity.id)"),
                    ObjectInspectorRow(
                        label: "Grid",
                        value: "(\(entity.position.x), \(entity.position.y), \(entity.position.z))"
                    ),
                    ObjectInspectorRow(label: "Health", value: "\(entity.health)/\(entity.maxHealth)"),
                    ObjectInspectorRow(label: "Footprint", value: "\(footprint.width)x\(footprint.height)"),
                    ObjectInspectorRow(label: "Path Blocking", value: structureType.blocksMovement ? "Yes" : "No")
                ]
            )
        ]

        var operationRows: [ObjectInspectorRow] = []
        operationRows.append(ObjectInspectorRow(label: "Power", value: powerLabel(for: structureType)))

        if structureType.powerDemand > 0 {
            let efficiency = world.economy.powerDemand == 0
                ? 1.0
                : min(1.0, Double(world.economy.powerAvailable) / Double(world.economy.powerDemand))
            operationRows.append(ObjectInspectorRow(label: "Efficiency", value: percentLabel(efficiency)))
        }

        if let recipeID = world.economy.activeRecipeByStructure[entity.id] {
            operationRows.append(ObjectInspectorRow(label: "Recipe", value: humanizedLabel(recipeID)))
            let progress = world.economy.productionProgressByStructure[entity.id, default: 0]
            if let duration = recipeDurationByID[recipeID], duration > 0 {
                let ratio = min(1.0, max(0, progress / duration))
                operationRows.append(
                    ObjectInspectorRow(
                        label: "Progress",
                        value: "\(percentLabel(ratio)) (\(decimalLabel(progress))/\(decimalLabel(duration))s)"
                    )
                )
            } else {
                operationRows.append(ObjectInspectorRow(label: "Progress", value: "\(decimalLabel(progress))s"))
            }
        }

        if let lastFireTick = world.combat.lastFireTickByTurret[entity.id] {
            operationRows.append(ObjectInspectorRow(label: "Last Shot Tick", value: "\(lastFireTick)"))
        }

        if !operationRows.isEmpty {
            sections.append(ObjectInspectorSection(title: "Operation", rows: operationRows))
        }

        let inputBuffer = world.economy.structureInputBuffers[entity.id, default: [:]]
        let outputBuffer = world.economy.structureOutputBuffers[entity.id, default: [:]]
        var bufferEntries = bufferRows(prefix: "Input", buffer: inputBuffer)
        bufferEntries.append(contentsOf: bufferRows(prefix: "Output", buffer: outputBuffer))
        if !bufferEntries.isEmpty {
            sections.append(ObjectInspectorSection(title: "Buffers", rows: bufferEntries))
        }

        if structureType == .conveyor {
            let io = world.economy.conveyorIOByEntity[entity.id] ?? ConveyorIOConfig.default(for: entity.rotation)
            var transportRows: [ObjectInspectorRow] = [
                ObjectInspectorRow(label: "Input From", value: io.inputDirection.rawValue.capitalized),
                ObjectInspectorRow(label: "Output To", value: io.outputDirection.rawValue.capitalized)
            ]
            if let payload = world.economy.conveyorPayloadByEntity[entity.id] {
                transportRows.append(ObjectInspectorRow(label: "Item", value: humanizedLabel(payload.itemID)))
                transportRows.append(ObjectInspectorRow(label: "Progress Ticks", value: "\(payload.progressTicks)"))
            }
            sections.append(
                ObjectInspectorSection(
                    title: "Transport",
                    rows: transportRows
                )
            )
        }

        if structureType == .turretMount {
            let ammoRows = ammoRows(for: entity.id, in: world)
            if !ammoRows.isEmpty {
                sections.append(ObjectInspectorSection(title: "Ammo", rows: ammoRows))
            }
        }

        return ObjectInspectorViewModel(
            entityID: entity.id,
            title: structureLabel(structureType),
            subtitle: "Structure",
            anchorPosition: entity.position,
            anchorHeightTiles: footprint.height,
            sections: sections
        )
    }

    private func enemyModel(for entity: Entity, in world: WorldState) -> ObjectInspectorViewModel {
        var rows: [ObjectInspectorRow] = [
            ObjectInspectorRow(label: "Entity ID", value: "#\(entity.id)"),
            ObjectInspectorRow(label: "Grid", value: "(\(entity.position.x), \(entity.position.y), \(entity.position.z))"),
            ObjectInspectorRow(label: "Health", value: "\(entity.health)/\(entity.maxHealth)")
        ]

        if let runtime = world.combat.enemies[entity.id] {
            rows.append(ObjectInspectorRow(label: "Archetype", value: runtime.archetype.rawValue.capitalized))
            rows.append(ObjectInspectorRow(label: "Move Every", value: "\(runtime.moveEveryTicks) ticks"))
            rows.append(ObjectInspectorRow(label: "Base Damage", value: "\(runtime.baseDamage)"))
            rows.append(ObjectInspectorRow(label: "Reward", value: "\(runtime.rewardCurrency) credits"))
        }

        return ObjectInspectorViewModel(
            entityID: entity.id,
            title: "Enemy",
            subtitle: "Hostile Unit",
            anchorPosition: entity.position,
            anchorHeightTiles: 1,
            sections: [ObjectInspectorSection(title: "Stats", rows: rows)]
        )
    }

    private func projectileModel(for entity: Entity, in world: WorldState) -> ObjectInspectorViewModel {
        var rows: [ObjectInspectorRow] = [
            ObjectInspectorRow(label: "Entity ID", value: "#\(entity.id)"),
            ObjectInspectorRow(label: "Grid", value: "(\(entity.position.x), \(entity.position.y), \(entity.position.z))")
        ]

        if let runtime = world.combat.projectiles[entity.id] {
            rows.append(ObjectInspectorRow(label: "Source Turret", value: "#\(runtime.sourceTurretID)"))
            rows.append(ObjectInspectorRow(label: "Target Enemy", value: "#\(runtime.targetEnemyID)"))
            rows.append(ObjectInspectorRow(label: "Damage", value: "\(runtime.damage)"))
            rows.append(ObjectInspectorRow(label: "Impact Tick", value: "\(runtime.impactTick)"))
            rows.append(ObjectInspectorRow(label: "Ticks Remaining", value: "\(max(0, runtime.impactTick - world.tick))"))
        }

        return ObjectInspectorViewModel(
            entityID: entity.id,
            title: "Projectile",
            subtitle: "In Flight",
            anchorPosition: entity.position,
            anchorHeightTiles: 1,
            sections: [ObjectInspectorSection(title: "Stats", rows: rows)]
        )
    }

    private func bufferRows(prefix: String, buffer: [ItemID: Int]) -> [ObjectInspectorRow] {
        buffer
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key < rhs.key
            }
            .map { itemID, quantity in
                ObjectInspectorRow(
                    id: "\(prefix)-\(itemID)",
                    label: "\(prefix) \(humanizedLabel(itemID))",
                    value: "\(quantity)"
                )
            }
    }

    private func ammoRows(for structureID: EntityID, in world: WorldState) -> [ObjectInspectorRow] {
        let ammoItemIDs: [ItemID] = ["ammo_light", "ammo_heavy", "ammo_plasma"]
        let local = world.economy.structureInputBuffers[structureID, default: [:]]

        return ammoItemIDs.compactMap { itemID in
            let localAmmo = local[itemID, default: 0]
            let globalAmmo = world.economy.inventories[itemID, default: 0]
            guard localAmmo > 0 || globalAmmo > 0 else { return nil }
            return ObjectInspectorRow(
                id: itemID,
                label: humanizedLabel(itemID),
                value: "Local \(localAmmo) • Global \(globalAmmo)"
            )
        }
    }

    private func powerLabel(for structureType: StructureType) -> String {
        let demand = structureType.powerDemand
        if demand < 0 {
            return "Generates \(abs(demand))"
        }
        if demand == 0 {
            return "None"
        }
        return "Uses \(demand)"
    }

    private func structureLabel(_ structureType: StructureType) -> String {
        switch structureType {
        case .hq:
            return "Headquarters"
        case .wall:
            return "Wall"
        case .turretMount:
            return "Turret Mount"
        case .miner:
            return "Miner"
        case .smelter:
            return "Smelter"
        case .assembler:
            return "Assembler"
        case .ammoModule:
            return "Ammo Module"
        case .powerPlant:
            return "Power Plant"
        case .conveyor:
            return "Conveyor"
        case .splitter:
            return "Splitter"
        case .merger:
            return "Merger"
        case .storage:
            return "Storage"
        }
    }

    private func humanizedLabel(_ value: String) -> String {
        value
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func percentLabel(_ ratio: Double) -> String {
        let percent = max(0, min(100, Int((ratio * 100).rounded())))
        return "\(percent)%"
    }

    private func decimalLabel(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

#if canImport(SwiftUI)
import SwiftUI

public struct ObjectInspectorPopup: View {
    public var model: ObjectInspectorViewModel
    public var onClose: (() -> Void)?

    public init(model: ObjectInspectorViewModel, onClose: (() -> Void)? = nil) {
        self.model = model
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title)
                        .font(.headline)
                    Text(model.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(model.sections) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(section.rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text(row.value)
                                .font(.caption.monospacedDigit())
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
    }
}
#endif
