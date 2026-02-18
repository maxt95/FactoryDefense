import CoreGraphics
import Foundation
import GameSimulation
import simd

public struct WhiteboxCameraState: Codable, Hashable, Sendable {
    public var pan: SIMD2<Float>
    public var zoom: Float

    public static let minimumZoom: Float = 0.45
    public static let maximumZoom: Float = 2.8
    public static let defaultSafePerimeterTiles: Float = 4

    private static let baseTileWidth: Float = 34
    private static let baseTileHeight: Float = 22
    private static let verticalBoardOffset: Float = 0.5

    public init(pan: SIMD2<Float> = SIMD2<Float>(0, 0), zoom: Float = 1.0) {
        self.pan = pan
        self.zoom = zoom
    }

    public mutating func panBy(deltaX: Float, deltaY: Float) {
        pan.x += deltaX
        pan.y += deltaY
    }

    public mutating func zoomBy(scale: Float) {
        guard scale.isFinite, scale > 0 else { return }
        zoom = max(Self.minimumZoom, min(Self.maximumZoom, zoom * scale))
    }

    public mutating func zoomBy(
        scale: Float,
        around anchor: CGPoint,
        viewport: CGSize,
        board: BoardState,
        safePerimeterTiles: Float = WhiteboxCameraState.defaultSafePerimeterTiles
    ) {
        guard scale.isFinite, scale > 0 else { return }
        guard viewport.width > 0, viewport.height > 0 else { return }
        guard anchor.x.isFinite, anchor.y.isFinite else { return }

        let viewWidth = Float(max(1, viewport.width))
        let viewHeight = Float(max(1, viewport.height))
        let oldZoom = max(0.001, zoom)
        let oldTileWidth = Self.baseTileWidth * oldZoom
        let oldTileHeight = Self.baseTileHeight * oldZoom
        let oldBoardPixelWidth = Float(board.width) * oldTileWidth
        let oldBoardPixelHeight = Float(board.height) * oldTileHeight
        let oldOriginBaseX = (viewWidth - oldBoardPixelWidth) * 0.5
        let oldOriginBaseY = (viewHeight * Self.verticalBoardOffset) - (oldBoardPixelHeight * 0.5)
        let oldOriginX = oldOriginBaseX + pan.x
        let oldOriginY = oldOriginBaseY + pan.y
        let localX = (Float(anchor.x) - oldOriginX) / oldTileWidth
        let localY = (Float(anchor.y) - oldOriginY) / oldTileHeight

        let computedMinimumZoom = minimumZoomToHideBoardEdge(
            viewport: viewport,
            board: board,
            safePerimeterTiles: safePerimeterTiles
        )
        let minimumZoom = min(Self.maximumZoom, max(Self.minimumZoom, computedMinimumZoom))
        zoom = max(minimumZoom, min(Self.maximumZoom, zoom * scale))

        let newZoom = max(0.001, zoom)
        let newTileWidth = Self.baseTileWidth * newZoom
        let newTileHeight = Self.baseTileHeight * newZoom
        let newBoardPixelWidth = Float(board.width) * newTileWidth
        let newBoardPixelHeight = Float(board.height) * newTileHeight
        let newOriginBaseX = (viewWidth - newBoardPixelWidth) * 0.5
        let newOriginBaseY = (viewHeight * Self.verticalBoardOffset) - (newBoardPixelHeight * 0.5)

        pan.x = Float(anchor.x) - (newOriginBaseX + (localX * newTileWidth))
        pan.y = Float(anchor.y) - (newOriginBaseY + (localY * newTileHeight))
        clampToSafePerimeter(viewport: viewport, board: board, safePerimeterTiles: safePerimeterTiles)
    }

    public func minimumZoomToHideBoardEdge(
        viewport: CGSize,
        board: BoardState,
        safePerimeterTiles: Float = WhiteboxCameraState.defaultSafePerimeterTiles
    ) -> Float {
        let safeTiles = max(0, safePerimeterTiles)
        let horizontalSpanTiles = max(1, Float(board.width) - (safeTiles * 2))
        let verticalSpanTiles = max(1, Float(board.height) - (safeTiles * 2))
        let viewportWidth = Float(max(1, viewport.width))
        let viewportHeight = Float(max(1, viewport.height))
        let requiredX = viewportWidth / (horizontalSpanTiles * Self.baseTileWidth)
        let requiredY = viewportHeight / (verticalSpanTiles * Self.baseTileHeight)
        return max(Self.minimumZoom, max(requiredX, requiredY))
    }

