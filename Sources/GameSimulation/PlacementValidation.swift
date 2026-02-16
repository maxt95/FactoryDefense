import Foundation

public enum PlacementResult: Int, Codable, Hashable, Sendable {
    case ok = 0
    case occupied = 1
    case outOfBounds = 2
    case blocksCriticalPath = 3
    case restrictedZone = 4
}

public struct PlacementValidator {
    public init() {}

    public func canPlace(_ structure: StructureType, at position: GridPosition, in world: WorldState) -> PlacementResult {
        guard world.board.contains(position) else { return .outOfBounds }
        guard !world.board.isRestricted(position) else { return .restrictedZone }

        if isOccupied(position, entities: world.entities) {
            return .occupied
        }

        guard structure.blocksMovement else {
            return .ok
        }

        return blocksPath(position: position, in: world) ? .blocksCriticalPath : .ok
    }

    private func isOccupied(_ position: GridPosition, entities: EntityStore) -> Bool {
        entities.all.contains(where: { entity in
            entity.position.x == position.x && entity.position.y == position.y && entity.category != .projectile
        })
    }

    private func blocksPath(position: GridPosition, in world: WorldState) -> Bool {
        let map = navigationMap(for: world, pendingBlockingPosition: position)
        let pathfinder = Pathfinder()

        let base = GridPosition(x: world.board.basePosition.x, y: world.board.basePosition.y)
        guard let baseTile = map.tile(at: base), baseTile.walkable else {
            return true
        }

        let spawns = world.board.spawnPositions()
        guard !spawns.isEmpty else { return true }

        for spawn in spawns {
            guard let spawnTile = map.tile(at: spawn), spawnTile.walkable else {
                continue
            }
            if pathfinder.findPath(on: map, from: spawn, to: base) != nil {
                return false
            }
        }

        return true
    }

    func navigationMap(for world: WorldState, pendingBlockingPosition: GridPosition? = nil) -> GridMap {
        var map = GridMap(width: world.board.width, height: world.board.height)

        for y in 0..<world.board.height {
            for x in 0..<world.board.width {
                let position = GridPosition(x: x, y: y)
                guard let terrain = world.board.terrain(at: position) else { continue }
                map.setTile(
                    GridTile(walkable: terrain.walkable, elevation: terrain.elevation, isRamp: terrain.isRamp),
                    at: position
                )
            }
        }

        for entity in world.entities.all where entity.category == .structure {
            guard entity.structureType?.blocksMovement == true else { continue }
            map.setTile(GridTile(walkable: false, elevation: entity.position.z), at: entity.position)
        }

        if let pendingBlockingPosition {
            map.setTile(GridTile(walkable: false, elevation: pendingBlockingPosition.z), at: pendingBlockingPosition)
        }

        let base = world.board.basePosition
        map.setTile(
            GridTile(walkable: true, elevation: world.board.elevation(at: base), isRamp: false),
            at: base
        )

        return map
    }
}
