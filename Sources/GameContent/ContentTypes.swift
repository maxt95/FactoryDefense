import Foundation

public typealias ItemID = String
public typealias UnlockID = String
public typealias EnemyID = String

public enum DifficultyID: String, Codable, CaseIterable, Sendable {
    case easy
    case normal
    case hard
}

public enum ItemKind: String, Codable, CaseIterable, Sendable {
    case raw
    case processed
    case ammo
    case utility
}

public struct ItemDef: Codable, Hashable, Sendable {
    public var id: ItemID
    public var name: String
    public var kind: ItemKind

    public init(id: ItemID, name: String, kind: ItemKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public struct ItemStack: Codable, Hashable, Sendable {
    public var itemID: ItemID
    public var quantity: Int

    public init(itemID: ItemID, quantity: Int) {
        self.itemID = itemID
        self.quantity = quantity
    }
}

public enum ItemFilter: Hashable, Sendable {
    case any
    case allow(Set<ItemID>)
}

extension ItemFilter: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case items
    }

    private enum Kind: String, Codable {
        case any
        case allow
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .any:
            self = .any
        case .allow:
            let items = try container.decode([ItemID].self, forKey: .items)
            self = .allow(Set(items))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .any:
            try container.encode(Kind.any, forKey: .kind)
        case .allow(let itemIDs):
            try container.encode(Kind.allow, forKey: .kind)
            try container.encode(Array(itemIDs).sorted(), forKey: .items)
        }
    }
}

public enum PortDirection: String, Codable, CaseIterable, Sendable {
    case north
    case east
    case south
    case west
}

public enum PortMode: String, Codable, CaseIterable, Sendable {
    case input
    case output
    case bidirectional
}

public struct PortDef: Codable, Hashable, Sendable {
    public var id: String
    public var direction: PortDirection
    public var mode: PortMode
    public var filter: ItemFilter
    public var bufferCapacity: Int

    public init(
        id: String,
        direction: PortDirection,
        mode: PortMode,
        filter: ItemFilter = .any,
        bufferCapacity: Int = 1
    ) {
        self.id = id
        self.direction = direction
        self.mode = mode
        self.filter = filter
        self.bufferCapacity = max(1, bufferCapacity)
    }
}

public struct BuildingFootprintDef: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct BuildingDef: Codable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var footprint: BuildingFootprintDef
    public var powerDraw: Int
    public var buildCosts: [ItemStack]
    public var ports: [PortDef]

    public init(
        id: String,
        displayName: String,
        footprint: BuildingFootprintDef,
        powerDraw: Int,
        buildCosts: [ItemStack],
        ports: [PortDef]
    ) {
        self.id = id
        self.displayName = displayName
        self.footprint = footprint
        self.powerDraw = powerDraw
        self.buildCosts = buildCosts
        self.ports = ports
    }
}

public enum AmmoType: String, Codable, CaseIterable, Sendable {
    case lightBallistic
    case heavyBallistic
    case plasma
}

public struct RecipeDef: Codable, Hashable, Sendable {
    public var id: String
    public var inputs: [ItemStack]
    public var outputs: [ItemStack]
    public var seconds: Float

    public init(id: String, inputs: [ItemStack], outputs: [ItemStack], seconds: Float) {
        self.id = id
        self.inputs = inputs
        self.outputs = outputs
        self.seconds = seconds
    }
}

public struct TurretDef: Codable, Hashable, Sendable {
    public var id: String
    public var ammoType: AmmoType
    public var fireRate: Float
    public var range: Float
    public var damage: Int

    public init(id: String, ammoType: AmmoType, fireRate: Float, range: Float, damage: Int) {
        self.id = id
        self.ammoType = ammoType
        self.fireRate = fireRate
        self.range = range
        self.damage = damage
    }
}

public enum EnemyBehaviorModifier: String, Codable, CaseIterable, Sendable {
    case none
    case structureSeeker
    case wallBreaker
    case auraBuffer
}

public struct EnemyDef: Codable, Hashable, Sendable {
    public var id: EnemyID
    public var health: Int
    public var speed: Float
    public var threatCost: Int
    public var baseDamage: Int
    public var behaviorModifier: EnemyBehaviorModifier
    public var wallDamageMultiplier: Double?
    public var minBudgetToSpawn: Int