    public mutating func compensateForBoardGrowth(
        deltaWidth: Int,
        deltaHeight: Int,
        deltaBaseX: Int,
        deltaBaseY: Int
    ) {
        let clampedZoom = max(0.001, zoom)
        let tileWidth = Self.baseTileWidth * clampedZoom
        let tileHeight = Self.baseTileHeight * clampedZoom
        pan.x += (Float(deltaWidth - (2 * deltaBaseX)) * tileWidth) * 0.5
        pan.y += (Float(deltaHeight - (2 * deltaBaseY)) * tileHeight) * 0.5
    }

    public mutating func clampToSafePerimeter(
        viewport: CGSize,
        board: BoardState,
        safePerimeterTiles: Float = WhiteboxCameraState.defaultSafePerimeterTiles
    ) {
        guard viewport.width > 0, viewport.height > 0 else { return }

        let computedMinimumZoom = minimumZoomToHideBoardEdge(
            viewport: viewport,
            board: board,
            safePerimeterTiles: safePerimeterTiles
        )
        let minimumZoom = min(Self.maximumZoom, max(Self.minimumZoom, computedMinimumZoom))
        zoom = max(minimumZoom, min(Self.maximumZoom, zoom))

        let safeTiles = max(0, safePerimeterTiles)
        let tileWidth = Self.baseTileWidth * zoom
        let tileHeight = Self.baseTileHeight * zoom
        let boardPixelWidth = Float(board.width) * tileWidth
        let boardPixelHeight = Float(board.height) * tileHeight
        let safeMarginX = safeTiles * tileWidth
        let safeMarginY = safeTiles * tileHeight
        let viewWidth = Float(viewport.width)
        let viewHeight = Float(viewport.height)

        let originBaseX = (viewWidth - boardPixelWidth) * 0.5
        let originBaseY = (viewHeight * Self.verticalBoardOffset) - (boardPixelHeight * 0.5)

        let minOriginX = viewWidth + safeMarginX - boardPixelWidth
        let maxOriginX = -safeMarginX
        var originX = originBaseX + pan.x
        if minOriginX > maxOriginX {
            originX = (minOriginX + maxOriginX) * 0.5
        } else {
            originX = min(max(originX, minOriginX), maxOriginX)
        }

        let minOriginY = viewHeight + safeMarginY - boardPixelHeight
        let maxOriginY = -safeMarginY
        var originY = originBaseY + pan.y
        if minOriginY > maxOriginY {
            originY = (minOriginY + maxOriginY) * 0.5
        } else {
            originY = min(max(originY, minOriginY), maxOriginY)
        }

        pan.x = originX - originBaseX
        pan.y = originY - originBaseY
    }
}

public struct WhiteboxSceneSummary: Hashable, Sendable {
    public var boardCellCount: Int
    public var blockedCellCount: Int
    public var restrictedCellCount: Int
    public var rampCount: Int
    public var structureCount: Int
    public var enemyCount: Int
    public var projectileCount: Int

    public init(
        boardCellCount: Int,
        blockedCellCount: Int,
        restrictedCellCount: Int,
        rampCount: Int,
        structureCount: Int,
        enemyCount: Int,
        projectileCount: Int
    ) {
        self.boardCellCount = boardCellCount
        self.blockedCellCount = blockedCellCount
        self.restrictedCellCount = restrictedCellCount
        self.rampCount = rampCount
        self.structureCount = structureCount
        self.enemyCount = enemyCount
        self.projectileCount = projectileCount
    }
}

public enum WhiteboxEntityCategory: UInt32, Sendable {
    case structure = 1
    case enemy = 2
    case projectile = 3
    case resourceNode = 4
    case player = 5
}

public enum WhiteboxStructureTypeID: UInt32, Sendable {
    case wall = 1
    case turretMount = 2
    case miner = 3
    case smelter = 4
    case assembler = 5
    case ammoModule = 6
    case powerPlant = 7
    case conveyor = 8
    case splitter = 9
    case merger = 10
    case storage = 11
    case hq = 12

