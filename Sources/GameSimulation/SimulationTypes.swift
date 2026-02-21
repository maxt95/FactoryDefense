import Foundation
import GameContent

public typealias EntityID = Int
public typealias RunSeed = UInt64

public enum Difficulty: String, Codable, CaseIterable, Sendable {
    case easy
    case normal
    case hard
}

public enum RunPhase: String, Codable, Sendable {
    case initializing
    case gracePeriod
    case playing
    case gameOver
}

public struct PlayerID: Codable, Hashable, Sendable, Comparable {
    public var rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: PlayerID, rhs: PlayerID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct GridPosition: Codable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var z: Int

    public init(x: Int, y: Int, z: Int = 0) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = GridPosition(x: 0, y: 0, z: 0)

    public func manhattanDistance(to other: GridPosition) -> Int {
        abs(x - other.x) + abs(y - other.y)
    }

    public func translated(byX dx: Int = 0, byY dy: Int = 0, byZ dz: Int = 0) -> GridPosition {
        GridPosition(x: x + dx, y: y + dy, z: z + dz)
    }

    public func translated(by direction: CardinalDirection, steps: Int = 1) -> GridPosition {
        let stepCount = max(0, steps)
        let delta = direction.delta
        return translated(byX: delta.x * stepCount, byY: delta.y * stepCount)
    }
}

public enum CardinalDirection: String, Codable, CaseIterable, Sendable {
    case north
    case east
    case south
    case west

    public var delta: (x: Int, y: Int) {
        switch self {
        case .north:
            return (0, -1)
        case .east:
            return (1, 0)
        case .south:
            return (0, 1)
        case .west:
            return (-1, 0)
        }
    }

    public var opposite: CardinalDirection {
        switch self {
        case .north:
            return .south
        case .east:
            return .west
        case .south:
            return .north
        case .west:
            return .east
        }
    }

    public var left: CardinalDirection {
        switch self {
        case .north:
            return .west
        case .east:
            return .north
        case .south:
            return .east
        case .west:
            return .south
        }
    }

    public var right: CardinalDirection {
        switch self {
        case .north:
            return .east
        case .east:
            return .south
        case .south:
            return .west
        case .west:
            return .north
        }
    }
}

public enum Rotation: String, Codable, CaseIterable, Sendable {
    case north
    case east
    case south
    case west

    public var direction: CardinalDirection {
        CardinalDirection(rawValue: rawValue) ?? .north
    }

    public func rotatedClockwise() -> Rotation {
        switch self {
        case .north:
            return .east
        case .east:
            return .south
        case .south:
            return .west
        case .west:
            return .north
        }
    }
}

public enum StructureType: String, Codable, CaseIterable, Sendable {
    case hq
    case wall
    case turretMount
    case miner
    case smelter
    case assembler
    case ammoModule
    case powerPlant
    case conveyor
    case splitter
    case merger
    case storage
    case researchCenter
}

public struct StructureFootprint: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
    }

    public func coveredCells(anchor: GridPosition) -> [GridPosition] {
        let minX = anchor.x - (width - 1)
        let maxX = anchor.x
        let minY = anchor.y - (height - 1)
        let maxY = anchor.y

        var cells: [GridPosition] = []
        cells.reserveCapacity(width * height)
        for y in minY...maxY {
            for x in minX...maxX {
                cells.append(GridPosition(x: x, y: y, z: anchor.z))
            }
        }
        return cells
    }

    /// Returns cells just OUTSIDE the footprint edge in a given direction.
    /// For example, for a 3x2 building with anchor at (x,y), calling
    /// edgeCells(anchor:, direction: .west) returns the cells to the west
    /// of the building where conveyors can attach.
    public func edgeCells(anchor: GridPosition, direction: CardinalDirection) -> [GridPosition] {
        let minX = anchor.x - (width - 1)
        let maxX = anchor.x
        let minY = anchor.y - (height - 1)
        let maxY = anchor.y

        var cells: [GridPosition] = []
        switch direction {
        case .north:
            // Row above the building
            for x in minX...maxX {
                cells.append(GridPosition(x: x, y: minY - 1, z: anchor.z))
            }
        case .south:
            // Row below the building
            for x in minX...maxX {
                cells.append(GridPosition(x: x, y: maxY + 1, z: anchor.z))
            }
        case .west:
            // Column to the left of the building
            for y in minY...maxY {
                cells.append(GridPosition(x: minX - 1, y: y, z: anchor.z))
            }
        case .east:
            // Column to the right of the building
            for y in minY...maxY {
                cells.append(GridPosition(x: maxX + 1, y: y, z: anchor.z))
            }
        }
        return cells
    }
}

public extension StructureType {
    var footprint: StructureFootprint {
        switch self {
        case .hq:
            return StructureFootprint(width: 5, height: 5)
        case .conveyor, .splitter, .merger, .wall, .turretMount:
            return StructureFootprint(width: 1, height: 1)
        case .miner, .ammoModule:
            return StructureFootprint(width: 2, height: 2)
        case .smelter, .storage:
            return StructureFootprint(width: 3, height: 2)
        case .assembler, .researchCenter:
            return StructureFootprint(width: 3, height: 3)
        case .powerPlant:
            return StructureFootprint(width: 4, height: 3)
        }
    }

    func coveredCells(anchor: GridPosition) -> [GridPosition] {
        footprint.coveredCells(anchor: anchor)
    }

    var buildCosts: [ItemStack] {
        switch self {
        case .hq:
            return []
        case .powerPlant:
            return [ItemStack(itemID: "circuit", quantity: 6), ItemStack(itemID: "plate_copper", quantity: 10), ItemStack(itemID: "plate_steel", quantity: 4)]
        case .miner:
            return [ItemStack(itemID: "plate_iron", quantity: 10), ItemStack(itemID: "gear", quantity: 5)]
        case .smelter:
            return [ItemStack(itemID: "plate_steel", quantity: 8), ItemStack(itemID: "gear", quantity: 2)]
        case .assembler:
            return [ItemStack(itemID: "plate_iron", quantity: 8), ItemStack(itemID: "circuit", quantity: 4), ItemStack(itemID: "gear", quantity: 2)]
        case .ammoModule:
            return [ItemStack(itemID: "circuit", quantity: 4), ItemStack(itemID: "plate_steel", quantity: 4)]
        case .conveyor:
            return [ItemStack(itemID: "plate_iron", quantity: 1)]
        case .splitter:
            return [ItemStack(itemID: "plate_iron", quantity: 1)]
        case .merger:
            return [ItemStack(itemID: "plate_iron", quantity: 1)]
        case .storage:
            return [ItemStack(itemID: "plate_steel", quantity: 6), ItemStack(itemID: "gear", quantity: 4)]
        case .wall:
            return [ItemStack(itemID: "wall_kit", quantity: 1)]
        case .turretMount:
            return [ItemStack(itemID: "turret_core", quantity: 1), ItemStack(itemID: "plate_steel", quantity: 2)]
        case .researchCenter:
            return [ItemStack(itemID: "plate_iron", quantity: 12), ItemStack(itemID: "circuit", quantity: 6), ItemStack(itemID: "gear", quantity: 4)]
        }
    }

