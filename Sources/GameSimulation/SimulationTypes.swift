import Foundation
import GameContent

public typealias EntityID = Int

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
}

public enum StructureType: String, Codable, CaseIterable, Sendable {
    case wall
    case turretMount
    case miner
    case smelter
    case assembler
    case ammoModule
    case powerPlant
    case conveyor
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
        case .turretMount, .powerPlant, .storage:
            return StructureFootprint(width: 2, height: 2)
        case .wall, .miner, .smelter, .assembler, .ammoModule, .conveyor:
            return StructureFootprint(width: 1, height: 1)
        }
    }

    func coveredCells(anchor: GridPosition) -> [GridPosition] {
        footprint.coveredCells(anchor: anchor)
    }

    var buildCosts: [ItemStack] {
        switch self {
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
        case .storage:
            return 1
        case .wall, .turretMount:
            return 0
        }
    }
}

public struct BuildRequest: Codable, Hashable, Sendable {
    public var structure: StructureType
    public var position: GridPosition

    public init(structure: StructureType, position: GridPosition) {
        self.structure = structure
        self.position = position
    }
}

public enum CommandPayload: Codable, Hashable, Sendable {
    case placeStructure(BuildRequest)
    case extract
    case triggerWave

    private enum CodingKeys: String, CodingKey {
        case kind
        case build
    }

