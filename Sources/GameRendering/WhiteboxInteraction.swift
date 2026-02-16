import CoreGraphics
import Foundation
import GameSimulation
import simd

public struct WhiteboxCameraState: Codable, Hashable, Sendable {
    public var pan: SIMD2<Float>
    public var zoom: Float

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
        zoom = max(0.45, min(2.8, zoom * scale))
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
    case storage = 9

    public init(structureType: StructureType) {
        switch structureType {
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
        case .storage:
            self = .storage
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
    public var x: Int32
    public var y: Int32
    public var category: UInt32

    public init(x: Int32, y: Int32, category: UInt32) {
        self.x = x
        self.y = y
        self.category = category
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
        entities.reserveCapacity(world.entities.all.count)

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
                entities.append(
                    WhiteboxEntityMarker(
                        x: Int32(entity.position.x),
                        y: Int32(entity.position.y),
                        category: WhiteboxEntityCategory.enemy.rawValue
                    )
                )
            case .projectile:
                entities.append(
                    WhiteboxEntityMarker(
                        x: Int32(entity.position.x),
                        y: Int32(entity.position.y),
                        category: WhiteboxEntityCategory.projectile.rawValue
                    )
                )
            }
        }

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
