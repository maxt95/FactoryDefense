import Foundation
import GameContent

public struct TerrainTile: Codable, Hashable, Sendable {
    public var walkable: Bool
    public var elevation: Int
    public var isRamp: Bool
    public var isRestricted: Bool

    public init(walkable: Bool, elevation: Int = 0, isRamp: Bool = false, isRestricted: Bool = false) {
        self.walkable = walkable
        self.elevation = elevation
        self.isRamp = isRamp
        self.isRestricted = isRestricted
    }
}

public struct BoardCell: Codable, Hashable, Sendable {
    public var position: GridPosition
    public var terrain: TerrainTile
    public var occupiedEntityID: EntityID?
    public var occupiedStructure: StructureType?

    public init(position: GridPosition, terrain: TerrainTile, occupiedEntityID: EntityID?, occupiedStructure: StructureType?) {
        self.position = position
        self.terrain = terrain
        self.occupiedEntityID = occupiedEntityID
        self.occupiedStructure = occupiedStructure
    }
}

public struct RampCell: Codable, Hashable, Sendable {
    public var position: GridPosition
    public var elevation: Int

    public init(position: GridPosition, elevation: Int) {
        self.position = position
        self.elevation = elevation
    }
}

public struct BoardState: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    public var basePosition: GridPosition
    public var spawnEdgeX: Int
    public var spawnYMin: Int
    public var spawnYMax: Int
    public var blockedCells: [GridPosition]
    public var restrictedCells: [GridPosition]
    public var ramps: [RampCell]

    public init(
        width: Int,
        height: Int,
        basePosition: GridPosition,
        spawnEdgeX: Int,
        spawnYMin: Int,
        spawnYMax: Int,
        blockedCells: [GridPosition] = [],
        restrictedCells: [GridPosition] = [],
        ramps: [RampCell] = []
    ) {
        self.width = width
        self.height = height
        self.basePosition = basePosition
        self.spawnEdgeX = spawnEdgeX
        self.spawnYMin = spawnYMin
        self.spawnYMax = spawnYMax
        self.blockedCells = blockedCells
        self.restrictedCells = restrictedCells
        self.ramps = ramps
    }

    public init(definition: BoardDef) {
        self.width = definition.width
        self.height = definition.height
        self.basePosition = GridPosition(
            x: definition.basePosition.x,
            y: definition.basePosition.y,
            z: definition.basePosition.z
        )
        self.spawnEdgeX = definition.spawnEdgeX
        self.spawnYMin = definition.spawnYMin
        self.spawnYMax = definition.spawnYMax
        self.blockedCells = definition.blockedCells.map { GridPosition(x: $0.x, y: $0.y, z: $0.z) }
        self.restrictedCells = definition.restrictedCells.map { GridPosition(x: $0.x, y: $0.y, z: $0.z) }
        self.ramps = definition.ramps.map {
            RampCell(
                position: GridPosition(x: $0.position.x, y: $0.position.y, z: $0.position.z),
                elevation: $0.elevation
            )
        }
    }

    public static func bootstrap() -> BoardState {
        BoardState(definition: .starter)
    }

    public func contains(_ position: GridPosition) -> Bool {
        position.x >= 0 && position.x < width && position.y >= 0 && position.y < height
    }

    public func isBlocked(_ position: GridPosition) -> Bool {
        blockedCells.contains { $0.x == position.x && $0.y == position.y }
    }

    public func isRestricted(_ position: GridPosition) -> Bool {
        restrictedCells.contains { $0.x == position.x && $0.y == position.y }
    }

    public func elevation(at position: GridPosition) -> Int {
        for ramp in ramps where ramp.position.x == position.x && ramp.position.y == position.y {
            return ramp.elevation
        }
        return position.z
    }

    public func terrain(at position: GridPosition) -> TerrainTile? {
        guard contains(position) else { return nil }
        let blocked = isBlocked(position)
        let restricted = isRestricted(position)
        let elevation = elevation(at: position)
        let ramp = ramps.contains { $0.position.x == position.x && $0.position.y == position.y }
        return TerrainTile(
            walkable: !blocked,
            elevation: elevation,
            isRamp: ramp,
            isRestricted: restricted
        )
    }

    public func spawnPositions() -> [GridPosition] {
        guard spawnYMin <= spawnYMax else { return [] }
        return (spawnYMin...spawnYMax).map { y in
            GridPosition(x: spawnEdgeX, y: y, z: basePosition.z)
        }
    }

    public func cell(at position: GridPosition, entities: EntityStore) -> BoardCell? {
        guard let terrain = terrain(at: position) else { return nil }
        let occupant = entities.all.first(where: { entity in
            entity.position.x == position.x && entity.position.y == position.y && entity.category != .projectile
        })
        return BoardCell(
            position: GridPosition(x: position.x, y: position.y, z: terrain.elevation),
            terrain: terrain,
            occupiedEntityID: occupant?.id,
            occupiedStructure: occupant?.structureType
        )
    }
}

public extension StructureType {
    var blocksMovement: Bool {
        switch self {
        case .conveyor:
            return false
        case .wall, .turretMount, .miner, .smelter, .assembler, .ammoModule, .powerPlant, .storage:
            return true
        }
    }
}
