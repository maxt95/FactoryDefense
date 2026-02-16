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
    case extracted
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
        abs(x - other.x) + abs(y - other.y) + abs(z - other.z)
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
}

public extension StructureType {
    var footprint: StructureFootprint {
        switch self {
        case .hq:
            return StructureFootprint(width: 2, height: 2)
        case .wall, .turretMount, .miner, .smelter, .assembler, .ammoModule, .powerPlant, .conveyor, .splitter, .merger, .storage:
            return StructureFootprint(width: 1, height: 1)
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
            return [ItemStack(itemID: "circuit", quantity: 2), ItemStack(itemID: "plate_copper", quantity: 4)]
        case .miner:
            return [ItemStack(itemID: "plate_iron", quantity: 6), ItemStack(itemID: "gear", quantity: 3)]
        case .smelter:
            return [ItemStack(itemID: "plate_steel", quantity: 4)]
        case .assembler:
            return [ItemStack(itemID: "plate_iron", quantity: 4), ItemStack(itemID: "circuit", quantity: 2)]
        case .ammoModule:
            return [ItemStack(itemID: "circuit", quantity: 2), ItemStack(itemID: "plate_steel", quantity: 2)]
        case .conveyor:
            return [ItemStack(itemID: "plate_iron", quantity: 1)]
        case .splitter:
            return [ItemStack(itemID: "plate_iron", quantity: 1)]
        case .merger:
            return [ItemStack(itemID: "plate_iron", quantity: 1)]
        case .storage:
            return [ItemStack(itemID: "plate_steel", quantity: 3), ItemStack(itemID: "gear", quantity: 2)]
        case .wall:
            return [ItemStack(itemID: "wall_kit", quantity: 1)]
        case .turretMount:
            return [ItemStack(itemID: "turret_core", quantity: 1), ItemStack(itemID: "plate_steel", quantity: 2)]
        }
    }

    var powerDemand: Int {
        switch self {
        case .hq:
            return 0
        case .powerPlant:
            return -12
        case .miner:
            return 2
        case .smelter:
            return 3
        case .assembler:
            return 3
        case .ammoModule:
            return 4
        case .conveyor:
            return 1
        case .splitter, .merger:
            return 0
        case .storage:
            return 0
        case .wall, .turretMount:
            return 0
        }
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
    case placeConveyor(position: GridPosition, direction: CardinalDirection)
    case rotateBuilding(entityID: EntityID)
    case pinRecipe(entityID: EntityID, recipeID: String)
    case extract
    case triggerWave

    private enum CodingKeys: String, CodingKey {
        case kind
        case build
        case entityID
        case position
        case direction
        case recipeID
    }

    private enum Kind: String, Codable {
        case placeStructure
        case removeStructure
        case placeConveyor
        case rotateBuilding
        case pinRecipe
        case extract
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
                direction: try container.decode(CardinalDirection.self, forKey: .direction)
            )
        case .rotateBuilding:
            self = .rotateBuilding(entityID: try container.decode(EntityID.self, forKey: .entityID))
        case .pinRecipe:
            self = .pinRecipe(
                entityID: try container.decode(EntityID.self, forKey: .entityID),
                recipeID: try container.decode(String.self, forKey: .recipeID)
            )
        case .extract:
            self = .extract
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
        case .placeConveyor(let position, let direction):
            try container.encode(Kind.placeConveyor, forKey: .kind)
            try container.encode(position, forKey: .position)
            try container.encode(direction, forKey: .direction)
        case .rotateBuilding(let entityID):
            try container.encode(Kind.rotateBuilding, forKey: .kind)
            try container.encode(entityID, forKey: .entityID)
        case .pinRecipe(let entityID, let recipeID):
            try container.encode(Kind.pinRecipe, forKey: .kind)
            try container.encode(entityID, forKey: .entityID)
            try container.encode(recipeID, forKey: .recipeID)
        case .extract:
            try container.encode(Kind.extract, forKey: .kind)
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
        case .placeConveyor(let position, let direction):
            return "conveyor:\(position.x):\(position.y):\(position.z):\(direction.rawValue)"
        case .rotateBuilding(let entityID):
            return "rotate:\(entityID)"
        case .pinRecipe(let entityID, let recipeID):
            return "pin:\(entityID):\(recipeID)"
        case .extract:
            return "extract"
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
    case raidTriggered
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
    case extracted
    case placementRejected
    case patchExhausted
    case minerIdled
    case wallNetworkSplit
    case wallNetworkRebuilt
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
        spawnEdgeX: Int = 56,
        spawnYMin: Int = 27,
        spawnYMax: Int = 36,
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
        self.splitterOutputToggleByEntity = splitterOutputToggleByEntity
        self.mergerInputToggleByEntity = mergerInputToggleByEntity
        self.powerAvailable = powerAvailable
        self.powerDemand = powerDemand
        self.currency = currency
        self.telemetry = telemetry
    }