    public init(
        id: EnemyID,
        health: Int,
        speed: Float,
        threatCost: Int,
        baseDamage: Int? = nil,
        behaviorModifier: EnemyBehaviorModifier = .none,
        wallDamageMultiplier: Double? = nil,
        minBudgetToSpawn: Int = 0
    ) {
        self.id = id
        self.health = health
        self.speed = speed
        self.threatCost = threatCost
        self.baseDamage = baseDamage ?? max(1, threatCost)
        self.behaviorModifier = behaviorModifier
        self.wallDamageMultiplier = wallDamageMultiplier
        self.minBudgetToSpawn = max(0, minBudgetToSpawn)
    }
}

public struct EnemyGroup: Codable, Hashable, Sendable {
    public var enemyID: EnemyID
    public var count: Int
    public var delayTicks: UInt64

    public init(enemyID: EnemyID, count: Int, delayTicks: UInt64) {
        self.enemyID = enemyID
        self.count = count
        self.delayTicks = delayTicks
    }
}

public struct WaveDef: Codable, Hashable, Sendable {
    public var index: Int
    public var spawnBudget: Int
    public var composition: [EnemyGroup]

    public init(index: Int, spawnBudget: Int, composition: [EnemyGroup]) {
        self.index = index
        self.spawnBudget = spawnBudget
        self.composition = composition
    }
}

public struct ProceduralWaveFormulaDef: Codable, Hashable, Sendable {
    public var base: Int
    public var linear: Int
    public var quadratic: Double

    public init(base: Int, linear: Int, quadratic: Double) {
        self.base = base
        self.linear = linear
        self.quadratic = quadratic
    }
}

public struct WaveDifficultyMultipliersDef: Codable, Hashable, Sendable {
    public var easy: Double
    public var normal: Double
    public var hard: Double

    public init(easy: Double, normal: Double, hard: Double) {
        self.easy = easy
        self.normal = normal
        self.hard = hard
    }

    public func value(for difficulty: DifficultyID) -> Double {
        switch difficulty {
        case .easy:
            return easy
        case .normal:
            return normal
        case .hard:
            return hard
        }
    }
}

public struct ProceduralWaveConfigDef: Codable, Hashable, Sendable {
    public var budgetFormula: ProceduralWaveFormulaDef
    public var swarmlingReserveRatio: Double
    public var difficultyMultipliers: WaveDifficultyMultipliersDef

    public init(
        budgetFormula: ProceduralWaveFormulaDef,
        swarmlingReserveRatio: Double,
        difficultyMultipliers: WaveDifficultyMultipliersDef
    ) {
        self.budgetFormula = budgetFormula
        self.swarmlingReserveRatio = swarmlingReserveRatio
        self.difficultyMultipliers = difficultyMultipliers
    }

    public static let v1Default = ProceduralWaveConfigDef(
        budgetFormula: ProceduralWaveFormulaDef(base: 10, linear: 4, quadratic: 0.5),
        swarmlingReserveRatio: 0.3,
        difficultyMultipliers: WaveDifficultyMultipliersDef(easy: 0.85, normal: 1.0, hard: 1.15)
    )
}

public struct WaveContentDef: Codable, Hashable, Sendable {
    public var handAuthoredWaves: [WaveDef]
    public var proceduralConfig: ProceduralWaveConfigDef

    public init(
        handAuthoredWaves: [WaveDef],
        proceduralConfig: ProceduralWaveConfigDef = .v1Default
    ) {
        self.handAuthoredWaves = handAuthoredWaves
        self.proceduralConfig = proceduralConfig
    }
}

public struct TechNodeDef: Codable, Hashable, Sendable {
    public var id: String
    public var costs: [ItemStack]
    public var prerequisites: [UnlockID]
    public var unlocks: [UnlockID]

    public init(id: String, costs: [ItemStack], prerequisites: [UnlockID], unlocks: [UnlockID]) {
        self.id = id
        self.costs = costs
        self.prerequisites = prerequisites
        self.unlocks = unlocks
    }
}

public struct BoardPointDef: Codable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var z: Int

    public init(x: Int, y: Int, z: Int = 0) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct BoardRampDef: Codable, Hashable, Sendable {
    public var position: BoardPointDef
    public var elevation: Int

    public init(position: BoardPointDef, elevation: Int) {
        self.position = position
        self.elevation = elevation
    }
}