    var powerDemand: Int {
        switch self {
        case .hq:
            return 0
        case .powerPlant:
            return -30
        case .miner:
            return 3
        case .smelter:
            return 5
        case .assembler:
            return 6
        case .ammoModule:
            return 5
        case .conveyor:
            return 1
        case .splitter, .merger:
            return 0
        case .storage:
            return 0
        case .wall, .turretMount:
            return 0
        case .researchCenter:
            return 3
        }
    }

    var supportedRecipeIDs: [String] {
        switch self {
        case .smelter:
            return ["smelt_iron", "smelt_copper", "smelt_steel"]
        case .assembler:
            return [
                "forge_gear",
                "etch_circuit",
                "assemble_power_cell",
                "craft_wall_kit",
                "craft_turret_core",
                "craft_repair_kit"
            ]
        case .ammoModule:
            return ["craft_ammo_light", "craft_ammo_heavy", "craft_ammo_plasma"]
        case .hq, .wall, .turretMount, .miner, .powerPlant, .conveyor, .splitter, .merger, .storage, .researchCenter:
            return []
        }
    }

    var defaultRecipeID: String? {
        supportedRecipeIDs.first
    }
}

public struct BuildRequest: Codable, Hashable, Sendable {
    public var structure: StructureType
    public var position: GridPosition
    public var rotation: Rotation
    public var targetPatchID: Int?

    public init(structure: StructureType, position: GridPosition, rotation: Rotation = .north, targetPatchID: Int? = nil) {
        self.structure = structure
        self.position = position
        self.rotation = rotation
        self.targetPatchID = targetPatchID
    }
}

public enum CommandPayload: Codable, Hashable, Sendable {
    case placeStructure(BuildRequest)
    case removeStructure(entityID: EntityID)
    case placeConveyor(position: GridPosition, direction: CardinalDirection, inputDirection: CardinalDirection? = nil, outputDirection: CardinalDirection? = nil)
    case configureConveyorIO(entityID: EntityID, inputDirection: CardinalDirection, outputDirection: CardinalDirection)
    case rotateBuilding(entityID: EntityID)
    case pinRecipe(entityID: EntityID, recipeID: String)
    case startOreSurvey(nodeID: String, researchCenterID: EntityID)
    case triggerWave

    private enum CodingKeys: String, CodingKey {
        case kind
        case build
        case entityID
        case position
        case direction
        case inputDirection
        case outputDirection
        case recipeID
        case nodeID
        case researchCenterID
    }

    private enum Kind: String, Codable {
        case placeStructure
        case removeStructure
        case placeConveyor
        case configureConveyorIO
        case rotateBuilding
        case pinRecipe
        case startOreSurvey
        case triggerWave
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .placeStructure:
            self = .placeStructure(try container.decode(BuildRequest.self, forKey: .build))
        case .removeStructure:
            self = .removeStructure(entityID: try container.decode(EntityID.self, forKey: .entityID))
        case .placeConveyor:
            self = .placeConveyor(
                position: try container.decode(GridPosition.self, forKey: .position),
                direction: try container.decode(CardinalDirection.self, forKey: .direction),
                inputDirection: try container.decodeIfPresent(CardinalDirection.self, forKey: .inputDirection),
                outputDirection: try container.decodeIfPresent(CardinalDirection.self, forKey: .outputDirection)
            )
        case .configureConveyorIO:
            self = .configureConveyorIO(
                entityID: try container.decode(EntityID.self, forKey: .entityID),
                inputDirection: try container.decode(CardinalDirection.self, forKey: .inputDirection),
                outputDirection: try container.decode(CardinalDirection.self, forKey: .outputDirection)
            )
        case .rotateBuilding:
            self = .rotateBuilding(entityID: try container.decode(EntityID.self, forKey: .entityID))
        case .pinRecipe:
            self = .pinRecipe(
                entityID: try container.decode(EntityID.self, forKey: .entityID),
                recipeID: try container.decode(String.self, forKey: .recipeID)
            )
        case .startOreSurvey:
            self = .startOreSurvey(
                nodeID: try container.decode(String.self, forKey: .nodeID),
                researchCenterID: try container.decode(EntityID.self, forKey: .researchCenterID)
            )
        case .triggerWave:
            self = .triggerWave
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .placeStructure(let build):
            try container.encode(Kind.placeStructure, forKey: .kind)
            try container.encode(build, forKey: .build)
        case .removeStructure(let entityID):
            try container.encode(Kind.removeStructure, forKey: .kind)
            try container.encode(entityID, forKey: .entityID)
        case .placeConveyor(let position, let direction, let ioInput, let ioOutput):
            try container.encode(Kind.placeConveyor, forKey: .kind)
            try container.encode(position, forKey: .position)
            try container.encode(direction, forKey: .direction)
            try container.encodeIfPresent(ioInput, forKey: .inputDirection)
            try container.encodeIfPresent(ioOutput, forKey: .outputDirection)
        case .configureConveyorIO(let entityID, let inputDirection, let outputDirection):
            try container.encode(Kind.configureConveyorIO, forKey: .kind)
            try container.encode(entityID, forKey: .entityID)
            try container.encode(inputDirection, forKey: .inputDirection)
            try container.encode(outputDirection, forKey: .outputDirection)
        case .rotateBuilding(let entityID):
            try container.encode(Kind.rotateBuilding, forKey: .kind)
            try container.encode(entityID, forKey: .entityID)
        case .pinRecipe(let entityID, let recipeID):
            try container.encode(Kind.pinRecipe, forKey: .kind)
            try container.encode(entityID, forKey: .entityID)
            try container.encode(recipeID, forKey: .recipeID)
        case .startOreSurvey(let nodeID, let researchCenterID):
            try container.encode(Kind.startOreSurvey, forKey: .kind)
            try container.encode(nodeID, forKey: .nodeID)
            try container.encode(researchCenterID, forKey: .researchCenterID)
        case .triggerWave:
            try container.encode(Kind.triggerWave, forKey: .kind)
        }
    }

    var sortToken: String {
        switch self {
        case .placeStructure(let build):
            let patchToken = build.targetPatchID.map(String.init) ?? "-"
            return "place:\(build.structure.rawValue):\(build.position.x):\(build.position.y):\(build.position.z):\(build.rotation.rawValue):\(patchToken)"
        case .removeStructure(let entityID):
            return "remove:\(entityID)"
        case .placeConveyor(let position, let direction, _, _):
            return "conveyor:\(position.x):\(position.y):\(position.z):\(direction.rawValue)"
        case .configureConveyorIO(let entityID, let inputDirection, let outputDirection):
            return "conveyorIO:\(entityID):\(inputDirection.rawValue):\(outputDirection.rawValue)"
        case .rotateBuilding(let entityID):
            return "rotate:\(entityID)"
        case .pinRecipe(let entityID, let recipeID):
            return "pin:\(entityID):\(recipeID)"
        case .startOreSurvey(let nodeID, let researchCenterID):
            return "survey:\(nodeID):\(researchCenterID)"
        case .triggerWave:
            return "triggerWave"
        }
    }
}