    public init(
        inventories: [ItemID: Int],
        activeRecipeByStructure: [EntityID: String],
        pinnedRecipeByStructure: [EntityID: String],
        productionProgressByStructure: [EntityID: Double],
        fractionalProductionRemainders: [ItemID: Double],
        structureInputBuffers: [EntityID: [ItemID: Int]],
        structureOutputBuffers: [EntityID: [ItemID: Int]],
        conveyorPayloadByEntity: [EntityID: ConveyorPayload],
        powerAvailable: Int,
        powerDemand: Int,
        currency: Int,
        telemetry: EconomyTelemetry
    ) {
        self.init(
            inventories: inventories,
            activeRecipeByStructure: activeRecipeByStructure,
            pinnedRecipeByStructure: pinnedRecipeByStructure,
            productionProgressByStructure: productionProgressByStructure,
            fractionalProductionRemainders: fractionalProductionRemainders,
            structureInputBuffers: structureInputBuffers,
            structureOutputBuffers: structureOutputBuffers,
            storageSharedPoolByEntity: [:],
            conveyorPayloadByEntity: conveyorPayloadByEntity,
            powerAvailable: powerAvailable,
            powerDemand: powerDemand,
            currency: currency,
            telemetry: telemetry
        )
    }

    public init(
        inventories: [ItemID: Int],
        activeRecipeByStructure: [EntityID: String],
        pinnedRecipeByStructure: [EntityID: String],
        productionProgressByStructure: [EntityID: Double],
        fractionalProductionRemainders: [ItemID: Double],
        structureInputBuffers: [EntityID: [ItemID: Int]],
        structureOutputBuffers: [EntityID: [ItemID: Int]],
        storageSharedPoolByEntity: [EntityID: [ItemID: Int]],
        conveyorPayloadByEntity: [EntityID: ConveyorPayload],
        powerAvailable: Int,
        powerDemand: Int,
        currency: Int,
        telemetry: EconomyTelemetry
    ) {
        self.init(
            inventories: inventories,
            activeRecipeByStructure: activeRecipeByStructure,
            pinnedRecipeByStructure: pinnedRecipeByStructure,
            productionProgressByStructure: productionProgressByStructure,
            fractionalProductionRemainders: fractionalProductionRemainders,
            structureInputBuffers: structureInputBuffers,
            structureOutputBuffers: structureOutputBuffers,
            storageSharedPoolByEntity: storageSharedPoolByEntity,
            conveyorPayloadByEntity: conveyorPayloadByEntity,
            splitterOutputToggleByEntity: [:],
            mergerInputToggleByEntity: [:],
            powerAvailable: powerAvailable,
            powerDemand: powerDemand,
            currency: currency,
            telemetry: telemetry
        )
    }

