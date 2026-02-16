import Foundation

public enum PlacementResult: Int, Codable, Hashable, Sendable {
    case ok = 0
    case occupied = 1
    case outOfBounds = 2
    case blocksCriticalPath = 3
    case restrictedZone = 4
    case insufficientResources = 5
    case invalidMinerPlacement = 6
    case invalidTurretMountPlacement = 7
    case invalidRemoval = 8
}

public struct PlacementValidator {
    public init() {}

    public func canPlace(
        _ structure: StructureType,
        at position: GridPosition,
        targetPatchID: Int? = nil,
        in world: WorldState
    ) -> PlacementResult {
        let coveredCells = structure.coveredCells(anchor: position)
        guard coveredCells.allSatisfy(world.board.contains(_:)) else { return .outOfBounds }
        guard !coveredCells.contains(where: world.board.isRestricted(_:)) else { return .restrictedZone }

        if structure == .turretMount {
            guard resolvedTurretHostWallID(forTurretAt: position, in: world.entities) != nil else {
                return .invalidTurretMountPlacement
            }
        } else if hasOccupiedCell(in: coveredCells, entities: world.entities) {
            return .occupied
        }

        if structure == .miner,
           resolvedMinerPatchID(forMinerAt: position, targetPatchID: targetPatchID, in: world) == nil {
            return .invalidMinerPlacement
        }

        guard structure.blocksMovement else {
            return .ok
        }

        return blocksPath(coveredCells: coveredCells, atElevation: position.z, in: world) ? .blocksCriticalPath : .ok
    }

    public func resolvedTurretHostWallID(forTurretAt turretPosition: GridPosition, in entities: EntityStore) -> EntityID? {
        let normalized = GridPosition(x: turretPosition.x, y: turretPosition.y, z: 0)

        let wallID = entities.all
            .filter { $0.category == .structure && $0.structureType == .wall }
            .first(where: { wall in
                guard let structureType = wall.structureType else { return false }
                return structureType.coveredCells(anchor: wall.position).contains(where: {
                    GridPosition(x: $0.x, y: $0.y, z: 0) == normalized
                })
            })?.id

        guard let wallID else { return nil }

        let hasExistingTurret = entities.all.contains { entity in
            entity.category == .structure
                && entity.structureType == .turretMount
                && GridPosition(x: entity.position.x, y: entity.position.y, z: 0) == normalized
        }
        return hasExistingTurret ? nil : wallID
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

        for spawn in spawns where spawn != base {
            guard let spawnTile = map.tile(at: spawn), spawnTile.walkable else {
                continue
            }
            if pathfinder.findPath(on: map, from: spawn, to: base) != nil {
                return false
            }
        }

        return true
    }

    public func resolvedMinerPatchID(
        forMinerAt minerPosition: GridPosition,
        targetPatchID: Int?,
        in world: WorldState
    ) -> Int? {
        if let targetPatchID {
            guard let patch = world.orePatches.first(where: { $0.id == targetPatchID }) else {
                return nil
            }
            guard patch.boundMinerID == nil else { return nil }
            guard !patch.isExhausted else { return nil }
            return isAdjacent(minerPosition, patch.position) ? patch.id : nil
        }

        let candidates = world.orePatches
            .filter { patch in
                patch.boundMinerID == nil && !patch.isExhausted && isAdjacent(minerPosition, patch.position)
            }
            .map(\.id)
            .sorted()
        return candidates.first
    }

    private func isAdjacent(_ lhs: GridPosition, _ rhs: GridPosition) -> Bool {
        abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y) == 1
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