public struct BoardDef: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    public var basePosition: BoardPointDef
    public var spawnEdgeX: Int
    public var spawnYMin: Int
    public var spawnYMax: Int
    public var blockedCells: [BoardPointDef]
    public var restrictedCells: [BoardPointDef]
    public var ramps: [BoardRampDef]

    public init(
        width: Int,
        height: Int,
        basePosition: BoardPointDef,
        spawnEdgeX: Int,
        spawnYMin: Int,
        spawnYMax: Int,
        blockedCells: [BoardPointDef] = [],
        restrictedCells: [BoardPointDef] = [],
        ramps: [BoardRampDef] = []
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

    public static let starter = BoardDef(
        width: 96,
        height: 64,
        basePosition: BoardPointDef(x: 40, y: 32, z: 0),
        spawnEdgeX: 56,
        spawnYMin: 27,
        spawnYMax: 36,
        blockedCells: [],
        restrictedCells: [
            BoardPointDef(x: 39, y: 31),
            BoardPointDef(x: 40, y: 31),
            BoardPointDef(x: 39, y: 32),
            BoardPointDef(x: 40, y: 32)
        ],
        ramps: [
            BoardRampDef(position: BoardPointDef(x: 47, y: 31), elevation: 1),
            BoardRampDef(position: BoardPointDef(x: 47, y: 32), elevation: 1),
            BoardRampDef(position: BoardPointDef(x: 47, y: 33), elevation: 1)
        ]
    )
}

public struct HQFootprintDef: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct HQStartingResourcesDef: Codable, Hashable, Sendable {
    public var easy: [ItemID: Int]
    public var normal: [ItemID: Int]
    public var hard: [ItemID: Int]

    public init(easy: [ItemID: Int], normal: [ItemID: Int], hard: [ItemID: Int]) {
        self.easy = easy
        self.normal = normal
        self.hard = hard
    }

    public func values(for difficulty: DifficultyID) -> [ItemID: Int] {
        switch difficulty {
        case .easy:
            return easy
        case .normal:
            return normal
        case .hard:
            return hard
        }
    }
}

public struct HQDef: Codable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var footprint: HQFootprintDef
    public var health: Int
    public var storageCapacity: Int
    public var powerDraw: Int
    public var startingResources: HQStartingResourcesDef

    public init(
        id: String,
        displayName: String,
        footprint: HQFootprintDef,
        health: Int,
        storageCapacity: Int,
        powerDraw: Int,
        startingResources: HQStartingResourcesDef
    ) {
        self.id = id
        self.displayName = displayName
        self.footprint = footprint
        self.health = health
        self.storageCapacity = storageCapacity
        self.powerDraw = powerDraw
        self.startingResources = startingResources
    }

    public static let v1Default = HQDef(
        id: "hq",
        displayName: "Headquarters",
        footprint: HQFootprintDef(width: 2, height: 2),
        health: 500,
        storageCapacity: 24,
        powerDraw: 0,
        startingResources: HQStartingResourcesDef(
            easy: [
                "ore_iron": 30,
                "ore_copper": 20,
                "ore_coal": 10,
                "plate_iron": 18,
                "plate_copper": 8,
                "plate_steel": 10,
                "gear": 5,
                "circuit": 5,
                "turret_core": 2,
                "wall_kit": 8,
                "ammo_light": 24
            ],
            normal: [
                "ore_iron": 20,
                "ore_copper": 12,
                "ore_coal": 6,
                "plate_iron": 14,
                "plate_copper": 6,
                "plate_steel": 8,
                "gear": 4,
                "circuit": 4,
                "turret_core": 1,
                "wall_kit": 6,
                "ammo_light": 16
            ],
            hard: [
                "ore_iron": 12,
                "ore_copper": 8,
                "ore_coal": 4,
                "plate_iron": 10,
                "plate_copper": 4,
                "plate_steel": 6,
                "gear": 3,
                "circuit": 2,
                "turret_core": 1,
                "wall_kit": 3,
                "ammo_light": 8
            ]
        )
    )
}

public struct DifficultyDef: Codable, Hashable, Sendable {
    public var gracePeriodSeconds: Int
    public var interWaveGapBase: Int
    public var interWaveGapFloor: Int
    public var gapCompressionPerWave: Int
    public var trickleIntervalSeconds: Int
    public var trickleSize: [Int]
    public var waveBudgetMultiplier: Double

    public init(
        gracePeriodSeconds: Int,
        interWaveGapBase: Int,
        interWaveGapFloor: Int,
        gapCompressionPerWave: Int,
        trickleIntervalSeconds: Int,
        trickleSize: [Int],
        waveBudgetMultiplier: Double
    ) {
        self.gracePeriodSeconds = gracePeriodSeconds
        self.interWaveGapBase = interWaveGapBase
        self.interWaveGapFloor = interWaveGapFloor
        self.gapCompressionPerWave = gapCompressionPerWave
        self.trickleIntervalSeconds = trickleIntervalSeconds
        self.trickleSize = trickleSize
        self.waveBudgetMultiplier = waveBudgetMultiplier
    }
}

