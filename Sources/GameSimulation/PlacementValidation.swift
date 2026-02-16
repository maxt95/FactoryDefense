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
        let coveredCells = structure.coveredCells(anchor: position)
        guard coveredCells.allSatisfy(world.board.contains(_:)) else { return .outOfBounds }
        guard !coveredCells.contains(where: world.board.isRestricted(_:)) else { return .restrictedZone }

        if hasOccupiedCell(in: coveredCells, entities: world.entities) {
            return .occupied
        }

        guard structure.blocksMovement else {
            return .ok
        }

        return blocksPath(coveredCells: coveredCells, atElevation: position.z, in: world) ? .blocksCriticalPath : .ok
    }

    private func hasOccupiedCell(in coveredCells: [GridPosition], entities: EntityStore) -> Bool {
        guard !coveredCells.isEmpty else { return false }
        let covered = Set(coveredCells.map { GridPosition(x: $0.x, y: $0.y, z: 0) })
        return entities.all.contains(where: { entity in
            guard entity.category != .projectile else { return false }
            if entity.category == .structure, let structureType = entity.structureType {
                return structureType.coveredCells(anchor: entity.position).contains(where: { occupiedCell in
                    covered.contains(GridPosition(x: occupiedCell.x, y: occupiedCell.y, z: 0))
                })
            }
            let position = GridPosition(x: entity.position.x, y: entity.position.y, z: 0)
            guard covered.contains(position) else { return false }
            return true
        })
    }

    private func blocksPath(coveredCells: [GridPosition], atElevation elevation: Int, in world: WorldState) -> Bool {
        let pendingBlockingCells = coveredCells.map { GridPosition(x: $0.x, y: $0.y, z: elevation) }
        let map = navigationMap(for: world, pendingBlockingCells: pendingBlockingCells)
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

    func navigationMap(for world: WorldState, pendingBlockingCells: [GridPosition] = []) -> GridMap {
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
            guard let structureType = entity.structureType, structureType.blocksMovement else { continue }
            for blockedCell in structureType.coveredCells(anchor: entity.position) {
                map.setTile(GridTile(walkable: false, elevation: entity.position.z), at: blockedCell)
            }
        }

        for pendingBlockingCell in pendingBlockingCells {
            map.setTile(GridTile(walkable: false, elevation: pendingBlockingCell.z), at: pendingBlockingCell)
        }

        let base = world.board.basePosition
        map.setTile(
            GridTile(walkable: true, elevation: world.board.elevation(at: base), isRamp: false),
            at: base
        )

        return map
    }
}