public struct PlayerCommand: Codable, Hashable, Sendable {
    public var tick: UInt64
    public var actor: PlayerID
    public var payload: CommandPayload

    public init(tick: UInt64, actor: PlayerID, payload: CommandPayload) {
        self.tick = tick
        self.actor = actor
        self.payload = payload
    }

    var deterministicSortToken: String {
        "\(actor.rawValue):\(payload.sortToken)"
    }
}

public enum EventKind: String, Codable, Sendable {
    case runStarted
    case gracePeriodEnded
    case gameOver
    case structurePlaced
    case structureRemoved
    case waveStarted
    case waveCleared
    case waveEnded
    case enemySpawned
    case enemyMoved
    case structureDamaged
    case structureDestroyed
    case enemyReachedBase
    case enemyDestroyed
    case projectileFired
    case ammoSpent
    case notEnoughAmmo
    case milestoneReached
    case placementRejected
    case patchExhausted
    case minerIdled
    case ringSurveyStarted
    case ringRevealed
    case oreRenewalSpawned
    case wallNetworkSplit
    case wallNetworkRebuilt
    case bottleneckActivated
    case bottleneckDeactivated
}

// MARK: - Bottleneck Detection Types

public enum BottleneckSignalKind: String, Codable, Hashable, CaseIterable, Sendable {
    case ammoDryFire
    case inputStarved
    case outputBlocked
    case powerShortage
    case minerNoOre
    case conveyorStall
    case wallNetworkUnderfed
    case surgeBacklogHigh

    public var priority: Int {
        guard let index = Self.allCases.firstIndex(of: self) else { return Int.max }
        return index
    }
}

public enum BottleneckSignalScope: Codable, Hashable, Sendable {
    case global
    case network(Int)
    case structure(EntityID)
}

public enum BottleneckSignalSeverity: String, Codable, Hashable, Sendable, Comparable {
    case info
    case warn
    case critical

    private var sortOrder: Int {
        switch self {
        case .info: return 0
        case .warn: return 1
        case .critical: return 2
        }
    }