public struct DifficultyConfigDef: Codable, Hashable, Sendable {
    public var easy: DifficultyDef
    public var normal: DifficultyDef
    public var hard: DifficultyDef

    public init(easy: DifficultyDef, normal: DifficultyDef, hard: DifficultyDef) {
        self.easy = easy
        self.normal = normal
        self.hard = hard
    }

    public func values(for difficulty: DifficultyID) -> DifficultyDef {
        switch difficulty {
        case .easy:
            return easy
        case .normal:
            return normal
        case .hard:
            return hard
        }
    }

    public static let v1Default = DifficultyConfigDef(
        easy: DifficultyDef(
            gracePeriodSeconds: 180,
            interWaveGapBase: 120,
            interWaveGapFloor: 70,
            gapCompressionPerWave: 2,
            trickleIntervalSeconds: 15,
            trickleSize: [1, 1],
            waveBudgetMultiplier: 0.85
        ),
        normal: DifficultyDef(
            gracePeriodSeconds: 120,
            interWaveGapBase: 90,
            interWaveGapFloor: 50,
            gapCompressionPerWave: 2,
            trickleIntervalSeconds: 12,
            trickleSize: [1, 2],
            waveBudgetMultiplier: 1.0
        ),
        hard: DifficultyDef(
            gracePeriodSeconds: 60,
            interWaveGapBase: 60,
            interWaveGapFloor: 35,
            gapCompressionPerWave: 2,
            trickleIntervalSeconds: 8,
            trickleSize: [2, 3],
            waveBudgetMultiplier: 1.15
        )
    )
}

public struct GameContentBundle: Codable, Sendable {
    public var items: [ItemDef]
    public var recipes: [RecipeDef]
    public var turrets: [TurretDef]
    public var enemies: [EnemyDef]
    public var waveContent: WaveContentDef
    public var techNodes: [TechNodeDef]
    public var board: BoardDef
    public var hq: HQDef
    public var difficulty: DifficultyConfigDef
    public var buildings: [BuildingDef]

    public init(
        items: [ItemDef],
        recipes: [RecipeDef],
        turrets: [TurretDef],
        enemies: [EnemyDef],
        waves: [WaveDef],
        techNodes: [TechNodeDef],
        board: BoardDef = .starter,
        hq: HQDef = .v1Default,
        difficulty: DifficultyConfigDef = .v1Default,
        buildings: [BuildingDef] = []
    ) {
        self.items = items
        self.recipes = recipes
        self.turrets = turrets
        self.enemies = enemies
        self.waveContent = WaveContentDef(handAuthoredWaves: waves)
        self.techNodes = techNodes
        self.board = board
        self.hq = hq
        self.difficulty = difficulty
        self.buildings = buildings
    }

    public init(
        items: [ItemDef],
        recipes: [RecipeDef],
        turrets: [TurretDef],
        enemies: [EnemyDef],
        waveContent: WaveContentDef,
        techNodes: [TechNodeDef],
        board: BoardDef = .starter,
        hq: HQDef = .v1Default,
        difficulty: DifficultyConfigDef = .v1Default,
        buildings: [BuildingDef] = []
    ) {
        self.items = items
        self.recipes = recipes
        self.turrets = turrets
        self.enemies = enemies
        self.waveContent = waveContent
        self.techNodes = techNodes
        self.board = board
        self.hq = hq
        self.difficulty = difficulty
        self.buildings = buildings
    }

    public var waves: [WaveDef] {
        waveContent.handAuthoredWaves
    }

    public static let empty = GameContentBundle(
        items: [],
        recipes: [],
        turrets: [],
        enemies: [],
        waveContent: WaveContentDef(handAuthoredWaves: []),
        techNodes: [],
        board: .starter,
        hq: .v1Default,
        difficulty: .v1Default,
        buildings: []
    )
}

public extension GameContentBundle {
    var itemIDs: Set<ItemID> { Set(items.map(\.id)) }
    var enemyIDs: Set<EnemyID> { Set(enemies.map(\.id)) }
    var techNodeIDs: Set<UnlockID> { Set(techNodes.map(\.id)) }
}