    public init(structureType: StructureType) {
        switch structureType {
        case .hq:
            self = .hq
        case .wall:
            self = .wall
        case .turretMount:
            self = .turretMount
        case .miner:
            self = .miner
        case .smelter:
            self = .smelter
        case .assembler:
            self = .assembler
        case .ammoModule:
            self = .ammoModule
        case .powerPlant:
            self = .powerPlant
        case .conveyor:
            self = .conveyor
        case .splitter:
            self = .splitter
        case .merger:
            self = .merger
        case .storage:
            self = .storage
        }
    }
}

public enum WhiteboxEnemyTypeID: UInt32, Sendable {
    case swarmling = 1
    case droneScout = 2
    case raider = 3
    case breacher = 4
    case artilleryBug = 5
    case overseer = 6

    init(archetype: EnemyArchetype) {
        switch archetype {
        case .swarmling:
            self = .swarmling
        case .droneScout:
            self = .droneScout
        case .raider:
            self = .raider
        case .breacher:
            self = .breacher
        case .overseer:
            self = .overseer
        }
    }
}

public enum WhiteboxProjectileTypeID: UInt32, Sendable {
    case lightBallistic = 1
    case heavyBallistic = 2
    case plasma = 3
}

public enum WhiteboxResourceTypeID: UInt32, Sendable {
    case iron = 1
    case copper = 2
    case coal = 3
    case unknown = 255

    init(oreType: String) {
        switch oreType {
        case "ore_iron":
            self = .iron
        case "ore_copper":
            self = .copper
        case "ore_coal":
            self = .coal
        default:
            self = .unknown
        }
    }

    var oreType: String {
        switch self {
        case .iron:
            return "ore_iron"
        case .copper:
            return "ore_copper"
        case .coal:
            return "ore_coal"
        case .unknown:
            return "ore_unknown"
        }
    }
}

public struct WhiteboxPoint: Hashable, Sendable {
    public var x: Int32
    public var y: Int32

    public init(x: Int32, y: Int32) {
        self.x = x
        self.y = y
    }
}

public struct WhiteboxRampPoint: Hashable, Sendable {
    public var x: Int32
    public var y: Int32
    public var elevation: Int32

    public init(x: Int32, y: Int32, elevation: Int32) {
        self.x = x
        self.y = y
        self.elevation = elevation
    }
}

public struct WhiteboxEntityMarker: Hashable, Sendable {
    public var id: Int64
    public var x: Int32
    public var y: Int32
    public var category: UInt32
    public var subtypeRaw: UInt32

    public init(id: Int64, x: Int32, y: Int32, category: UInt32, subtypeRaw: UInt32 = 0) {
        self.id = id
        self.x = x
        self.y = y
        self.category = category
        self.subtypeRaw = subtypeRaw
    }
}

public struct WhiteboxStructureMarker: Hashable, Sendable {
    public var anchorX: Int32
    public var anchorY: Int32
    public var typeRaw: UInt32
    public var footprintWidth: Int32
    public var footprintHeight: Int32

    public init(anchorX: Int32, anchorY: Int32, typeRaw: UInt32, footprintWidth: Int32, footprintHeight: Int32) {
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.typeRaw = typeRaw
        self.footprintWidth = footprintWidth
        self.footprintHeight = footprintHeight
    }
}

public struct WhiteboxSceneData: Sendable {
    public var summary: WhiteboxSceneSummary
    public var blockedCells: [WhiteboxPoint]
    public var restrictedCells: [WhiteboxPoint]
    public var ramps: [WhiteboxRampPoint]
    public var structures: [WhiteboxStructureMarker]
    public var entities: [WhiteboxEntityMarker]

    public init(
        summary: WhiteboxSceneSummary,
        blockedCells: [WhiteboxPoint],
        restrictedCells: [WhiteboxPoint],
        ramps: [WhiteboxRampPoint],
        structures: [WhiteboxStructureMarker],
        entities: [WhiteboxEntityMarker]
    ) {
        self.summary = summary
        self.blockedCells = blockedCells
        self.restrictedCells = restrictedCells
        self.ramps = ramps
        self.structures = structures
        self.entities = entities
    }
}

public struct WhiteboxSceneBuilder {
    public init() {}

