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

    public func selectableEntity(at position: GridPosition) -> Entity? {
        let gridX = position.x
        let gridY = position.y

        for entity in all where entity.category == .structure {
            guard let structureType = entity.structureType else { continue }
            let occupiesCell = structureType.coveredCells(anchor: entity.position).contains(where: { covered in
                covered.x == gridX && covered.y == gridY
            })
            if occupiesCell {
                return entity
            }
        }

        for entity in all where entity.category == .enemy {
            if entity.position.x == gridX && entity.position.y == gridY {
                return entity
            }
        }

        for entity in all where entity.category == .projectile {
            if entity.position.x == gridX && entity.position.y == gridY {
                return entity
            }
        }

        return nil
    }

    @discardableResult
    public mutating func spawnStructure(
        _ structure: StructureType,
        at position: GridPosition,
        turretDefID: String? = nil,
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
