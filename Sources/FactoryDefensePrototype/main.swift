import Foundation
import GameSimulation
import GamePlatform

let engine = SimulationEngine(worldState: .bootstrap())
let player = PlayerID(1)

engine.enqueue(
    PlayerCommand(
        tick: 1,
        actor: player,
        payload: .placeStructure(BuildRequest(structure: .turretMount, position: GridPosition(x: 5, y: 0)))
    )
)

engine.enqueue(
    PlayerCommand(
        tick: 2,
        actor: player,
        payload: .triggerWave
    )
)

let events = engine.run(ticks: 800)
let waveEvents = events.filter { $0.kind == .waveStarted }.count
let ammoSpent = events.filter { $0.kind == .ammoSpent }.reduce(0) { $0 + ($1.value ?? 0) }
let spawnedEnemies = events.filter { $0.kind == .enemySpawned }.count
let destroyedEnemies = events.filter { $0.kind == .enemyDestroyed }.count
let baseHits = events.filter { $0.kind == .enemyReachedBase }.count

print("FactoryDefensePrototype finished")
print("tick=\(engine.worldState.tick) waveEvents=\(waveEvents) ammoSpent=\(ammoSpent)")
print("enemiesSpawned=\(spawnedEnemies) enemiesDestroyed=\(destroyedEnemies) baseHits=\(baseHits)")
print("baseIntegrity=\(engine.worldState.hqHealth) currency=\(engine.worldState.economy.currency)")

let snapshotsDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".local_snapshots")
let store = FileSnapshotStore(directory: snapshotsDir)
let savedURL = try store.save(snapshot: engine.makeSnapshot(), name: "prototype_last")
print("snapshot=\(savedURL.path)")