    public static func < (lhs: BottleneckSignalSeverity, rhs: BottleneckSignalSeverity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

public struct BottleneckSignal: Codable, Hashable, Sendable {
    public var kind: BottleneckSignalKind
    public var scope: BottleneckSignalScope
    public var severity: BottleneckSignalSeverity
    public var firstTick: UInt64
    public var lastTick: UInt64
    public var entityID: EntityID?
    public var networkID: Int?
    public var itemID: ItemID?
    public var detail: String?

    public init(
        kind: BottleneckSignalKind,
        scope: BottleneckSignalScope,
        severity: BottleneckSignalSeverity,
        firstTick: UInt64,
        lastTick: UInt64,
        entityID: EntityID? = nil,
        networkID: Int? = nil,
        itemID: ItemID? = nil,
        detail: String? = nil
    ) {
        self.kind = kind
        self.scope = scope
        self.severity = severity
        self.firstTick = firstTick
        self.lastTick = lastTick
        self.entityID = entityID
        self.networkID = networkID
        self.itemID = itemID
        self.detail = detail
    }
}

public struct BottleneckSignalKey: Codable, Hashable, Sendable {
    public var kind: BottleneckSignalKind
    public var scope: BottleneckSignalScope

    public init(kind: BottleneckSignalKind, scope: BottleneckSignalScope) {
        self.kind = kind
        self.scope = scope
    }
}

public struct BottleneckSignalHysteresis: Codable, Hashable, Sendable {
    public var conditionMetTickCount: UInt64
    public var conditionClearedTickCount: UInt64
    public var isActive: Bool

    public init(
        conditionMetTickCount: UInt64 = 0,
        conditionClearedTickCount: UInt64 = 0,
        isActive: Bool = false
    ) {
        self.conditionMetTickCount = conditionMetTickCount
        self.conditionClearedTickCount = conditionClearedTickCount
        self.isActive = isActive
    }
}

public struct BottleneckTelemetry: Codable, Hashable, Sendable {
    public var signalActiveTicksByKind: [BottleneckSignalKind: UInt64]
    public var signalTransitionsByKind: [BottleneckSignalKind: Int]
    public var maxConcurrentSignals: Int

    public init(
        signalActiveTicksByKind: [BottleneckSignalKind: UInt64] = [:],
        signalTransitionsByKind: [BottleneckSignalKind: Int] = [:],
        maxConcurrentSignals: Int = 0
    ) {
        self.signalActiveTicksByKind = signalActiveTicksByKind
        self.signalTransitionsByKind = signalTransitionsByKind
        self.maxConcurrentSignals = maxConcurrentSignals
    }
}

public struct BottleneckState: Codable, Hashable, Sendable {
    public var activeSignals: [BottleneckSignal]
    public var hysteresis: [BottleneckSignalKey: BottleneckSignalHysteresis]
    public var telemetry: BottleneckTelemetry
    public var previousDryFireEvents: Int

    public init(
        activeSignals: [BottleneckSignal] = [],
        hysteresis: [BottleneckSignalKey: BottleneckSignalHysteresis] = [:],
        telemetry: BottleneckTelemetry = BottleneckTelemetry(),
        previousDryFireEvents: Int = 0
    ) {
        self.activeSignals = activeSignals
        self.hysteresis = hysteresis
        self.telemetry = telemetry
        self.previousDryFireEvents = previousDryFireEvents
    }
}

public struct SimEvent: Codable, Hashable, Sendable {
    public var tick: UInt64
    public var kind: EventKind
    public var entity: EntityID?
    public var value: Int?
    public var itemID: ItemID?
    public var placementReason: PlacementResult?
    public var reasonDetail: String?

    public init(
        tick: UInt64,
        kind: EventKind,
        entity: EntityID? = nil,
        value: Int? = nil,
        itemID: ItemID? = nil,
        placementReason: PlacementResult? = nil,
        reasonDetail: String? = nil
    ) {
        self.tick = tick
        self.kind = kind
        self.entity = entity
        self.value = value
        self.itemID = itemID
        self.placementReason = placementReason
        self.reasonDetail = reasonDetail
    }
}

public enum EntityCategory: String, Codable, Sendable {
    case structure
    case enemy
    case projectile
}

public struct Entity: Codable, Hashable, Sendable {
    public var id: EntityID
    public var category: EntityCategory
    public var structureType: StructureType?
    public var turretDefID: String?
    public var hostWallID: EntityID?
    public var boundPatchID: Int?
    public var rotation: Rotation
    public var position: GridPosition
    public var health: Int
    public var maxHealth: Int

    public init(
        id: EntityID,
        category: EntityCategory,
        structureType: StructureType? = nil,
        turretDefID: String? = nil,
        hostWallID: EntityID? = nil,
        boundPatchID: Int? = nil,
        rotation: Rotation = .north,
        position: GridPosition,
        health: Int,
        maxHealth: Int
    ) {
        self.id = id
        self.category = category
        self.structureType = structureType
        self.turretDefID = turretDefID
        self.hostWallID = hostWallID
        self.boundPatchID = boundPatchID
        self.rotation = rotation
        self.position = position
        self.health = health
        self.maxHealth = maxHealth
    }
}

public enum EnemyArchetype: String, Codable, Sendable {
    case swarmling
    case droneScout
    case raider
    case breacher
    case overseer
}

public struct EnemyRuntime: Codable, Hashable, Sendable {
    public var id: EntityID
    public var enemyID: EnemyID
    public var archetype: EnemyArchetype
    public var moveEveryTicks: UInt64
    public var baseDamage: Int
    public var rewardCurrency: Int
    public var behaviorModifier: EnemyBehaviorModifier
    public var wallDamageMultiplier: Double
    public var entryPoint: GridPosition?

    public init(
        id: EntityID,
        enemyID: EnemyID = "drone_scout",
        archetype: EnemyArchetype,
        moveEveryTicks: UInt64,
        baseDamage: Int,
        rewardCurrency: Int,
        behaviorModifier: EnemyBehaviorModifier = .none,
        wallDamageMultiplier: Double = 1.0,
        entryPoint: GridPosition? = nil
    ) {
        self.id = id
        self.enemyID = enemyID
        self.archetype = archetype
        self.moveEveryTicks = moveEveryTicks
        self.baseDamage = baseDamage
        self.rewardCurrency = rewardCurrency
        self.behaviorModifier = behaviorModifier
        self.wallDamageMultiplier = wallDamageMultiplier
        self.entryPoint = entryPoint
    }
}

public struct WallNetworkState: Codable, Hashable, Sendable {
    public var id: Int
    public var wallEntityIDs: [EntityID]
    public var ammoPoolByItemID: [ItemID: Int]
    public var capacity: Int

    public init(
        id: Int,
        wallEntityIDs: [EntityID],
        ammoPoolByItemID: [ItemID: Int] = [:],
        capacity: Int
    ) {
        self.id = id
        self.wallEntityIDs = wallEntityIDs
        self.ammoPoolByItemID = ammoPoolByItemID
        self.capacity = max(0, capacity)
    }
}

public struct PendingEnemySpawn: Codable, Hashable, Sendable {
    public var spawnTick: UInt64
    public var enemyID: EnemyID
    public var waveIndex: Int
    public var clusterID: Int
    public var entryPoint: GridPosition
    public var spawnPosition: GridPosition

    public init(
        spawnTick: UInt64,
        enemyID: EnemyID,
        waveIndex: Int,
        clusterID: Int,
        entryPoint: GridPosition,
        spawnPosition: GridPosition
    ) {
        self.spawnTick = spawnTick
        self.enemyID = enemyID
        self.waveIndex = waveIndex
        self.clusterID = clusterID
        self.entryPoint = entryPoint
        self.spawnPosition = spawnPosition
    }
}

public struct ThreatTelemetry: Codable, Hashable, Sendable {
    public var spawnedEnemiesByWave: [Int: Int]
    public var queuedSpawnBacklog: Int
    public var structureDamageEvents: Int
    public var dryFireEvents: Int

    public init(
        spawnedEnemiesByWave: [Int: Int] = [:],
        queuedSpawnBacklog: Int = 0,
        structureDamageEvents: Int = 0,
        dryFireEvents: Int = 0
    ) {
        self.spawnedEnemiesByWave = spawnedEnemiesByWave
        self.queuedSpawnBacklog = max(0, queuedSpawnBacklog)
        self.structureDamageEvents = max(0, structureDamageEvents)
        self.dryFireEvents = max(0, dryFireEvents)
    }
}

public struct ProjectileRuntime: Codable, Hashable, Sendable {
    public var id: EntityID
    public var sourceTurretID: EntityID
    public var targetEnemyID: EntityID
    public var damage: Int
    public var impactTick: UInt64

    public init(id: EntityID, sourceTurretID: EntityID, targetEnemyID: EntityID, damage: Int, impactTick: UInt64) {
        self.id = id
        self.sourceTurretID = sourceTurretID
        self.targetEnemyID = targetEnemyID
        self.damage = damage
        self.impactTick = impactTick
    }
}

public struct CombatState: Codable, Hashable, Sendable {
    public var enemies: [EntityID: EnemyRuntime]
    public var projectiles: [EntityID: ProjectileRuntime]
    public var lastFireTickByTurret: [EntityID: UInt64]
    public var basePosition: GridPosition
    public var spawnEdgeX: Int
    public var spawnYMin: Int
    public var spawnYMax: Int
    public var wallNetworkByWallEntityID: [EntityID: Int]
    public var wallNetworks: [Int: WallNetworkState]
    public var wallNetworksDirty: Bool

    public init(
        enemies: [EntityID: EnemyRuntime] = [:],
        projectiles: [EntityID: ProjectileRuntime] = [:],
        lastFireTickByTurret: [EntityID: UInt64] = [:],
        basePosition: GridPosition = .zero,
        spawnEdgeX: Int = 120,
        spawnYMin: Int = 52,
        spawnYMax: Int = 76,
        wallNetworkByWallEntityID: [EntityID: Int] = [:],
        wallNetworks: [Int: WallNetworkState] = [:],
        wallNetworksDirty: Bool = true
    ) {
        self.enemies = enemies
        self.projectiles = projectiles
        self.lastFireTickByTurret = lastFireTickByTurret
        self.basePosition = basePosition
        self.spawnEdgeX = spawnEdgeX
        self.spawnYMin = spawnYMin
        self.spawnYMax = spawnYMax
        self.wallNetworkByWallEntityID = wallNetworkByWallEntityID
        self.wallNetworks = wallNetworks
        self.wallNetworksDirty = wallNetworksDirty
    }
}

public struct EconomyTelemetry: Codable, Hashable, Sendable {
    public var produced: [ItemID: Int]
    public var consumed: [ItemID: Int]

    public init(produced: [ItemID: Int] = [:], consumed: [ItemID: Int] = [:]) {
        self.produced = produced
        self.consumed = consumed
    }

    mutating func recordProduction(itemID: ItemID, quantity: Int) {
        produced[itemID, default: 0] += quantity
    }

    mutating func recordConsumption(itemID: ItemID, quantity: Int) {
        consumed[itemID, default: 0] += quantity
    }
}

public struct ConveyorPayload: Codable, Hashable, Sendable {
    public var itemID: ItemID
    public var progressTicks: Int

    public init(itemID: ItemID, progressTicks: Int = 0) {
        self.itemID = itemID
        self.progressTicks = max(0, progressTicks)
    }
}

public struct ConveyorIOConfig: Codable, Hashable, Sendable {
    public var inputDirection: CardinalDirection
    public var outputDirection: CardinalDirection

    public init(inputDirection: CardinalDirection, outputDirection: CardinalDirection) {
        self.inputDirection = inputDirection
        self.outputDirection = outputDirection
    }

    public static func `default`(for rotation: Rotation) -> ConveyorIOConfig {
        let output = rotation.direction
        return ConveyorIOConfig(inputDirection: output.opposite, outputDirection: output)
    }
}

public struct EconomyState: Codable, Hashable, Sendable {
    public var inventories: [ItemID: Int]
    public var activeRecipeByStructure: [EntityID: String]
    public var pinnedRecipeByStructure: [EntityID: String]
    public var productionProgressByStructure: [EntityID: Double]
    public var fractionalProductionRemainders: [ItemID: Double]
    public var structureInputBuffers: [EntityID: [ItemID: Int]]
    public var structureOutputBuffers: [EntityID: [ItemID: Int]]
    public var storageSharedPoolByEntity: [EntityID: [ItemID: Int]]
    public var conveyorPayloadByEntity: [EntityID: ConveyorPayload]
    public var conveyorIOByEntity: [EntityID: ConveyorIOConfig]
    public var splitterOutputToggleByEntity: [EntityID: Int]
    public var mergerInputToggleByEntity: [EntityID: Int]
    public var powerAvailable: Int
    public var powerDemand: Int
    public var currency: Int
    public var telemetry: EconomyTelemetry

    public init(
        inventories: [ItemID: Int] = [:],
        activeRecipeByStructure: [EntityID: String] = [:],
        pinnedRecipeByStructure: [EntityID: String] = [:],
        productionProgressByStructure: [EntityID: Double] = [:],
        fractionalProductionRemainders: [ItemID: Double] = [:],
        structureInputBuffers: [EntityID: [ItemID: Int]] = [:],
        structureOutputBuffers: [EntityID: [ItemID: Int]] = [:],
        storageSharedPoolByEntity: [EntityID: [ItemID: Int]] = [:],
        conveyorPayloadByEntity: [EntityID: ConveyorPayload] = [:],
        conveyorIOByEntity: [EntityID: ConveyorIOConfig] = [:],
        splitterOutputToggleByEntity: [EntityID: Int] = [:],
        mergerInputToggleByEntity: [EntityID: Int] = [:],
        powerAvailable: Int = 0,
        powerDemand: Int = 0,
        currency: Int = 0,
        telemetry: EconomyTelemetry = .init()
    ) {
        self.inventories = inventories
        self.activeRecipeByStructure = activeRecipeByStructure
        self.pinnedRecipeByStructure = pinnedRecipeByStructure
        self.productionProgressByStructure = productionProgressByStructure
        self.fractionalProductionRemainders = fractionalProductionRemainders
        self.structureInputBuffers = structureInputBuffers
        self.structureOutputBuffers = structureOutputBuffers
        self.storageSharedPoolByEntity = storageSharedPoolByEntity
        self.conveyorPayloadByEntity = conveyorPayloadByEntity
        self.conveyorIOByEntity = conveyorIOByEntity
        self.splitterOutputToggleByEntity = splitterOutputToggleByEntity
        self.mergerInputToggleByEntity = mergerInputToggleByEntity
        self.powerAvailable = powerAvailable
        self.powerDemand = powerDemand
        self.currency = currency
        self.telemetry = telemetry
    }

}

public struct ThreatState: Codable, Hashable, Sendable {
    public var waveIndex: Int
    public var nextWaveTick: UInt64
    public var waveIntervalTicks: UInt64
    public var waveDurationTicks: UInt64
    public var waveEndsAtTick: UInt64?
    public var isWaveActive: Bool
    public var waveGapBaseTicks: UInt64
    public var waveGapFloorTicks: UInt64
    public var waveGapCompressionTicks: UInt64
    public var gracePeriodTicks: UInt64
    public var graceEndsAtTick: UInt64
    public var trickleIntervalTicks: UInt64
    public var trickleMinCount: Int
    public var trickleMaxCount: Int
    public var nextTrickleTick: UInt64
    public var milestoneEvery: Int
    public var lastMilestoneWave: Int
    public var pendingSpawns: [PendingEnemySpawn]
    public var deterministicRandomState: UInt64
    public var telemetry: ThreatTelemetry

    public init(
        waveIndex: Int = 0,
        nextWaveTick: UInt64 = 0,
        waveIntervalTicks: UInt64 = 1_800,
        waveDurationTicks: UInt64 = 160,
        waveEndsAtTick: UInt64? = nil,
        isWaveActive: Bool = false,
        waveGapBaseTicks: UInt64? = nil,
        waveGapFloorTicks: UInt64 = 1_000,
        waveGapCompressionTicks: UInt64 = 40,
        gracePeriodTicks: UInt64 = 2_400,
        graceEndsAtTick: UInt64? = nil,
        trickleIntervalTicks: UInt64 = 240,
        trickleMinCount: Int = 1,
        trickleMaxCount: Int = 2,
        nextTrickleTick: UInt64 = 0,
        milestoneEvery: Int = 5,
        lastMilestoneWave: Int = 0,
        pendingSpawns: [PendingEnemySpawn] = [],
        deterministicRandomState: UInt64 = 0xC0FFEE,
        telemetry: ThreatTelemetry = ThreatTelemetry()
    ) {
        self.waveIndex = waveIndex
        self.nextWaveTick = nextWaveTick
        self.waveIntervalTicks = waveIntervalTicks
        self.waveDurationTicks = waveDurationTicks
        self.waveEndsAtTick = waveEndsAtTick
        self.isWaveActive = isWaveActive
        self.waveGapBaseTicks = waveGapBaseTicks ?? waveIntervalTicks
        self.waveGapFloorTicks = waveGapFloorTicks
        self.waveGapCompressionTicks = waveGapCompressionTicks
        self.gracePeriodTicks = gracePeriodTicks
        self.graceEndsAtTick = graceEndsAtTick ?? gracePeriodTicks
        self.trickleIntervalTicks = max(1, trickleIntervalTicks)
        self.trickleMinCount = max(1, trickleMinCount)
        self.trickleMaxCount = max(self.trickleMinCount, trickleMaxCount)
        self.nextTrickleTick = nextTrickleTick
        self.milestoneEvery = milestoneEvery
        self.lastMilestoneWave = lastMilestoneWave
        self.pendingSpawns = pendingSpawns
        self.deterministicRandomState = deterministicRandomState
        self.telemetry = telemetry
    }
}

public struct RunState: Codable, Hashable, Sendable {
    public var phase: RunPhase
    public var difficulty: Difficulty
    public var seed: RunSeed
    public var hqEntityID: EntityID?
    public var runStartedEmitted: Bool
    public var gracePeriodEndedEmitted: Bool
    public var gameOverEmitted: Bool

    public init(
        phase: RunPhase = .gracePeriod,
        difficulty: Difficulty = .normal,
        seed: RunSeed = 0,
        hqEntityID: EntityID? = nil,
        runStartedEmitted: Bool = false,
        gracePeriodEndedEmitted: Bool = false,
        gameOverEmitted: Bool = false
    ) {
        self.phase = phase
        self.difficulty = difficulty
        self.seed = seed
        self.hqEntityID = hqEntityID
        self.runStartedEmitted = runStartedEmitted
        self.gracePeriodEndedEmitted = gracePeriodEndedEmitted
        self.gameOverEmitted = gameOverEmitted
    }

    public var gameOver: Bool {
        get { phase == .gameOver }
        set {
            if newValue {
                phase = .gameOver
            } else if phase == .gameOver {
                phase = .playing
            }
        }
    }
}

public enum OrePatchRichness: String, Codable, Sendable {
    case poor
    case normal
    case rich
}

public enum OreRingVisibilityState: String, Codable, Sendable {
    case locked
    case surveying
    case revealed
}

public struct RenewalRequest: Codable, Hashable, Sendable {
    public var sourcePatchID: Int
    public var oreType: ItemID
    public var exhaustedAtTick: UInt64
    public var skipCount: Int

    public init(sourcePatchID: Int, oreType: ItemID, exhaustedAtTick: UInt64, skipCount: Int = 0) {
        self.sourcePatchID = sourcePatchID
        self.oreType = oreType
        self.exhaustedAtTick = exhaustedAtTick
        self.skipCount = max(0, skipCount)
    }
}

public struct OreLifecycleState: Codable, Hashable, Sendable {
    public var ringStates: [Int: OreRingVisibilityState]
    public var surveyEndTickByRing: [Int: UInt64]
    public var renewalQueue: [RenewalRequest]
    public var nextPatchID: Int
    public var lastRenewalWaveProcessed: Int

    public init(
        ringStates: [Int: OreRingVisibilityState] = [
            0: .revealed,
            1: .locked,
            2: .locked,
            3: .locked
        ],
        surveyEndTickByRing: [Int: UInt64] = [:],
        renewalQueue: [RenewalRequest] = [],
        nextPatchID: Int = 1,
        lastRenewalWaveProcessed: Int = 0
    ) {
        self.ringStates = ringStates
        self.surveyEndTickByRing = surveyEndTickByRing
        self.renewalQueue = renewalQueue
        self.nextPatchID = max(1, nextPatchID)
        self.lastRenewalWaveProcessed = max(0, lastRenewalWaveProcessed)
    }
}

public struct OrePatch: Codable, Hashable, Sendable {
    public var id: Int
    public var oreType: ItemID
    public var richness: OrePatchRichness
    public var position: GridPosition
    public var revealRing: Int
    public var isRevealed: Bool
    public var totalOre: Int
    public var remainingOre: Int
    public var boundMinerID: EntityID?
    public var exhaustedAtTick: UInt64?
    public var renewalProcessed: Bool

    public init(
        id: Int,
        oreType: ItemID,
        richness: OrePatchRichness,
        position: GridPosition,
        revealRing: Int = 0,
        isRevealed: Bool = true,
        totalOre: Int,
        remainingOre: Int,
        boundMinerID: EntityID? = nil,
        exhaustedAtTick: UInt64? = nil,
        renewalProcessed: Bool = false
    ) {
        self.id = id
        self.oreType = oreType
        self.richness = richness
        self.position = position
        self.revealRing = revealRing
        self.isRevealed = isRevealed
        self.totalOre = totalOre
        self.remainingOre = remainingOre
        self.boundMinerID = boundMinerID
        self.exhaustedAtTick = exhaustedAtTick
        self.renewalProcessed = renewalProcessed
    }

    public var isExhausted: Bool {
        remainingOre <= 0
    }
}

public struct WorldState: Codable, Hashable, Sendable {
    public var tick: UInt64
    public var board: BoardState
    public var entities: EntityStore
    public var orePatches: [OrePatch]
    public var oreLifecycle: OreLifecycleState
    public var economy: EconomyState
    public var threat: ThreatState
    public var run: RunState
    public var combat: CombatState
    public var bottleneck: BottleneckState

    public init(
        tick: UInt64,
        board: BoardState = .bootstrap(),
        entities: EntityStore,
        orePatches: [OrePatch] = [],
        oreLifecycle: OreLifecycleState = OreLifecycleState(),
        economy: EconomyState,
        threat: ThreatState,
        run: RunState,
        combat: CombatState = CombatState(),
        bottleneck: BottleneckState = BottleneckState()
    ) {
        self.tick = tick
        self.board = board
        self.entities = entities
        self.orePatches = orePatches
        self.oreLifecycle = oreLifecycle
        self.economy = economy
        self.threat = threat
        self.run = run
        self.combat = combat
        self.bottleneck = bottleneck
    }

    public static func bootstrap(difficulty: Difficulty = .normal, seed: RunSeed = 0) -> WorldState {
        let content = CanonicalBootstrapContent.bundle ?? .empty
        var board = BoardState(definition: content.board)
        var store = EntityStore()

        let hqID = store.spawnStructure(
            .hq,
            at: board.basePosition,
            health: max(1, content.hq.health),
            maxHealth: max(1, content.hq.health)
        )

        let difficultyID = DifficultyID(rawValue: difficulty.rawValue) ?? .normal
        let difficultyValues = content.difficulty.values(for: difficultyID)
        let graceTicks = UInt64(max(1, difficultyValues.gracePeriodSeconds) * 20)
        let waveBaseTicks = UInt64(max(1, difficultyValues.interWaveGapBase) * 20)
        let waveFloorTicks = UInt64(max(1, difficultyValues.interWaveGapFloor) * 20)
        let waveCompressionTicks = UInt64(max(0, difficultyValues.gapCompressionPerWave) * 20)
        let trickleTicks = UInt64(max(1, difficultyValues.trickleIntervalSeconds) * 20)
        let startingResources = content.hq.startingResources.values(for: difficultyID)
        let oreConfig = content.orePatches

        let orePatches = generateRing0OrePatches(
            seed: seed,
            difficulty: difficulty,
            board: board,
            oreConfig: oreConfig
        )
        let oreLifecycle = OreLifecycleState(nextPatchID: (orePatches.map(\.id).max() ?? 0) + 1)
        for patch in orePatches {
            let cell = GridPosition(x: patch.position.x, y: patch.position.y, z: 0)
            if !board.restrictedCells.contains(where: { $0.x == cell.x && $0.y == cell.y }) {
                board.restrictedCells.append(cell)
            }
        }

        var world = WorldState(
            tick: 0,
            board: board,
            entities: store,
            orePatches: orePatches,
            oreLifecycle: oreLifecycle,
            economy: EconomyState(
                inventories: [:],
                structureInputBuffers: [:],
                structureOutputBuffers: [:],
                storageSharedPoolByEntity: [hqID: startingResources]
            ),
            threat: ThreatState(
                waveIndex: 0,
                nextWaveTick: graceTicks + waveBaseTicks,
                waveIntervalTicks: waveBaseTicks,
                waveDurationTicks: 160,
                waveEndsAtTick: nil,
                isWaveActive: false,
                waveGapBaseTicks: waveBaseTicks,
                waveGapFloorTicks: waveFloorTicks,
                waveGapCompressionTicks: waveCompressionTicks,
                gracePeriodTicks: graceTicks,
                graceEndsAtTick: graceTicks,
                trickleIntervalTicks: trickleTicks,
                trickleMinCount: max(1, difficultyValues.trickleSize.first ?? 1),
                trickleMaxCount: max(1, difficultyValues.trickleSize.dropFirst().first ?? 1),
                nextTrickleTick: graceTicks,
                milestoneEvery: 5,
                lastMilestoneWave: 0,
                pendingSpawns: [],
                deterministicRandomState: seed
            ),
            run: RunState(
                phase: .gracePeriod,
                difficulty: difficulty,
                seed: seed,
                hqEntityID: hqID
            ),
            combat: CombatState(
                basePosition: board.basePosition,
                spawnEdgeX: board.spawnEdgeX,
                spawnYMin: board.spawnYMin,
                spawnYMax: board.spawnYMax
            )
        )
        world.rebuildAggregatedInventory()
        return world
    }

    public var hqHealth: Int {
        guard let hqID = run.hqEntityID else { return 0 }
        return entities.entity(id: hqID)?.health ?? 0
    }

    public var hqMaxHealth: Int {
        guard let hqID = run.hqEntityID else { return 0 }
        return entities.entity(id: hqID)?.maxHealth ?? 0
    }

    public mutating func rebuildAggregatedInventory() {
        economy.inventories = aggregatedPhysicalInventory()
    }

    public func aggregatedPhysicalInventory() -> [ItemID: Int] {
        let hasPhysicalStores =
            !economy.structureInputBuffers.isEmpty
            || !economy.structureOutputBuffers.isEmpty
            || !economy.storageSharedPoolByEntity.isEmpty
            || !economy.conveyorPayloadByEntity.isEmpty
            || !combat.wallNetworks.isEmpty
        guard hasPhysicalStores else {
            return [:]
        }

        var aggregate: [ItemID: Int] = [:]

        func absorb(_ items: [ItemID: Int]) {
            for (itemID, quantity) in items where quantity > 0 {
                aggregate[itemID, default: 0] += quantity
            }
        }

        for buffer in economy.structureInputBuffers.values {
            absorb(buffer)
        }
        for buffer in economy.structureOutputBuffers.values {
            absorb(buffer)
        }
        for pool in economy.storageSharedPoolByEntity.values {
            absorb(pool)
        }
        for payload in economy.conveyorPayloadByEntity.values {
            aggregate[payload.itemID, default: 0] += 1
        }
        for network in combat.wallNetworks.values {
            absorb(network.ammoPoolByItemID)
        }

        return aggregate
    }
}

private struct DeterministicRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xA076_1D64_78BD_642F : seed
    }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextInt(upperBound: Int) -> Int {
        guard upperBound > 1 else { return 0 }
        return Int(nextUInt64() % UInt64(upperBound))
    }
}