    public init(
        inventories: [ItemID: Int],
        activeRecipeByStructure: [EntityID: String],
        productionProgressByStructure: [EntityID: Double],
        fractionalProductionRemainders: [ItemID: Double],
        structureInputBuffers: [EntityID: [ItemID: Int]],
        structureOutputBuffers: [EntityID: [ItemID: Int]],
        conveyorPayloadByEntity: [EntityID: ConveyorPayload],
        splitterOutputToggleByEntity: [EntityID: Int] = [:],
        mergerInputToggleByEntity: [EntityID: Int] = [:],
        powerAvailable: Int,
        powerDemand: Int,
        currency: Int,
        telemetry: EconomyTelemetry
    ) {
        self.init(
            inventories: inventories,
            activeRecipeByStructure: activeRecipeByStructure,
            pinnedRecipeByStructure: [:],
            productionProgressByStructure: productionProgressByStructure,
            fractionalProductionRemainders: fractionalProductionRemainders,
            structureInputBuffers: structureInputBuffers,
            structureOutputBuffers: structureOutputBuffers,
            storageSharedPoolByEntity: [:],
            conveyorPayloadByEntity: conveyorPayloadByEntity,
            splitterOutputToggleByEntity: splitterOutputToggleByEntity,
            mergerInputToggleByEntity: mergerInputToggleByEntity,
            powerAvailable: powerAvailable,
            powerDemand: powerDemand,
            currency: currency,
            telemetry: telemetry
        )
    }

    @discardableResult
    public mutating func consume(itemID: ItemID, quantity: Int) -> Bool {
        guard quantity > 0 else { return true }
        let current = inventories[itemID, default: 0]
        guard current >= quantity else { return false }
        inventories[itemID] = current - quantity
        telemetry.recordConsumption(itemID: itemID, quantity: quantity)
        return true
    }

    public mutating func add(itemID: ItemID, quantity: Int) {
        guard quantity > 0 else { return }
        inventories[itemID, default: 0] += quantity
        telemetry.recordProduction(itemID: itemID, quantity: quantity)
    }

    public func canAfford(_ costs: [ItemStack]) -> Bool {
        costs.allSatisfy { inventories[$0.itemID, default: 0] >= $0.quantity }
    }

    @discardableResult
    public mutating func consume(costs: [ItemStack]) -> Bool {
        guard canAfford(costs) else { return false }
        for cost in costs {
            _ = consume(itemID: cost.itemID, quantity: cost.quantity)
        }
        return true
    }

