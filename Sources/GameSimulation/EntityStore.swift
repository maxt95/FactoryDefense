import Foundation

public struct EntityStore: Codable, Hashable, Sendable {
    public private(set) var entitiesByID: [EntityID: Entity]
    public private(set) var nextEntityID: EntityID

    public init(entitiesByID: [EntityID: Entity] = [:], nextEntityID: EntityID = 1) {
        self.entitiesByID = entitiesByID
        self.nextEntityID = nextEntityID
    }

    public var all: [Entity] {
        entitiesByID.values.sorted { $0.id < $1.id }
    }

    public func entity(id: EntityID) -> Entity? {
        entitiesByID[id]
    }

    public func structures(of type: StructureType) -> [Entity] {
        all.filter { $0.category == .structure && $0.structureType == type }
    }

    public func enemies() -> [Entity] {
        all.filter { $0.category == .enemy }
    }

    public func projectiles() -> [Entity] {
        all.filter { $0.category == .projectile }
    }

    public func selectableEntities(at position: GridPosition) -> [Entity] {
        let gridX = position.x
        let gridY = position.y

        let matchingStructures = all.filter { entity in
            guard entity.category == .structure, let structureType = entity.structureType else { return false }
            return structureType.coveredCells(anchor: entity.position).contains(where: { covered in
                covered.x == gridX && covered.y == gridY
            })
        }
        .sorted { lhs, rhs in
            let lhsPriority = structureSelectionPriority(lhs.structureType)
            let rhsPriority = structureSelectionPriority(rhs.structureType)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.id < rhs.id
        }

        let matchingEnemies = all.filter { entity in
            entity.category == .enemy && entity.position.x == gridX && entity.position.y == gridY
        }
        .sorted { $0.id < $1.id }

        let matchingProjectiles = all.filter { entity in
            entity.category == .projectile && entity.position.x == gridX && entity.position.y == gridY
        }
        .sorted { $0.id < $1.id }

        return matchingStructures + matchingEnemies + matchingProjectiles
    }

    public func selectableEntity(at position: GridPosition) -> Entity? {
        selectableEntities(at: position).first
    }

    private func structureSelectionPriority(_ structureType: StructureType?) -> Int {
        guard let structureType else { return 2 }
        switch structureType {
        case .turretMount:
            return 0
        case .wall:
            return 1
        default:
            return 2
        }
    }

    @discardableResult
    public mutating func spawnStructure(
        _ structure: StructureType,
        at position: GridPosition,
        rotation: Rotation = .north,
        turretDefID: String? = nil,
        hostWallID: EntityID? = nil,
        boundPatchID: Int? = nil,
        health: Int = 100,
        maxHealth: Int? = nil
    ) -> EntityID {
        let id = nextEntityID
        nextEntityID += 1
        let resolvedTurretDefID: String? = structure == .turretMount ? (turretDefID ?? "turret_mk1") : nil
        let resolvedMaxHealth = max(1, maxHealth ?? health)
        let resolvedHealth = min(max(1, health), resolvedMaxHealth)
        entitiesByID[id] = Entity(
            id: id,
            category: .structure,
            structureType: structure,
            turretDefID: resolvedTurretDefID,
            hostWallID: hostWallID,
            boundPatchID: boundPatchID,
            rotation: rotation,
            position: position,
            health: resolvedHealth,
            maxHealth: resolvedMaxHealth
        )
        return id
    }

    @discardableResult
    public mutating func spawnEnemy(at position: GridPosition, health: Int) -> EntityID {
        let id = nextEntityID
        nextEntityID += 1
        entitiesByID[id] = Entity(
            id: id,
            category: .enemy,
            position: position,
            health: health,
            maxHealth: health
        )
        return id
    }

    @discardableResult
    public mutating func spawnProjectile(at position: GridPosition) -> EntityID {
        let id = nextEntityID
        nextEntityID += 1
        entitiesByID[id] = Entity(
            id: id,
            category: .projectile,
            position: position,
            health: 1,
            maxHealth: 1
        )
        return id
    }

    public mutating func updatePosition(_ id: EntityID, to position: GridPosition) {
        guard var entity = entitiesByID[id] else { return }
        entity.position = position
        entitiesByID[id] = entity
    }

    public mutating func updateBoundPatchID(_ id: EntityID, to boundPatchID: Int?) {
        guard var entity = entitiesByID[id] else { return }
        entity.boundPatchID = boundPatchID
        entitiesByID[id] = entity
    }

    public mutating func rotateStructure(_ id: EntityID) {
        guard var entity = entitiesByID[id], entity.category == .structure else { return }
        entity.rotation = entity.rotation.rotatedClockwise()
        entitiesByID[id] = entity
    }

    public mutating func remove(_ id: EntityID) {
        entitiesByID.removeValue(forKey: id)
    }

    public mutating func damage(_ id: EntityID, amount: Int) {
        guard var entity = entitiesByID[id] else { return }
        entity.health = max(0, entity.health - amount)
        entitiesByID[id] = entity
        if entity.health == 0 {
            remove(id)
        }
    }

    public mutating func translateAll(byX dx: Int = 0, byY dy: Int = 0) {
        guard dx != 0 || dy != 0 else { return }
        for id in entitiesByID.keys {
            guard var entity = entitiesByID[id] else { continue }
            entity.position = entity.position.translated(byX: dx, byY: dy)
            entitiesByID[id] = entity
        }
    }
}