    public func build(from world: WorldState) -> WhiteboxSceneData {
        let blockedCells = world.board.blockedCells
            .map { WhiteboxPoint(x: Int32($0.x), y: Int32($0.y)) }
            .sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        let restrictedCells = world.board.restrictedCells
            .map { WhiteboxPoint(x: Int32($0.x), y: Int32($0.y)) }
            .sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        let ramps = world.board.ramps
            .map { WhiteboxRampPoint(x: Int32($0.position.x), y: Int32($0.position.y), elevation: Int32($0.elevation)) }
            .sorted { ($0.x, $0.y, $0.elevation) < ($1.x, $1.y, $1.elevation) }

        var structures: [WhiteboxStructureMarker] = []
        var entities: [WhiteboxEntityMarker] = []
        structures.reserveCapacity(world.entities.all.count)
        entities.reserveCapacity(world.entities.all.count + world.orePatches.count)

        for entity in world.entities.all {
            switch entity.category {
            case .structure:
                guard let structureType = entity.structureType else { continue }
                let structureID = WhiteboxStructureTypeID(structureType: structureType)
                let footprint = structureType.footprint
                structures.append(
                    WhiteboxStructureMarker(
                        anchorX: Int32(entity.position.x),
                        anchorY: Int32(entity.position.y),
                        typeRaw: structureID.rawValue,
                        footprintWidth: Int32(footprint.width),
                        footprintHeight: Int32(footprint.height)
                    )
                )
            case .enemy:
                let subtypeRaw = whiteboxEnemyTypeRaw(entityID: entity.id, world: world)
                entities.append(
                    WhiteboxEntityMarker(
                        id: Int64(entity.id),
                        x: Int32(entity.position.x),
                        y: Int32(entity.position.y),
                        category: WhiteboxEntityCategory.enemy.rawValue,
                        subtypeRaw: subtypeRaw
                    )
                )
            case .projectile:
                let subtypeRaw = whiteboxProjectileTypeRaw(entityID: entity.id, world: world)
                entities.append(
                    WhiteboxEntityMarker(
                        id: Int64(entity.id),
                        x: Int32(entity.position.x),
                        y: Int32(entity.position.y),
                        category: WhiteboxEntityCategory.projectile.rawValue,
                        subtypeRaw: subtypeRaw
                    )
                )
            case .player:
                entities.append(
                    WhiteboxEntityMarker(
                        id: Int64(entity.id),
                        x: Int32(entity.position.x),
                        y: Int32(entity.position.y),
                        category: WhiteboxEntityCategory.player.rawValue,
                        subtypeRaw: 0
                    )
                )
            }
        }

        let oreMarkers = world.orePatches
            .sorted { lhs, rhs in
                if lhs.position.x != rhs.position.x {
                    return lhs.position.x < rhs.position.x
                }
                if lhs.position.y != rhs.position.y {
                    return lhs.position.y < rhs.position.y
                }
                return lhs.id < rhs.id
            }
            .map { patch in
                WhiteboxEntityMarker(
                    id: Int64(-patch.id),
                    x: Int32(patch.position.x),
                    y: Int32(patch.position.y),
                    category: WhiteboxEntityCategory.resourceNode.rawValue,
                    subtypeRaw: WhiteboxResourceTypeID(oreType: patch.oreType).rawValue
                )
            }
        entities.append(contentsOf: oreMarkers)

        let summary = WhiteboxSceneSummary(
            boardCellCount: world.board.width * world.board.height,
            blockedCellCount: blockedCells.count,
            restrictedCellCount: restrictedCells.count,
            rampCount: ramps.count,
            structureCount: structures.count,
            enemyCount: entities.filter { $0.category == WhiteboxEntityCategory.enemy.rawValue }.count,
            projectileCount: entities.filter { $0.category == WhiteboxEntityCategory.projectile.rawValue }.count
        )

        return WhiteboxSceneData(
            summary: summary,
            blockedCells: blockedCells,
            restrictedCells: restrictedCells,
            ramps: ramps,
            structures: structures,
            entities: entities
        )
    }

    private func whiteboxEnemyTypeRaw(entityID: EntityID, world: WorldState) -> UInt32 {
        guard let runtime = world.combat.enemies[entityID] else {
            return WhiteboxEnemyTypeID.swarmling.rawValue
        }
        return WhiteboxEnemyTypeID(archetype: runtime.archetype).rawValue
    }