    public mutating func addFractional(itemID: ItemID, quantity: Double) {
        guard quantity > 0 else { return }
        let total = fractionalProductionRemainders[itemID, default: 0] + quantity
        let whole = Int(total.rounded(.down))
        if whole > 0 {
            add(itemID: itemID, quantity: whole)
        }
        fractionalProductionRemainders[itemID] = total - Double(whole)
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
    public var raidCooldownUntilTick: UInt64
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
        raidCooldownUntilTick: UInt64 = 0,
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
        self.raidCooldownUntilTick = raidCooldownUntilTick
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

    public var extracted: Bool {
        get { phase == .extracted }
        set {
            if newValue {
                phase = .extracted
            } else if phase == .extracted {
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

public struct OrePatch: Codable, Hashable, Sendable {
    public var id: Int
    public var oreType: ItemID
    public var richness: OrePatchRichness
    public var position: GridPosition
    public var totalOre: Int
    public var remainingOre: Int
    public var boundMinerID: EntityID?

    public init(
        id: Int,
        oreType: ItemID,
        richness: OrePatchRichness,
        position: GridPosition,
        totalOre: Int,
        remainingOre: Int,
        boundMinerID: EntityID? = nil
    ) {
        self.id = id
        self.oreType = oreType
        self.richness = richness
        self.position = position
        self.totalOre = totalOre
        self.remainingOre = remainingOre
        self.boundMinerID = boundMinerID
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
    public var economy: EconomyState
    public var threat: ThreatState
    public var run: RunState
    public var combat: CombatState

    public init(
        tick: UInt64,
        board: BoardState = .bootstrap(),
        entities: EntityStore,
        orePatches: [OrePatch] = [],
        economy: EconomyState,
        threat: ThreatState,
        run: RunState,
        combat: CombatState = CombatState()
    ) {
        self.tick = tick
        self.board = board
        self.entities = entities
        self.orePatches = orePatches
        self.economy = economy
        self.threat = threat
        self.run = run
        self.combat = combat
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

        let orePatches = generateRing0OrePatches(seed: seed, difficulty: difficulty)
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
                raidCooldownUntilTick: 0,
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
        guard run.hqEntityID != nil else { return }

        let hasPhysicalStores =
            !economy.structureInputBuffers.isEmpty
            || !economy.structureOutputBuffers.isEmpty
            || !economy.storageSharedPoolByEntity.isEmpty
            || !economy.conveyorPayloadByEntity.isEmpty
            || !combat.wallNetworks.isEmpty
        guard hasPhysicalStores else { return }

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

        economy.inventories = aggregate
    }
}

private enum CanonicalBootstrapContent {
    static let bundle: GameContentBundle? = {
        let contentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Content/bootstrap")
        return try? ContentLoader().loadBundle(from: contentDirectory)
    }()
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

private func generateRing0OrePatches(seed: RunSeed, difficulty: Difficulty) -> [OrePatch] {
    let patchCount: Int
    switch difficulty {
    case .easy:
        patchCount = 7
    case .normal:
        patchCount = 5
    case .hard:
        patchCount = 3
    }

    let minX = 34
    let maxX = 46
    let minY = 26
    let maxY = 38
    let restrictedCells: Set<GridPosition> = [
        GridPosition(x: 39, y: 31),
        GridPosition(x: 40, y: 31),
        GridPosition(x: 39, y: 32),
        GridPosition(x: 40, y: 32),
        GridPosition(x: 47, y: 31),
        GridPosition(x: 47, y: 32),
        GridPosition(x: 47, y: 33)
    ]

    var candidates: [GridPosition] = []
    for y in minY...maxY {
        for x in minX...maxX {
            let position = GridPosition(x: x, y: y)
            if !restrictedCells.contains(position) {
                candidates.append(position)
            }
        }
    }
    candidates.sort {
        if $0.y == $1.y { return $0.x < $1.x }
        return $0.y < $1.y
    }

    var rng = DeterministicRNG(seed: seed)
    var placed: [GridPosition] = []

    func isValid(_ candidate: GridPosition) -> Bool {
        placed.allSatisfy { existing in
            max(abs(existing.x - candidate.x), abs(existing.y - candidate.y)) >= 3
        }
    }

    func pickPosition() -> GridPosition? {
        guard !candidates.isEmpty else { return nil }
        for _ in 0..<(candidates.count * 2) {
            let candidate = candidates[rng.nextInt(upperBound: candidates.count)]
            if isValid(candidate) {
                return candidate
            }
        }
        return candidates.first(where: isValid)
    }

    func rollRichness() -> OrePatchRichness {
        let roll = rng.nextInt(upperBound: 100)
        if roll < 40 { return .poor }
        if roll < 90 { return .normal }
        return .rich
    }

    func oreAmount(itemID: ItemID, richness: OrePatchRichness) -> Int {
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
        let roll = rng.nextInt(upperBound: 20)
        if roll < 10 { return "ore_iron" }
        if roll < 16 { return "ore_copper" }
        return "ore_coal"
    }

    var patches: [OrePatch] = []
    let guaranteedTypes: [ItemID] = ["ore_iron", "ore_copper", "ore_coal"]
    let guaranteedCount = min(patchCount, guaranteedTypes.count)
    for oreType in guaranteedTypes.prefix(guaranteedCount) {
        guard let position = pickPosition() else { break }
        placed.append(position)
        let richness = rollRichness()
        let totalOre = oreAmount(itemID: oreType, richness: richness)
        patches.append(
            OrePatch(
                id: patches.count + 1,
                oreType: oreType,
                richness: richness,
                position: position,
                totalOre: totalOre,
                remainingOre: totalOre
            )
        )
    }

    while patches.count < patchCount {
        guard let position = pickPosition() else { break }
        placed.append(position)
        let oreType = rollOreType()
        let richness = rollRichness()
        let totalOre = oreAmount(itemID: oreType, richness: richness)
        patches.append(
            OrePatch(
                id: patches.count + 1,
                oreType: oreType,
                richness: richness,
                position: position,
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
