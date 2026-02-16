import Foundation

public typealias ItemID = String
public typealias UnlockID = String
public typealias EnemyID = String

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

    public init(id: String, ammoType: AmmoType, fireRate: Float, range: Float) {
        self.id = id
        self.ammoType = ammoType
        self.fireRate = fireRate
        self.range = range
    }
}

public struct EnemyDef: Codable, Hashable, Sendable {
    public var id: EnemyID
    public var health: Int
    public var speed: Float
    public var threatCost: Int

    public init(id: EnemyID, health: Int, speed: Float, threatCost: Int) {
        self.id = id
        self.health = health
        self.speed = speed
        self.threatCost = threatCost
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

public struct GameContentBundle: Codable, Sendable {
    public var items: [ItemDef]
    public var recipes: [RecipeDef]
    public var turrets: [TurretDef]
    public var enemies: [EnemyDef]
    public var waves: [WaveDef]
    public var techNodes: [TechNodeDef]

    public init(
        items: [ItemDef],
        recipes: [RecipeDef],
        turrets: [TurretDef],
        enemies: [EnemyDef],
        waves: [WaveDef],
        techNodes: [TechNodeDef]
    ) {
        self.items = items
        self.recipes = recipes
        self.turrets = turrets
        self.enemies = enemies
        self.waves = waves
        self.techNodes = techNodes
    }

    public static let empty = GameContentBundle(
        items: [],
        recipes: [],
        turrets: [],
        enemies: [],
        waves: [],
        techNodes: []
    )
}

public extension GameContentBundle {
    var itemIDs: Set<ItemID> { Set(items.map(\.id)) }
    var enemyIDs: Set<EnemyID> { Set(enemies.map(\.id)) }
    var techNodeIDs: Set<UnlockID> { Set(techNodes.map(\.id)) }
}
