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

    @discardableResult
    public mutating func spawnStructure(_ structure: StructureType, at position: GridPosition) -> EntityID {
        let id = nextEntityID
        nextEntityID += 1
        entitiesByID[id] = Entity(
            id: id,
            category: .structure,
            structureType: structure,
            position: position,
            health: 100,
            maxHealth: 100
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
}
