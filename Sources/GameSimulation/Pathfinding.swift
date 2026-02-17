import Foundation

public struct GridTile: Codable, Hashable, Sendable {
    public var walkable: Bool
    public var elevation: Int
    public var isRamp: Bool

    public init(walkable: Bool, elevation: Int = 0, isRamp: Bool = false) {
        self.walkable = walkable
        self.elevation = elevation
        self.isRamp = isRamp
    }
}

public struct GridMap: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    private var tiles: [GridTile]

    public init(width: Int, height: Int, defaultTile: GridTile = GridTile(walkable: true)) {
        self.width = width
        self.height = height
        self.tiles = Array(repeating: defaultTile, count: width * height)
    }

    public func contains(_ position: GridPosition) -> Bool {
        position.x >= 0 && position.x < width && position.y >= 0 && position.y < height
    }

    public func tile(at position: GridPosition) -> GridTile? {
        guard contains(position) else { return nil }
        return tiles[index(for: position)]
    }

    public mutating func setTile(_ tile: GridTile, at position: GridPosition) {
        guard contains(position) else { return }
        tiles[index(for: position)] = tile
    }

    private func index(for position: GridPosition) -> Int {
        position.y * width + position.x
    }
}

public struct Pathfinder {
    public init() {}

    public func findPath(on map: GridMap, from start: GridPosition, to goal: GridPosition) -> [GridPosition]? {
        guard map.contains(start), map.contains(goal) else { return nil }
        guard let startTile = map.tile(at: start), startTile.walkable else { return nil }
        guard let goalTile = map.tile(at: goal), goalTile.walkable else { return nil }

        var openSet: Set<GridPosition> = [start]
        var cameFrom: [GridPosition: GridPosition] = [:]
        var gScore: [GridPosition: Int] = [start: 0]
        var fScore: [GridPosition: Int] = [start: heuristic(start, goal)]

        while !openSet.isEmpty {
            let current = openSet.min { lhs, rhs in
                let lhsF = fScore[lhs, default: .max]
                let rhsF = fScore[rhs, default: .max]
                if lhsF != rhsF { return lhsF < rhsF }

                let lhsG = gScore[lhs, default: .max]
                let rhsG = gScore[rhs, default: .max]
                if lhsG != rhsG { return lhsG < rhsG }

                if lhs.x != rhs.x { return lhs.x < rhs.x }
                if lhs.y != rhs.y { return lhs.y < rhs.y }
                return lhs.z < rhs.z
            }!
            if current == goal {
                return reconstructPath(cameFrom: cameFrom, current: current)
            }

            openSet.remove(current)
            for neighbor in neighbors(of: current, on: map) {
                let tentative = gScore[current, default: .max] + movementCost(from: current, to: neighbor, on: map)
                if tentative < gScore[neighbor, default: .max] {
                    cameFrom[neighbor] = current
                    gScore[neighbor] = tentative
                    fScore[neighbor] = tentative + heuristic(neighbor, goal)
                    openSet.insert(neighbor)
                }
            }
        }

        return nil
    }

    private func neighbors(of position: GridPosition, on map: GridMap) -> [GridPosition] {
        let offsets = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        return offsets.compactMap { dx, dy in
            let candidate = GridPosition(x: position.x + dx, y: position.y + dy)
            guard let tile = map.tile(at: candidate), tile.walkable else { return nil }
            return candidate
        }
    }

    private func movementCost(from a: GridPosition, to b: GridPosition, on map: GridMap) -> Int {
        _ = a
        _ = b
        _ = map
        return 1
    }

    private func heuristic(_ a: GridPosition, _ b: GridPosition) -> Int {
        abs(a.x - b.x) + abs(a.y - b.y)
    }

    private func reconstructPath(cameFrom: [GridPosition: GridPosition], current: GridPosition) -> [GridPosition] {
        var path: [GridPosition] = [current]
        var node = current
        while let parent = cameFrom[node] {
            path.append(parent)
            node = parent
        }
        return path.reversed()
    }
}
