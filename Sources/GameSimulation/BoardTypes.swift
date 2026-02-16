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

public enum BoardGrowthPolicy {
    public static let initialWidth = 96
    public static let initialHeight = 64
    public static let maxWidth = 512
    public static let maxHeight = 512
    public static let expansionTriggerTiles = 8
    public static let expansionStepTiles = 16
}

public struct BoardExpansionInsets: Codable, Hashable, Sendable {
    public var left: Int
    public var right: Int
    public var top: Int
    public var bottom: Int

    public init(left: Int = 0, right: Int = 0, top: Int = 0, bottom: Int = 0) {
        self.left = max(0, left)
        self.right = max(0, right)
        self.top = max(0, top)
        self.bottom = max(0, bottom)
    }

    public var isEmpty: Bool {
        left == 0 && right == 0 && top == 0 && bottom == 0
    }

    public var widthDelta: Int {
        left + right
    }

    public var heightDelta: Int {
        top + bottom
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

    public func plannedExpansion(
        for coveredCells: [GridPosition],
        triggerTiles: Int = BoardGrowthPolicy.expansionTriggerTiles,
        stepTiles: Int = BoardGrowthPolicy.expansionStepTiles,
        maxWidth: Int = BoardGrowthPolicy.maxWidth,
        maxHeight: Int = BoardGrowthPolicy.maxHeight
    ) -> BoardExpansionInsets? {
        guard !coveredCells.isEmpty else { return BoardExpansionInsets() }

        let minX = coveredCells.map(\.x).min() ?? 0
        let maxX = coveredCells.map(\.x).max() ?? 0
        let minY = coveredCells.map(\.y).min() ?? 0
        let maxY = coveredCells.map(\.y).max() ?? 0
        let minimumMargin = max(0, triggerTiles + 1)

        var insets = BoardExpansionInsets(
            left: max(0, minimumMargin - minX),
            right: max(0, minimumMargin - ((width - 1) - maxX)),
            top: max(0, minimumMargin - minY),
            bottom: max(0, minimumMargin - ((height - 1) - maxY))
        )

        insets.left = roundedUp(insets.left, toMultipleOf: stepTiles)
        insets.right = roundedUp(insets.right, toMultipleOf: stepTiles)
        insets.top = roundedUp(insets.top, toMultipleOf: stepTiles)
        insets.bottom = roundedUp(insets.bottom, toMultipleOf: stepTiles)

        guard width + insets.widthDelta <= maxWidth else { return nil }
        guard height + insets.heightDelta <= maxHeight else { return nil }
        return insets
    }

    public mutating func applyExpansion(_ insets: BoardExpansionInsets) {
        guard !insets.isEmpty else { return }

        width += insets.widthDelta
        height += insets.heightDelta

        let shiftX = insets.left
        let shiftY = insets.top
        guard shiftX != 0 || shiftY != 0 else { return }

        basePosition = basePosition.translated(byX: shiftX, byY: shiftY)
        spawnEdgeX += shiftX
        spawnYMin += shiftY
        spawnYMax += shiftY
        blockedCells = blockedCells.map { $0.translated(byX: shiftX, byY: shiftY) }
        restrictedCells = restrictedCells.map { $0.translated(byX: shiftX, byY: shiftY) }
        ramps = ramps.map { RampCell(position: $0.position.translated(byX: shiftX, byY: shiftY), elevation: $0.elevation) }
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
        guard width > 0 && height > 0 else { return [] }

        var positions: [GridPosition] = []
        positions.reserveCapacity(max(1, (width * 2) + (height * 2) - 4))

        if height >= 1 {
            for x in 0..<width {
                positions.append(GridPosition(x: x, y: 0, z: basePosition.z))
            }
        }

        if width >= 1, height >= 2 {
            for y in 1..<height {
                positions.append(GridPosition(x: width - 1, y: y, z: basePosition.z))
            }
        }

        if height >= 2, width >= 2 {
            for x in stride(from: width - 2, through: 0, by: -1) {
                positions.append(GridPosition(x: x, y: height - 1, z: basePosition.z))
            }
        }

        if width >= 2, height >= 3 {
            for y in stride(from: height - 2, through: 1, by: -1) {
                positions.append(GridPosition(x: 0, y: y, z: basePosition.z))
            }
        }

        return positions
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

public extension WorldState {
    mutating func applyBoardExpansion(_ insets: BoardExpansionInsets) {
        guard !insets.isEmpty else { return }
        board.applyExpansion(insets)

        let shiftX = insets.left
        let shiftY = insets.top
        guard shiftX != 0 || shiftY != 0 else { return }

        entities.translateAll(byX: shiftX, byY: shiftY)
        orePatches = orePatches.map { patch in
            var translated = patch
            translated.position = translated.position.translated(byX: shiftX, byY: shiftY)
            return translated
        }
        combat.basePosition = combat.basePosition.translated(byX: shiftX, byY: shiftY)
        combat.spawnEdgeX += shiftX
        combat.spawnYMin += shiftY
        combat.spawnYMax += shiftY
    }
}

private func roundedUp(_ value: Int, toMultipleOf step: Int) -> Int {
    guard value > 0 else { return 0 }
    guard step > 1 else { return value }
    let remainder = value % step
    return remainder == 0 ? value : value + step - remainder
}

public extension StructureType {
    var blocksMovement: Bool {
        switch self {
        case .conveyor, .turretMount:
            return false
        case .hq, .wall, .miner, .smelter, .assembler, .ammoModule, .powerPlant, .storage:
            return true
        }
    }
}