    private enum Kind: String, Codable {
        case placeStructure
        case extract
        case triggerWave
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .placeStructure:
            self = .placeStructure(try container.decode(BuildRequest.self, forKey: .build))
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
        case .extract:
            try container.encode(Kind.extract, forKey: .kind)
        case .triggerWave:
            try container.encode(Kind.triggerWave, forKey: .kind)
        }
    }

    var sortToken: String {
        switch self {
        case .placeStructure(let build):
            return "place:\(build.structure.rawValue):\(build.position.x):\(build.position.y):\(build.position.z)"
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
    case waveStarted
    case waveEnded
    case raidTriggered
    case enemySpawned
    case enemyMoved
    case enemyReachedBase
    case enemyDestroyed
    case projectileFired
    case ammoSpent
    case notEnoughAmmo
    case milestoneReached
    case extracted
    case placementRejected
}

public struct SimEvent: Codable, Hashable, Sendable {
    public var tick: UInt64
    public var kind: EventKind
    public var entity: EntityID?
    public var value: Int?
    public var itemID: ItemID?

    public init(tick: UInt64, kind: EventKind, entity: EntityID? = nil, value: Int? = nil, itemID: ItemID? = nil) {
        self.tick = tick
        self.kind = kind
        self.entity = entity
        self.value = value
        self.itemID = itemID
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
    public var position: GridPosition
    public var health: Int
    public var maxHealth: Int

    public init(
        id: EntityID,
        category: EntityCategory,
        structureType: StructureType? = nil,
        turretDefID: String? = nil,
        position: GridPosition,
        health: Int,
        maxHealth: Int
    ) {
        self.id = id
        self.category = category
        self.structureType = structureType
        self.turretDefID = turretDefID
        self.position = position
        self.health = health
        self.maxHealth = maxHealth
    }
}

public enum EnemyArchetype: String, Codable, Sendable {
    case scout
    case raider
}

public struct EnemyRuntime: Codable, Hashable, Sendable {
    public var id: EntityID
    public var archetype: EnemyArchetype
    public var moveEveryTicks: UInt64
    public var baseDamage: Int
    public var rewardCurrency: Int

    public init(
        id: EntityID,
        archetype: EnemyArchetype,
        moveEveryTicks: UInt64,
        baseDamage: Int,
        rewardCurrency: Int
    ) {
        self.id = id
        self.archetype = archetype
        self.moveEveryTicks = moveEveryTicks
        self.baseDamage = baseDamage
        self.rewardCurrency = rewardCurrency
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

    public init(
        enemies: [EntityID: EnemyRuntime] = [:],
        projectiles: [EntityID: ProjectileRuntime] = [:],
        lastFireTickByTurret: [EntityID: UInt64] = [:],
        basePosition: GridPosition = .zero,
        spawnEdgeX: Int = 56,
        spawnYMin: Int = 27,
        spawnYMax: Int = 36
    ) {
        self.enemies = enemies
        self.projectiles = projectiles
        self.lastFireTickByTurret = lastFireTickByTurret
        self.basePosition = basePosition
        self.spawnEdgeX = spawnEdgeX
        self.spawnYMin = spawnYMin
        self.spawnYMax = spawnYMax
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

public struct EconomyState: Codable, Hashable, Sendable {
    public var inventories: [ItemID: Int]
    public var activeRecipeByStructure: [EntityID: String]
    public var productionProgressByStructure: [EntityID: Double]
    public var fractionalProductionRemainders: [ItemID: Double]
    public var powerAvailable: Int
    public var powerDemand: Int
    public var currency: Int
    public var telemetry: EconomyTelemetry

    public init(
        inventories: [ItemID: Int] = [:],
        activeRecipeByStructure: [EntityID: String] = [:],
        productionProgressByStructure: [EntityID: Double] = [:],
        fractionalProductionRemainders: [ItemID: Double] = [:],
        powerAvailable: Int = 0,
        powerDemand: Int = 0,
        currency: Int = 0,
        telemetry: EconomyTelemetry = .init()
    ) {
        self.inventories = inventories
        self.activeRecipeByStructure = activeRecipeByStructure
        self.productionProgressByStructure = productionProgressByStructure
        self.fractionalProductionRemainders = fractionalProductionRemainders
        self.powerAvailable = powerAvailable
        self.powerDemand = powerDemand
        self.currency = currency
        self.telemetry = telemetry
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
    public var raidCooldownUntilTick: UInt64
    public var milestoneEvery: Int
    public var lastMilestoneWave: Int

    public init(
        waveIndex: Int = 0,
        nextWaveTick: UInt64 = 400,
        waveIntervalTicks: UInt64 = 400,
        waveDurationTicks: UInt64 = 160,
        waveEndsAtTick: UInt64? = nil,
        isWaveActive: Bool = false,
        raidCooldownUntilTick: UInt64 = 0,
        milestoneEvery: Int = 5,
        lastMilestoneWave: Int = 0
    ) {
        self.waveIndex = waveIndex
        self.nextWaveTick = nextWaveTick
        self.waveIntervalTicks = waveIntervalTicks
        self.waveDurationTicks = waveDurationTicks
        self.waveEndsAtTick = waveEndsAtTick
        self.isWaveActive = isWaveActive
        self.raidCooldownUntilTick = raidCooldownUntilTick
        self.milestoneEvery = milestoneEvery
        self.lastMilestoneWave = lastMilestoneWave
    }
}

public struct RunState: Codable, Hashable, Sendable {
    public var baseIntegrity: Int
    public var extracted: Bool
    public var gameOver: Bool

    public init(baseIntegrity: Int = 100, extracted: Bool = false, gameOver: Bool = false) {
        self.baseIntegrity = baseIntegrity
        self.extracted = extracted
        self.gameOver = gameOver
    }
}

public struct WorldState: Codable, Hashable, Sendable {
    public var tick: UInt64
    public var board: BoardState
    public var entities: EntityStore
    public var economy: EconomyState
    public var threat: ThreatState
    public var run: RunState
    public var combat: CombatState

    public init(
        tick: UInt64,
        board: BoardState = .bootstrap(),
        entities: EntityStore,
        economy: EconomyState,
        threat: ThreatState,
        run: RunState,
        combat: CombatState = CombatState()
    ) {
        self.tick = tick
        self.board = board
        self.entities = entities
        self.economy = economy
        self.threat = threat
        self.run = run
        self.combat = combat
    }

    public static func bootstrap() -> WorldState {
        let board = BoardState.bootstrap()
        var store = EntityStore()
        _ = store.spawnStructure(.powerPlant, at: GridPosition(x: 39, y: 30))
        _ = store.spawnStructure(.miner, at: GridPosition(x: 40, y: 30))
        _ = store.spawnStructure(.smelter, at: GridPosition(x: 41, y: 30))
        _ = store.spawnStructure(.ammoModule, at: GridPosition(x: 42, y: 30))
        _ = store.spawnStructure(.turretMount, at: GridPosition(x: 43, y: 31))
        _ = store.spawnStructure(.turretMount, at: GridPosition(x: 43, y: 33))

        var startupPowerAvailable = 0
        var startupPowerDemand = 0
        for structure in store.all where structure.category == .structure {
            guard let structureType = structure.structureType else { continue }
            let demand = structureType.powerDemand
            if demand < 0 {
                startupPowerAvailable += abs(demand)
            } else {
                startupPowerDemand += demand
            }
        }

        return WorldState(
            tick: 0,
            board: board,
            entities: store,
            economy: EconomyState(
                inventories: [
                    "ore_iron": 10,
                    "ammo_light": 80,
                    // Starter construction stock prevents early-game deadlock
                    // while recipe pinning and richer logistics are still pending.
                    "plate_iron": 12,
                    "plate_copper": 4,
                    "plate_steel": 4,
                    "gear": 6,
                    "circuit": 4
                ],
                powerAvailable: startupPowerAvailable,
                powerDemand: startupPowerDemand
            ),
            threat: ThreatState(),
            run: RunState(),
            combat: CombatState(
                basePosition: board.basePosition,
                spawnEdgeX: board.spawnEdgeX,
                spawnYMin: board.spawnYMin,
                spawnYMax: board.spawnYMax
            )
        )
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