    private func whiteboxProjectileTypeRaw(entityID: EntityID, world: WorldState) -> UInt32 {
        guard let runtime = world.combat.projectiles[entityID] else {
            return WhiteboxProjectileTypeID.lightBallistic.rawValue
        }

        if let turret = world.entities.entity(id: runtime.sourceTurretID),
           let turretDefID = turret.turretDefID {
            switch turretDefID {
            case "turret_mk2":
                return WhiteboxProjectileTypeID.heavyBallistic.rawValue
            case "plasma_sentinel":
                return WhiteboxProjectileTypeID.plasma.rawValue
            default:
                return WhiteboxProjectileTypeID.lightBallistic.rawValue
            }
        }

        if runtime.damage >= 40 {
            return WhiteboxProjectileTypeID.plasma.rawValue
        }
        if runtime.damage >= 20 {
            return WhiteboxProjectileTypeID.heavyBallistic.rawValue
        }
        return WhiteboxProjectileTypeID.lightBallistic.rawValue
    }
}

public struct WhiteboxPicker {
    public init() {}

    private static let baseTileWidth: CGFloat = 34
    private static let baseTileHeight: CGFloat = 22
    private static let verticalBoardOffset: CGFloat = 0.50

    private func boardOrigin(
        viewport: CGSize,
        boardWidth: Int,
        boardHeight: Int,
        camera: WhiteboxCameraState
    ) -> CGPoint {
        let zoom = max(0.001, CGFloat(camera.zoom))
        let tileWidth = WhiteboxPicker.baseTileWidth * zoom
        let tileHeight = WhiteboxPicker.baseTileHeight * zoom
        let boardPixelSize = CGSize(
            width: CGFloat(boardWidth) * tileWidth,
            height: CGFloat(boardHeight) * tileHeight
        )
        return CGPoint(
            x: (viewport.width - boardPixelSize.width) * 0.5 + CGFloat(camera.pan.x),
            y: viewport.height * WhiteboxPicker.verticalBoardOffset - boardPixelSize.height * 0.5 + CGFloat(camera.pan.y)
        )
    }

    public func screenPosition(
        for grid: GridPosition,
        viewport: CGSize,
        camera: WhiteboxCameraState,
        board: BoardState
    ) -> CGPoint {
        let zoom = max(0.001, CGFloat(camera.zoom))
        let tileWidth = WhiteboxPicker.baseTileWidth * zoom
        let tileHeight = WhiteboxPicker.baseTileHeight * zoom
        let origin = boardOrigin(
            viewport: viewport,
            boardWidth: board.width,
            boardHeight: board.height,
            camera: camera
        )

        return CGPoint(
            x: origin.x + CGFloat(grid.x) * tileWidth + (tileWidth * 0.5),
            y: origin.y + CGFloat(grid.y) * tileHeight + (tileHeight * 0.5)
        )
    }

    public func gridPosition(
        at point: CGPoint,
        viewport: CGSize,
        board: BoardState,
        camera: WhiteboxCameraState
    ) -> GridPosition? {
        let zoom = max(0.001, CGFloat(camera.zoom))
        let tileWidth = WhiteboxPicker.baseTileWidth * zoom
        let tileHeight = WhiteboxPicker.baseTileHeight * zoom
        guard tileWidth > 0.0001, tileHeight > 0.0001 else { return nil }

        let origin = boardOrigin(
            viewport: viewport,
            boardWidth: board.width,
            boardHeight: board.height,
            camera: camera
        )
        let boardPixelSize = CGSize(
            width: CGFloat(board.width) * tileWidth,
            height: CGFloat(board.height) * tileHeight
        )

        let localX = point.x - origin.x
        let localY = point.y - origin.y
        guard localX >= 0, localY >= 0, localX < boardPixelSize.width, localY < boardPixelSize.height else {
            return nil
        }

        let selected = GridPosition(
            x: Int(floor(localX / tileWidth)),
            y: Int(floor(localY / tileHeight))
        )

        guard board.contains(selected) else { return nil }
        return GridPosition(
            x: selected.x,
            y: selected.y,
            z: board.elevation(at: selected)
        )
    }
}