private func generateRing0OrePatches(
    seed: RunSeed,
    difficulty: Difficulty,
    board: BoardState,
    oreConfig: OrePatchesConfigDef
) -> [OrePatch] {
    let difficultyID = DifficultyID(rawValue: difficulty.rawValue) ?? .normal
    let ring0 = oreConfig.rings.first(where: { $0.index == 0 }) ?? OrePatchesConfigDef.v1Default.rings[0]
    let patchCount = max(1, ring0.patchCount.value(for: difficultyID))
    let base = board.basePosition

    var blocked: Set<GridPosition> = Set(board.restrictedCells + board.blockedCells)
    let hqFootprint = Set(StructureType.hq.footprint.coveredCells(anchor: base))
    blocked.formUnion(hqFootprint)

    // Keep a two-tile moat around HQ clear for starter walling.
    for cell in hqFootprint {
        for dy in -2...2 {
            for dx in -2...2 {
                blocked.insert(cell.translated(byX: dx, byY: dy))
            }
        }
    }

    var candidates: [GridPosition] = []
    for y in 0..<board.height {
        for x in 0..<board.width {
            let position = GridPosition(x: x, y: y, z: 0)
            guard !blocked.contains(position) else { continue }
            let distance = max(abs(position.x - base.x), abs(position.y - base.y))
            guard distance >= 4, distance <= max(4, ring0.maxDistance) else { continue }
            candidates.append(position)
        }
    }
    candidates.sort { lhs, rhs in
        if lhs.y == rhs.y { return lhs.x < rhs.x }
        return lhs.y < rhs.y
    }

    var rng = DeterministicRNG(seed: seed)
    var placedPositions: [GridPosition] = []
    let oreTypesByID = Dictionary(uniqueKeysWithValues: oreConfig.oreTypes.map { ($0.oreType, $0) })
    let weightedOreTypes = oreConfig.oreTypes
        .filter { $0.rarityWeight > 0 }
        .sorted { $0.oreType < $1.oreType }

    func chebyshevDistance(_ lhs: GridPosition, _ rhs: GridPosition) -> Int {
        max(abs(lhs.x - rhs.x), abs(lhs.y - rhs.y))
    }

    func canPlace(_ position: GridPosition, spacing: Int) -> Bool {
        placedPositions.allSatisfy { existing in
            chebyshevDistance(position, existing) >= spacing
        }
    }

    func pickPosition(
        minDistance: Int,
        maxDistance: Int,
        preferredSpacing: Int = 3,
        fallbackSpacing: Int = 2
    ) -> GridPosition? {
        let localCandidates = candidates.filter { position in
            let distance = chebyshevDistance(position, base)
            return distance >= minDistance && distance <= maxDistance
        }
        guard !localCandidates.isEmpty else { return nil }

        for spacing in [preferredSpacing, fallbackSpacing] where spacing > 0 {
            for _ in 0..<(localCandidates.count * 2) {
                let candidate = localCandidates[rng.nextInt(upperBound: localCandidates.count)]
                if canPlace(candidate, spacing: spacing) {
                    return candidate
                }
            }
            if let deterministicPick = localCandidates.first(where: { canPlace($0, spacing: spacing) }) {
                return deterministicPick
            }
        }
        return nil
    }

    func rollRichness() -> OrePatchRichness {
        let poor = max(0, ring0.richnessWeights.poor)
        let normal = max(0, ring0.richnessWeights.normal)
        let rich = max(0, ring0.richnessWeights.rich)
        let total = poor + normal + rich
        guard total > 0 else { return .normal }

        let bucket = Double(rng.nextInt(upperBound: 10_000)) / 10_000.0
        var threshold = poor / total
        if bucket < threshold { return .poor }
        threshold += normal / total
        if bucket < threshold { return .normal }
        return .rich
    }

    func oreAmount(itemID: ItemID, richness: OrePatchRichness) -> Int {
        if let oreType = oreTypesByID[itemID] {
            switch richness {
            case .poor:
                return max(1, oreType.amounts.poor)
            case .normal:
                return max(1, oreType.amounts.normal)
            case .rich:
                return max(1, oreType.amounts.rich)
            }
        }
        switch (itemID, richness) {
        case ("ore_iron", .poor): return 300
        case ("ore_iron", .normal): return 500
        case ("ore_iron", .rich): return 800
        case ("ore_copper", .poor): return 200
        case ("ore_copper", .normal): return 400
        case ("ore_copper", .rich): return 650
        case ("ore_coal", .poor): return 150
        case ("ore_coal", .normal): return 300
        case ("ore_coal", .rich): return 500
        default: return 300
        }
    }

    func rollOreType() -> ItemID {
        guard !weightedOreTypes.isEmpty else { return "ore_iron" }
        let totalWeight = weightedOreTypes.reduce(0.0) { $0 + max(0, $1.rarityWeight) }
        guard totalWeight > 0 else { return weightedOreTypes[0].oreType }

        var target = Double(rng.nextInt(upperBound: 10_000)) / 10_000.0 * totalWeight
        for oreType in weightedOreTypes {
            let weight = max(0, oreType.rarityWeight)
            if target < weight {
                return oreType.oreType
            }
            target -= weight
        }
        return weightedOreTypes[weightedOreTypes.count - 1].oreType
    }

    var patches: [OrePatch] = []
    let guaranteedTypes: [ItemID] = ["ore_iron", "ore_copper", "ore_coal"]
    let guaranteedCount = min(patchCount, guaranteedTypes.count)

    for oreType in guaranteedTypes.prefix(guaranteedCount) {
        guard let position = pickPosition(minDistance: 4, maxDistance: min(8, ring0.maxDistance)) else { break }
        placedPositions.append(position)
        let richness = rollRichness()
        let totalOre = oreAmount(itemID: oreType, richness: richness)
        patches.append(
            OrePatch(
                id: patches.count + 1,
                oreType: oreType,
                richness: richness,
                position: position,
                revealRing: 0,
                isRevealed: true,
                totalOre: totalOre,
                remainingOre: totalOre
            )
        )
    }

    while patches.count < patchCount {
        guard let position = pickPosition(minDistance: 6, maxDistance: max(6, ring0.maxDistance)) else { break }
        placedPositions.append(position)
        let oreType = rollOreType()
        let richness = rollRichness()
        let totalOre = oreAmount(itemID: oreType, richness: richness)
        patches.append(
            OrePatch(
                id: patches.count + 1,
                oreType: oreType,
                richness: richness,
                position: position,
                revealRing: 0,
                isRevealed: true,
                totalOre: totalOre,
                remainingOre: totalOre
            )
        )
    }

    return patches.sorted { lhs, rhs in
        if lhs.position.x == rhs.position.x {
            return lhs.position.y < rhs.position.y
        }
        return lhs.position.x < rhs.position.x
    }
}

public struct SystemContext {
    public var tickDurationSeconds: Double
    public var commands: [PlayerCommand]

    private let emitEvent: (SimEvent) -> Void

    public init(tickDurationSeconds: Double, commands: [PlayerCommand], emitEvent: @escaping (SimEvent) -> Void) {
        self.tickDurationSeconds = tickDurationSeconds
        self.commands = commands
        self.emitEvent = emitEvent
    }

    public func emit(_ event: SimEvent) {
        emitEvent(event)
    }
}

public protocol SimulationSystem {
    func update(state: inout WorldState, context: SystemContext)
}
