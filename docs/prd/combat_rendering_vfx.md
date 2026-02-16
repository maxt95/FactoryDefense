# Combat, Rendering & VFX PRD

**Version:** 1.0-draft
**Parent:** `docs/GAME_PRD_LIVING.md`
**Status:** Forward-looking v1 design
**Last updated:** 2026-02-15

> **Core truth:** Visual clarity at scale. Thousands of entities — enemies, projectiles, particles — must be simultaneously readable, performant, and deterministic. The simulation owns all gameplay truth on the CPU; the GPU owns all visual presentation. Nothing the GPU does affects game state.

**Companion docs:**
- [`factory_economy.md`](factory_economy.md) — turret type stats (section 7.3), ammo consumption rates, production chain coupling
- [`building_specifications.md`](building_specifications.md) — per-building specs, ammo buffer/pool model for turret feeding

---

## Table of Contents

1. [Overview & Design Intent](#1-overview--design-intent)
2. [Simulation Architecture](#2-simulation-architecture)
3. [Projectile Physics](#3-projectile-physics)
4. [Enemy Movement](#4-enemy-movement)
5. [Combat System](#5-combat-system)
6. [Interpolation Bridge](#6-interpolation-bridge)
7. [GPU Rendering Pipeline](#7-gpu-rendering-pipeline)
8. [GPU Particle System](#8-gpu-particle-system)
9. [Metal Shader Architecture](#9-metal-shader-architecture)
10. [Performance Budget](#10-performance-budget)
11. [Determinism Guarantees](#11-determinism-guarantees)
12. [Implementation Roadmap](#12-implementation-roadmap)
- [Appendix A: New File Summary](#appendix-a-new-file-summary)
- [Appendix B: Modified File Summary](#appendix-b-modified-file-summary)
- [Appendix C: Implementation Priority Matrix](#appendix-c-implementation-priority-matrix)

---

## Terminology

| Term | Definition |
|------|-----------|
| **SimPosition** | Continuous float-precision grid-space coordinate (x, y, z). Replaces integer `GridPosition` for moving entities |
| **Flow field** | A precomputed vector field covering the entire grid. Each cell stores a direction toward the goal. All enemies sample from the same field |
| **Spatial grid** | A uniform grid acceleration structure that buckets entity IDs by cell for O(1) neighbor queries |
| **Instance buffer** | A GPU buffer containing per-entity data (position, color, scale) for instanced draw calls |
| **Particle pool** | A fixed-size GPU buffer of `GPUParticle` structs. Dead particles are overwritten by new emissions |
| **Emission command** | A CPU-to-GPU instruction to spawn N particles at a position with given parameters |
| **Billboard** | A screen-facing quad used for projectiles, particles, and small enemies |
| **Quality preset** | One of `mobileBalanced`, `tabletHigh`, `macCinematic` — controls particle counts, instance limits, and post-processing |
| **VFX event** | A simulation event (e.g., `projectileFired`, `enemyDestroyed`) that triggers visual-only particle effects |
| **Triple-buffering** | Three rotating GPU buffers so CPU can fill frame N+1 while GPU renders frame N |

---

## 1. Overview & Design Intent

### 1.1 Why This System Exists

The current simulation and renderer have fundamental scaling limitations:

- **EntityStore** uses a flat `[EntityID: Entity]` dictionary with no spatial structure. `enemies()` sorts the full array by ID every call — O(n log n) per query.
- **CombatSystem** finds targets by calling `enemies()` (full sort), then `.filter` by Manhattan distance, then `.min`. For T turrets and E enemies: O(T × E log E) per tick.
- **Projectiles** are fire-and-forget. `ProjectileRuntime` stores only an `impactTick` — no position, velocity, or physical travel. Damage teleports to the target on the impact tick.
- **Enemy movement** creates a new `Pathfinder()` and rebuilds the full `navigationMap` (6,144+ tiles) every single tick. Each enemy runs independent A*. At 1000 enemies this is catastrophic.
- **Enemy positions** are integer `GridPosition` — movement appears jerky at 20 Hz with no sub-grid precision.
- **WhiteboxRenderer** allocates fresh Metal buffers every frame and runs a compute kernel that loops over ALL structures and ALL entities per pixel. At 1920×1080 with 150 entities: 311M iterations per frame.
- **No interpolation** of entity positions between ticks — `InterpolatedWorldFrame` only blends scalar values (integrity).

### 1.2 Target Scale

- **1000+ simultaneous enemies** with smooth sub-grid movement
- **500+ simultaneous projectiles** with real physical travel and collision detection
- **65,536 GPU particles** (macCinematic) for muzzle flash, trails, impacts, death bursts, environmental effects
- **60 FPS** on all quality presets with >9ms headroom per frame

### 1.3 Design Pillars

**Visual clarity at density.** When 200 enemies swarm through a killzone with 8 turrets firing, the player must be able to read: where enemies are coming from, which turrets are active, where damage is landing, and which enemies are about to reach the base.

**Co-op determinism.** All gameplay truth lives on the CPU in the deterministic simulation loop. Two clients with identical command streams must produce identical `WorldState` snapshots. The GPU handles visual-only effects — particles, trails, screen-space distortion — that do not feed back into simulation.

**Vampire Survivors density.** The target aesthetic is controlled chaos: massive entity counts rendered efficiently via instancing, with GPU particles providing visual weight to combat events.

### 1.4 Implementation Status

| Aspect | Status |
|--------|--------|
| Entity spatial indexing | Gap — flat dictionary, O(n) scans |
| Continuous entity positions | Gap — integer GridPosition only |
| Real projectile physics | Gap — fire-and-forget impactTick model |
| Flow field pathfinding | Gap — per-enemy A* rebuilt every tick |
| Entity position interpolation | Gap — only scalar interpolation |
| Instanced rendering | Gap — per-pixel compute loop |
| GPU particle system | Gap — no particle system exists |
| Quality-scaled rendering | Gap — empty pass node stubs |

---

## 2. Simulation Architecture

### 2.1 Design Intent

Moving entities (enemies, projectiles) need continuous float-precision positions for smooth movement, accurate collision detection, and interpolated rendering. The simulation must support spatial queries (find enemies near turret) in O(1) amortized time rather than O(n).

### 2.2 SimPosition

A continuous grid-space coordinate that replaces integer `GridPosition` for all moving entities:

```swift
public struct SimPosition: Codable, Hashable, Sendable {
    public var x: Float  // continuous grid-space coordinate
    public var y: Float
    public var z: Float  // elevation (typically 0 for ground entities)

    public var gridPosition: GridPosition {
        GridPosition(x: Int(x.rounded(.down)), y: Int(y.rounded(.down)), z: Int(z.rounded(.down)))
    }

    public init(from grid: GridPosition) {
        self.x = Float(grid.x) + 0.5  // center of cell
        self.y = Float(grid.y) + 0.5
        self.z = Float(grid.z)
    }

    public func distanceSquared(to other: SimPosition) -> Float {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }

    public func distance(to other: SimPosition) -> Float {
        distanceSquared(to: other).squareRoot()
    }
}
```

**Determinism note:** All `Float` operations on Apple ARM64 are IEEE 754 compliant and deterministic given identical inputs and compilation settings. For future cross-architecture co-op, fixed-point arithmetic would be needed, but that is out of scope for v1.

### 2.3 Spatial Grid

A uniform grid acceleration structure for O(1) neighbor queries. Rebuilt from scratch each tick (O(n) rebuild is trivial at 20 Hz with 1000 entities).

```swift
public struct SpatialGrid<T> {
    public let width: Int
    public let height: Int
    private var cells: [[T]]  // flat array, index = y * width + x

    public mutating func insert(_ item: T, atX x: Int, y: Int)
    public mutating func clear()  // removeAll(keepingCapacity: true) per cell
    public func query(minX: Int, maxX: Int, minY: Int, maxY: Int) -> [T]
    public func queryRadius(center: SimPosition, radius: Float) -> [T]
}
```

**Memory:** For a 512×512 grid: 262,144 empty arrays × 8 bytes = ~2 MB. Acceptable.

**Rebuild strategy:** Cleared and rebuilt from entity runtimes each tick. Not maintained incrementally.

### 2.4 Enhanced Entity Runtimes

The existing `EnemyRuntime` and `ProjectileRuntime` are extended with continuous position and movement data. See sections 3 and 4 for full type definitions.

**CombatState extensions:**

```swift
public var projectiles: [EntityID: ProjectileRuntime]
public var flowField: FlowField?
public var flowFieldDirty: Bool  // set true when navigation map changes
```

### 2.5 Implementation Status

| Aspect | Status |
|--------|--------|
| `SimPosition` type | Gap — only integer `GridPosition` exists |
| `SpatialGrid` | Gap — no spatial acceleration structure |
| Continuous enemy positions | Gap — `EnemyRuntime` uses integer positions |
| Continuous projectile positions | Gap — `ProjectileRuntime` has no position |
| `CombatState.projectiles` dictionary | Gap — projectiles tracked only by impactTick |

### 2.6 Open Questions

- Should the spatial grid cell size match the game grid 1:1, or use coarser cells (e.g., 2×2 or 4×4) for fewer buckets?
  - Recommendation: 1:1 for v1. Memory is acceptable and keeps queries simple. Profile and coarsen if needed.
- When should struct-of-arrays (SoA) layout replace the current dictionary-based storage?
  - Recommendation: defer until profiling shows AoS is the bottleneck. Spatial grid and flow field provide the largest wins.

---

## 3. Projectile Physics

### 3.1 Design Intent

Projectiles physically travel through space each tick. They can miss if the target moves. This creates emergent gameplay: fast enemies dodge slow projectiles, homing missiles track targets, and artillery arcs over walls. Real travel also enables visible projectile trails and satisfying impact VFX at the actual collision point.

### 3.2 ProjectileType Enum

```swift
public enum ProjectileType: UInt8, Codable, Hashable, Sendable {
    case ballistic = 0    // straight line, constant speed
    case homing = 1       // tracks target, curves toward it
    case arcing = 2       // parabolic arc (mortars/artillery)
}
```

### 3.3 ProjectileRuntime

```swift
public struct ProjectileRuntime: Codable, Hashable, Sendable {
    public var id: EntityID
    public var sourceTurretID: EntityID
    public var targetEnemyID: EntityID    // for homing; ignored for ballistic after launch
    public var damage: Int
    public var projectileType: ProjectileType

    // Physics state (continuous)
    public var position: SimPosition
    public var velocity: SIMD2<Float>     // grid-units per tick
    public var speed: Float               // magnitude, grid-units per tick

    // Arcing only
    public var arcPeakHeight: Float       // peak height of parabolic arc
    public var arcProgress: Float         // 0..1 along arc

    // Lifetime
    public var spawnTick: UInt64
    public var maxLifetimeTicks: UInt64   // auto-despawn after this many ticks
    public var collisionRadius: Float     // grid-units, typically 0.3-0.5

    // Visual data (copied to interpolation bridge)
    public var sourcePosition: SimPosition  // where it was fired from (for trail rendering)
}
```

**Size:** ~88 bytes per projectile. At 1000 simultaneous projectiles: 88 KB.

### 3.4 Movement Per Tick

**Ballistic** — straight line, constant speed:
```swift
projectile.position.x += projectile.velocity.x
projectile.position.y += projectile.velocity.y
```

**Homing** — adjusts velocity toward target each tick:
```swift
let toTarget = SIMD2<Float>(
    targetRuntime.position.x - projectile.position.x,
    targetRuntime.position.y - projectile.position.y
)
let desired = normalize(toTarget) * projectile.speed
let turnRate: Float = 0.15
projectile.velocity += (desired - projectile.velocity) * turnRate
projectile.velocity = normalize(projectile.velocity) * projectile.speed  // maintain speed
projectile.position.x += projectile.velocity.x
projectile.position.y += projectile.velocity.y
```

**Arcing** — parabolic arc with z-height:
```swift
projectile.arcProgress += 1.0 / Float(projectile.maxLifetimeTicks)
projectile.position.x += projectile.velocity.x
projectile.position.y += projectile.velocity.y
let t = projectile.arcProgress
projectile.position.z = projectile.arcPeakHeight * 4.0 * t * (1.0 - t)
```

### 3.5 Collision Detection

Per tick, for each live projectile:

1. **Out-of-bounds check:** if position is > 2 cells outside board bounds, despawn.
2. **Spatial grid query:** `enemyGrid.queryRadius(center: projectile.position, radius: projectile.collisionRadius + 1.0)`
3. **Distance check:** for each candidate enemy, check `distanceSquared < (projectile.collisionRadius + 0.5)²` (enemy has ~0.5 radius).
4. **On hit:** apply damage, emit `projectileImpact` event with position, despawn projectile.
5. **On lifetime expiry:** emit `projectileMissed` event, despawn.

### 3.6 Key Constants

| Parameter | Value | Notes |
|-----------|-------|-------|
| Default projectile speed | 2.0 grid-units/tick | 40 grid-units/second at 20 Hz |
| Default max lifetime | 40 ticks | 2 seconds |
| Default collision radius | 0.4 grid-units | |
| Enemy collision radius | ~0.5 grid-units | |
| Homing turn rate | 0.15 | Lerp factor per tick |
| Arc peak height | Varies by turret | Typically 2.0-4.0 grid-units |

### 3.7 Implementation Status

| Aspect | Status |
|--------|--------|
| `ProjectileType` enum | Gap — no type distinction |
| Real projectile positions | Gap — `ProjectileRuntime` has no position/velocity |
| Per-tick projectile movement | Gap — fire-and-forget model |
| Collision detection | Gap — damage teleports on impactTick |
| Homing behavior | Gap |
| Arcing behavior | Gap |
| `projectileImpact` / `projectileMissed` events | Gap — only `projectileFired` exists |

### 3.8 Open Questions

- Should ballistic projectiles have a small homing correction (aim-assist) to prevent excessive misses at long range?
  - Recommendation: no for v1. Missing is intentional gameplay — fast enemies are harder to hit. Balance via fire rate and projectile speed.
- Should arcing projectiles deal area-of-effect damage on impact?
  - Recommendation: yes as a future enhancement. For v1, single-target damage at the impact point.

---

## 4. Enemy Movement

### 4.1 Design Intent

All enemies share a single precomputed flow field instead of running individual A*. This drops pathfinding cost from O(enemies × grid²) to O(grid²) (computed once when the map changes) plus O(enemies) per tick for movement. Enemies move in continuous sub-grid space for smooth visual presentation.

### 4.2 Flow Field Pathfinding

A flow field is a grid-sized data structure where each cell stores a direction vector toward the goal (base position). Built via BFS (Dijkstra) from the goal outward.

```swift
public struct FlowField: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    private var integrationField: [UInt16]  // cost-to-goal; UInt16.max = impassable
    private var flowDirections: [UInt8]      // 0-7 for 8 directions, 255 = no flow
    // 0=E, 1=NE, 2=N, 3=NW, 4=W, 5=SW, 6=S, 7=SE

    public static func build(from map: GridMap, goal: GridPosition) -> FlowField
    public func sampleDirection(at position: SimPosition) -> SIMD2<Float>?
    public func isReachable(x: Int, y: Int) -> Bool
}
```

**Build algorithm:**
1. **Integration field** — BFS from goal. 4-directional neighbors (matching current A* behavior). Cost includes elevation differences: `moveCost = 1 + abs(neighborElevation - currentElevation)`.
2. **Flow directions** — each cell points to its lowest-cost neighbor among all 8 directions.

**Memory:** For 512×512 grid: 262,144 × (2 + 1) bytes = 768 KB.

**Rebuild frequency:** Only when the navigation map changes (structure placed or destroyed). Dirty-flagged via `CombatState.flowFieldDirty`, set `true` in `CommandSystem` on structure placement/removal.

### 4.3 Enhanced EnemyRuntime

```swift
public struct EnemyRuntime: Codable, Hashable, Sendable {
    public var id: EntityID
    public var archetype: EnemyArchetype
    public var moveEveryTicks: UInt64
    public var baseDamage: Int

    // Continuous position
    public var position: SimPosition
    public var previousPosition: SimPosition  // for interpolation

    // Movement
    public var speed: Float           // grid-units per tick (derived from moveEveryTicks)
    public var heading: Float         // radians, for visual rotation

    // Visual
    public var healthFraction: Float  // 0..1, for health bar rendering
}
```

### 4.4 EnemyMovementSystem with Flow Field

Per tick:
1. If `flowFieldDirty` or `flowField == nil`, rebuild from navigation map.
2. For each enemy (sorted by ID for determinism):
   - Store `previousPosition` for interpolation.
   - Check if `tick % moveEveryTicks == 0` (movement cadence).
   - If within 0.8 grid-units of base position, apply base hit and remove.
   - Sample flow field direction at current position.
   - Move: `position += direction * speed`.
   - Update `heading` from movement direction.
   - Sync `GridPosition` in entity store.

**Performance:** 1000 enemies at < 2ms per tick. Each enemy does one flow field lookup + one position update — O(1) per enemy vs O(grid²) for A*.

### 4.5 Enemy Archetypes

| Archetype | Move Every (ticks) | Speed (grid/tick) | HP | Damage | Behavior |
|-----------|-------------------|-------------------|-----|--------|----------|
| swarmling | 2 | 0.5 | 10 | 5 | Targets base, fast, fragile |
| drone_scout | 3 | 0.33 | 20 | 8 | Targets base, moderate |
| raider | 3 | 0.33 | 45 | 12 | Seeks nearest non-wall structure; HQ if path clear |
| breacher | 4 | 0.25 | 70 | 15 | Targets blocking walls/structures |
| overseer | 4 | 0.25 | 140 | 10 | Targets base, buffs nearby enemies |
| ~~artillery_bug~~ | ~~5~~ | ~~0.2~~ | ~~90~~ | ~~20~~ | **Deferred to post-v1** |

See `factory_economy.md` section 7.6 for full structure targeting behavior and enemy-structure interaction.

### 4.6 Implementation Status

| Aspect | Status |
|--------|--------|
| `FlowField` type | Gap — per-enemy A* rebuilt every tick |
| Flow field dirty flagging | Gap |
| Sub-grid enemy positions | Gap — integer `GridPosition` only |
| `previousPosition` for interpolation | Gap |
| `speed` / `heading` on enemy runtime | Gap |
| `healthFraction` on enemy runtime | Gap |

### 4.7 Open Questions

- Should enemies have local avoidance (steering around each other) in addition to flow field following?
  - Recommendation: defer to v1.1. Flow field alone produces acceptable movement. Local avoidance adds significant per-enemy cost.
- Should flow fields support multiple goals (e.g., base + secondary structure targets)?
  - Recommendation: single flow field to base for v1. Raiders/breachers that target structures can use local A* as a fallback for the final few cells only.

---

## 5. Combat System

### 5.1 Design Intent

The combat system bridges the factory economy and the defense layer. Every shot fired consumes real ammo from the production chain. Targeting uses spatial queries for O(1) amortized lookups instead of O(n) scans. Turret types are fully differentiated by ammo type, range, fire rate, and damage.

### 5.2 Spatial Targeting

Each tick, the combat system:
1. Builds an enemy spatial grid from all enemy runtimes.
2. For each turret (sorted by ID):
   - Queries the spatial grid with the turret's range as radius.
   - Finds the nearest enemy by `distanceSquared` (tie-break by lowest entity ID for determinism).
   - Checks fire rate: `tick - lastFireTick >= ticksBetweenShots`.
   - Attempts `economy.consume(itemID: ammoType, quantity: 1)`.
   - On success: spawns a `ProjectileRuntime` with computed direction and speed.
   - On failure: emits `notEnoughAmmo` event.

### 5.3 Turret Types

Cross-reference: `factory_economy.md` section 7.3 for full turret stat table.

| Turret | AmmoType | Fire Rate (shots/s) | Ticks Between Shots | Range | Damage | Projectile Type |
|--------|----------|--------------------|--------------------|-------|--------|-----------------|
| turret_mk1 | ammo_light | 2.0 | 10 | 8 | 12 | ballistic |
| turret_mk2 | ammo_heavy | 1.4 | 14 | 10 | 25 | ballistic |
| gattling_tower | ammo_light | 4.2 | 5 | 6.5 | 8 | ballistic |
| plasma_sentinel | ammo_plasma | 0.9 | 22 | 11 | 45 | homing |

### 5.4 Projectile Spawning

When a turret fires:
```swift
let direction = normalize(targetPosition - turretPosition)
let projectileSpeed: Float = 2.0

ProjectileRuntime(
    id: nextEntityID,
    sourceTurretID: turret.id,
    targetEnemyID: targetID,
    damage: turretDef.damage,
    projectileType: turretDef.projectileType,
    position: turretPosition,
    velocity: direction * projectileSpeed,
    speed: projectileSpeed,
    spawnTick: state.tick,
    maxLifetimeTicks: 40,
    collisionRadius: 0.4,
    sourcePosition: turretPosition
)
```

### 5.5 Extended SimEvent

Events carry position and direction data for VFX spawning:

```swift
public struct SimEvent: Codable, Hashable, Sendable {
    public var tick: UInt64
    public var kind: EventKind
    public var entity: EntityID?
    public var value: Int?
    public var itemID: ItemID?
    public var position: SimPosition?       // NEW: for VFX spawning
    public var direction: SIMD2<Float>?     // NEW: for directional VFX
}
```

New event kinds:
- `projectileImpact` — projectile hit an enemy (position, damage)
- `projectileMissed` — projectile expired without hitting

### 5.6 Implementation Status

| Aspect | Status |
|--------|--------|
| Spatial targeting via grid query | Gap — O(n) full scan per turret |
| Per-turret type stats | Exists — per-turret ammo type, range, fire rate, damage (Milestone 0) |
| Fire rate tracking per turret | Exists — `lastFireTick` per turret entity (Milestone 0) |
| Projectile spawning with physics | Gap — fire-and-forget model |
| `projectileImpact` / `projectileMissed` events | Gap |
| Position/direction on SimEvent | Gap |

---

## 6. Interpolation Bridge

### 6.1 Design Intent

The simulation ticks at 20 Hz. Rendering runs at 60 FPS. Without interpolation, entities visually teleport between tick positions. The interpolation bridge produces per-entity smoothly-lerped positions at render time, plus a VFX event queue that translates simulation events into particle spawn requests.

### 6.2 EntitySnapshot and InterpolatedEntityFrame

```swift
public enum EntityCategory: UInt8, Sendable {
    case structure
    case enemy
    case projectile
}

public struct InterpolatedEntityFrame: Sendable {
    public var id: EntityID
    public var category: EntityCategory
    public var position: SimPosition       // lerped between previous and current tick
    public var heading: Float
    public var healthFraction: Float
    public var archetype: EnemyArchetype?
    public var structureType: StructureType?
    public var velocity: SIMD2<Float>?
    public var sourcePosition: SimPosition?   // projectile origin (for trails)
    public var projectileType: ProjectileType?
}
```

### 6.3 Enhanced InterpolatedWorldFrame

```swift
public struct InterpolatedWorldFrame: Sendable {
    public var previous: WorldState
    public var current: WorldState
    public var alpha: Double                  // 0..1 between ticks
    public var entityFrames: [InterpolatedEntityFrame]
}
```

**Interpolation rules:**
- **Enemies:** lerp between `previousPosition` (stored on runtime) and current `position`. Newly spawned enemies (no previous state) use current position with no lerp.
- **Projectiles:** lerp between previous tick position and current position. Newly spawned projectiles lerp from `sourcePosition` (turret origin).
- **Structures:** static — use `SimPosition(from: entity.position)` with no lerp.

### 6.4 VFX Event Bridge

Translates simulation events into visual-only particle spawn requests:

```swift
public struct ParticleSpawnRequest {
    public var type: ParticleEffectType
    public var position: SimPosition
    public var direction: SIMD2<Float>?
    public var count: Int
    public var lifetime: Float
}

public struct VFXEventQueue {
    private var pendingSpawns: [ParticleSpawnRequest] = []

    public mutating func processEvents(_ events: [SimEvent])
    public mutating func drain() -> [ParticleSpawnRequest]
}
```

**Event-to-VFX mapping:**

| SimEvent Kind | Particle Type | Count | Lifetime |
|---------------|--------------|-------|----------|
| `projectileFired` | muzzleFlash | 12 | 0.15s |
| `projectileImpact` | impactExplosion | 24 | 0.4s |
| `enemyDestroyed` | deathExplosion | 32 | 0.6s |

### 6.5 Implementation Status

| Aspect | Status |
|--------|--------|
| `InterpolatedWorldFrame` | Exists — but only interpolates scalars (integrity) |
| Per-entity position interpolation | Gap |
| `InterpolatedEntityFrame` type | Gap |
| `VFXEventQueue` | Gap |
| `ParticleSpawnRequest` | Gap |

---

## 7. GPU Rendering Pipeline

### 7.1 Design Intent

Replace the per-pixel compute renderer (WhiteboxRenderer) with an instanced rendering pipeline. Each entity category (tiles, structures, enemies, projectiles) is rendered via a single instanced draw call per category. The CPU fills instance buffers each frame; the GPU renders all instances in one pass.

### 7.2 Shared Types Header

A shared C header imported by both Metal shaders and Swift (via bridging header):

```c
// SharedTypes.h

struct CameraUniforms {
    simd_float2 viewportSize;        // pixels
    simd_float2 viewSizePoints;      // points
    simd_float2 drawableScale;
    simd_float2 boardOrigin;         // screen-space origin of board
    float tileWidth;                 // screen-space tile dimensions
    float tileHeight;
    float cameraZoom;
    float time;                      // seconds since start (for animation)
    uint boardWidth;
    uint boardHeight;
};

struct EntityInstanceData {          // 64 bytes, 16-byte aligned
    float positionX;
    float positionY;
    float positionZ;
    float heading;
    float scaleX;
    float scaleY;
    float scaleZ;
    float healthFraction;
    float colorR;
    float colorG;
    float colorB;
    float colorA;
    uint entityTypeRaw;
    uint flags;              // bit 0 = billboard, bit 1 = selected
    unsigned short animFrame;
    unsigned short _pad0;
};

struct TileInstanceData {            // 32 bytes
    short gridX;
    short gridY;
    short elevation;
    unsigned short tileType; // 0=ground, 1=blocked, 2=restricted, 3=ramp, 4=base, 5=spawn
    float colorR;
    float colorG;
    float colorB;
    float highlightStrength;
};
```

### 7.3 Instance Buffer Management

Triple-buffered instance buffers prevent CPU-GPU contention:

```swift
public final class InstanceBufferPool {
    private let device: MTLDevice
    private let bufferCount = 3  // triple-buffering
    private var buffers: [MTLBuffer]
    private var currentIndex = 0
    private let maxInstances: Int
    private let instanceStride: Int

    public init(device: MTLDevice, maxInstances: Int = 4096)
    public func nextBuffer() -> MTLBuffer?
    public func writeInstances(_ instances: [EntityInstanceData], into buffer: MTLBuffer) -> Int
}
```

**Max instances:** 4,096 per buffer (covers 1000+ enemies + 500+ projectiles + structures).

**Buffer size:** 4,096 × 64 bytes = 256 KB per buffer, 768 KB total for triple-buffering.

### 7.4 Board Rendering — Instanced Tile Quads

Replace the per-pixel compute board renderer with instanced quads. One `TileInstanceData` per visible cell.

- For a 96×64 board: 6,144 tiles × 32 bytes = 192 KB per frame.
- Single instanced draw call for the entire board.
- Tile buffer only rebuilds when board state changes (structure placed/removed, zone highlight changes).

### 7.5 Entity Rendering — Hybrid 3D + Billboard

Entities use a hybrid approach:
- **3D meshes** for structures and large enemies (future).
- **Billboarded quads** for projectiles, particles, and small enemies (v1 default).

The `flags` field in `EntityInstanceData` controls rendering mode:
- `flags & 1`: billboard — quad always faces camera.
- `flags & 2`: selected — highlighted outline.

### 7.6 Depth Sorting

Current rendering uses top-down orthographic grid (not true isometric). Depth = Y position.

- Sort entities by Y ascending before writing to instance buffer.
- Disable depth testing for 2D case.
- If transitioning to true isometric later, use `position.z = positionY * depthScale` in the vertex shader with a depth buffer.

### 7.7 Triple-Buffering Strategy

```swift
private let frameSemaphore = DispatchSemaphore(value: 3)

public func draw(in view: MTKView) {
    frameSemaphore.wait()
    guard let commandBuffer = commandQueue.makeCommandBuffer() else {
        frameSemaphore.signal()
        return
    }
    commandBuffer.addCompletedHandler { [weak self] _ in
        self?.frameSemaphore.signal()
    }
    // ... fill instance buffers, encode render passes ...
}
```

### 7.8 Implementation Status

| Aspect | Status |
|--------|--------|
| Instanced entity rendering | Gap — per-pixel compute loop |
| `SharedTypes.h` | Gap — no shared type header |
| `EntityInstanceData` / `TileInstanceData` | Gap |
| `InstanceBufferPool` | Gap — fresh buffer allocation every frame |
| Triple-buffered frame pacing | Gap |
| Instanced tile board rendering | Gap — per-pixel compute |
| Billboard entity rendering | Gap |

### 7.9 Open Questions

- Should the whitebox renderer be retained as a debug/fallback mode?
  - Recommendation: yes. Keep it available behind a debug toggle but disabled by default once instanced rendering is functional.

---

## 8. GPU Particle System

### 8.1 Design Intent

A fully GPU-driven particle system. The CPU emits spawn commands; the GPU handles all particle physics (position, velocity, aging, death) and rendering. This keeps particle overhead off the CPU simulation thread and scales to tens of thousands of simultaneous particles.

### 8.2 GPUParticle Struct

```c
struct GPUParticle {         // 80 bytes
    float positionX;
    float positionY;
    float positionZ;
    float age;
    float velocityX;
    float velocityY;
    float velocityZ;
    float lifetime;
    float colorR;
    float colorG;
    float colorB;
    float colorA;
    float scaleStart;
    float scaleEnd;
    float rotation;
    float rotationSpeed;
    uint particleType;
    uint alive;              // 0 = dead, 1 = alive
    uint _pad0;
    uint _pad1;
};
```

### 8.3 Particle Pool Architecture

```swift
public final class GPUParticleSystem {
    private let maxParticles: Int          // 65,536 (macCinematic)
    private var particleBuffers: [MTLBuffer]  // 2 buffers (double-buffered)
    private var emissionBuffer: MTLBuffer?    // CPU -> GPU emission queue
    private var counterBuffer: MTLBuffer?     // atomic free-slot counter
    private let maxEmissionsPerFrame: Int = 512

    private var emitPipeline: MTLComputePipelineState?
    private var updatePipeline: MTLComputePipelineState?
}
```

**Memory:** 80 bytes × 65,536 = 5.12 MB per buffer, 10.24 MB total (double-buffered).

**Emission queue:** Max 512 commands/frame × 80 bytes = 40 KB (`.storageModeShared`).

**Particle pool:** `.storageModePrivate` — lives entirely on GPU. CPU never reads particle data.

**Slot allocation:** Atomic counter. New emissions claim slots via `atomic_fetch_add`. On pool full, wraps around (oldest particles overwritten).

### 8.4 Emission Command

```c
struct ParticleEmissionCommand {  // 80 bytes
    float positionX;
    float positionY;
    float positionZ;
    uint count;
    float directionX;
    float directionY;
    float spreadAngle;
    float speedMin;
    float speedMax;
    float lifetimeMin;
    float lifetimeMax;
    float scaleStart;
    float scaleEnd;
    float colorR;
    float colorG;
    float colorB;
    uint particleType;
    uint _pad0;
    uint _pad1;
    uint _pad2;
};
```

### 8.5 Particle Types and Presets

```swift
public enum ParticleEffectType: UInt32, CaseIterable {
    case muzzleFlash = 0       // 8-14 particles, 0.1-0.15s, additive yellow/white
    case projectileTrail = 1   // 2-3 per frame while alive, 0.3s, additive
    case impactExplosion = 2   // 12-30 particles, 0.3-0.5s, radial burst
    case deathExplosion = 3    // 16-40 particles, 0.5-0.8s, directional spray
    case smoke = 4             // 1-2 per second, 2-4s, alpha blend, slow rise
    case sparks = 5            // 4-8 per burst, 0.2-0.4s, gravity-affected
    case ambientDust = 6       // 1 per few seconds, 5-10s, very slow drift
}
```

**Particle types reference table:**

| Type | Count | Lifetime | Blend Mode | Trigger |
|------|-------|----------|------------|---------|
| Muzzle flash | 8-14 | 0.1-0.15s | Additive | `projectileFired` event |
| Projectile trail | 2-3/frame | 0.3s | Additive | Per-frame while projectile alive |
| Impact explosion | 12-30 | 0.3-0.5s | Additive | `projectileImpact` event |
| Death burst | 16-40 | 0.5-0.8s | Additive | `enemyDestroyed` event |
| Smoke | 1-2/sec | 2-4s | Alpha | Attached to smelters/power plants |
| Sparks | 4-8/burst | 0.2-0.4s | Additive | Construction/damage events |
| Ambient dust | 1/few sec | 5-10s | Alpha | Background environmental |

### 8.6 Blending

- **Additive blending** (`.sourceAlpha, .one`) for fire, flash, sparks, trails — order-independent, no sorting required.
- **Alpha blending** for smoke — requires back-to-front sort (deferred to Phase 8).
- Dead particles output degenerate triangles (vertex position at z = -1), clipped by the GPU at zero cost.

### 8.7 Compute Pipeline

**Per frame:**
1. **Emit pass** — `particle_emit` compute shader processes the emission queue. Each command spawns N particles, claiming slots via atomic counter.
2. **Update pass** — `particle_update` compute shader advances all particles: position += velocity × dt, aging, drag, gravity (sparks), alpha fade, rotation. Kills expired particles (`alive = 0`).
3. **Render pass** — `particle_vertex` / `particle_fragment` renders all live particles as billboarded quads. Dead particles produce degenerate triangles.

### 8.8 Particle Physics (GPU)

Key behaviors in the `particle_update` compute shader:
- **Drag:** `velocity *= 1.0 - (dragCoefficient * deltaTime)`
- **Gravity (sparks, type 5):** `velocityZ -= 9.8 * deltaTime`. Bounces on ground: `velocityZ *= -0.3`.
- **Alpha fade:** starts at 70% of lifetime, fades over last 30%: `alpha = 1.0 - ((t - 0.7) / 0.3)` where `t = age / lifetime`.
- **Rotation:** `rotation += rotationSpeed * deltaTime`. Speed range: -2.0 to +2.0 radians/s.

### 8.9 Implementation Status

| Aspect | Status |
|--------|--------|
| `GPUParticleSystem` class | Gap — no particle system |
| Particle pool buffers | Gap |
| `particle_update` compute shader | Gap |
| `particle_emit` compute shader | Gap |
| `particle_render` vertex/fragment shaders | Gap |
| Emission queue from VFX events | Gap |
| Quality-scaled particle counts | Gap |

---

## 9. Metal Shader Architecture

### 9.1 Shader File Organization

```
Sources/GameRendering/Shaders/
  SharedTypes.h          — shared C header (Swift imports via bridging)
  whitebox.metal         — existing (retained as debug fallback)
  tile_render.metal      — instanced tile quad rendering
  entity_render.metal    — instanced entity rendering (3D + billboard)
  particle_update.metal  — compute: particle physics + aging
  particle_emit.metal    — compute: process emission queue
  particle_render.metal  — vertex/fragment: billboard particle rendering
  pbr.metal              — existing stubs (evolve into full PBR later)
  debug.metal            — existing debug heat map
```

### 9.2 Shader Function Table

| Shader File | Function | Type | Purpose |
|-------------|----------|------|---------|
| `tile_render.metal` | `tile_vertex` | vertex | Instanced tile quad positioning from `TileInstanceData` |
| `tile_render.metal` | `tile_fragment` | fragment | Tile coloring with grid lines and highlights |
| `entity_render.metal` | `entity_vertex` | vertex | Instanced entity positioning (billboard + future 3D mesh) |
| `entity_render.metal` | `entity_fragment` | fragment | Entity coloring, health bar overlay, selection highlight |
| `particle_update.metal` | `particle_update` | compute | Move, age, apply drag/gravity, kill expired particles |
| `particle_emit.metal` | `particle_emit` | compute | Spawn particles from emission command queue |
| `particle_render.metal` | `particle_vertex` | vertex | Billboarded particle quad with rotation and scale |
| `particle_render.metal` | `particle_fragment` | fragment | Soft circle with alpha/additive blending |

### 9.3 Buffer Binding Conventions

| Buffer Index | Contents | Used By |
|-------------|----------|---------|
| 0 | Instance data (entity, tile, or particle array) | All vertex/compute shaders |
| 1 | `CameraUniforms` or `ParticleUpdateUniforms` | All shaders |
| 2 | Emission commands (particle_emit only) | `particle_emit` |
| 3 | Emission count (particle_emit only) | `particle_emit` |
| 4 | Max particles constant (particle_emit only) | `particle_emit` |

### 9.4 Implementation Status

| Aspect | Status |
|--------|--------|
| `SharedTypes.h` | Gap — no shared header |
| `tile_render.metal` | Gap |
| `entity_render.metal` | Gap |
| `particle_update.metal` | Gap |
| `particle_emit.metal` | Gap |
| `particle_render.metal` | Gap |
| Existing `whitebox.metal` | Exists — per-pixel compute (to be retained as debug fallback) |
| Existing `pbr.metal` | Exists — vertex/fragment stubs, no instancing |

---

## 10. Performance Budget

### 10.1 Frame Time Budget (16.67ms target for 60 FPS)

| Pass | mobileBalanced | tabletHigh | macCinematic |
|------|---------------|------------|--------------|
| Tile render | 1.0 ms | 0.8 ms | 0.6 ms |
| Entity instances (opaque) | 1.5 ms | 1.2 ms | 1.0 ms |
| Particle update (compute) | 0.5 ms | 0.4 ms | 0.3 ms |
| Particle render (transparent) | 1.5 ms | 1.2 ms | 1.0 ms |
| Post processing | 0.5 ms | 0.8 ms | 1.5 ms |
| UI composite | 0.3 ms | 0.3 ms | 0.3 ms |
| CPU overhead (buffer fill) | 1.5 ms | 1.5 ms | 1.5 ms |
| **Total** | **6.8 ms** | **6.2 ms** | **6.2 ms** |
| **Headroom** | **9.9 ms** | **10.5 ms** | **10.5 ms** |

### 10.2 Memory Budget

| Resource | Size | Notes |
|----------|------|-------|
| Particle pool (2×) | 10.24 MB | 65K particles, double-buffered, `.storageModePrivate` |
| Entity instance buffers (3×) | 768 KB | 4K instances, triple-buffered, `.storageModeShared` |
| Tile instance buffers (3×) | 576 KB | 6K tiles, triple-buffered |
| Emission queue | 40 KB | 512 commands, `.storageModeShared` |
| Spatial grid (CPU) | ~2 MB | 512×512 cells |
| Flow field (CPU) | ~768 KB | 512×512 integration + direction fields |
| Render targets (existing) | ~40 MB | Already allocated by RenderResources |
| Indirect draw args | 48 bytes | 3 draw argument structs |
| **New total** | **~14.4 MB** | On top of existing render targets |

### 10.3 Particle Budget by Quality Preset

| Parameter | mobileBalanced | tabletHigh | macCinematic |
|-----------|---------------|------------|--------------|
| Max simultaneous particles | 16,384 | 32,768 | 65,536 |
| Muzzle flash count | 6 | 10 | 14 |
| Trail density (per projectile/frame) | 1 | 2 | 3 |
| Impact explosion count | 12 | 20 | 30 |
| Death explosion count | 16 | 28 | 40 |
| Ambient particles | 20 | 50 | 100 |

Counts scale: `mobileBalanced` uses ~40% of `macCinematic` counts.

### 10.4 Simulation Tick Budget (50ms at 20 Hz)

| System | Budget | Notes |
|--------|--------|-------|
| Flow field rebuild | ~5 ms | Only on map change, amortized to near-zero |
| Spatial grid rebuild | < 0.5 ms | O(n) insert for 1000 entities |
| Enemy movement | < 2 ms | 1000 enemies × flow field sample + move |
| Combat targeting | < 1 ms | Spatial grid queries, ~50 turrets |
| Projectile movement + collision | < 1 ms | 500 projectiles × move + grid query |
| **Total** | **< 5 ms** | Well within 50ms tick budget |

### 10.5 Implementation Status

| Aspect | Status |
|--------|--------|
| Quality preset system | Exists — `QualityPreset` enum with mobileBalanced/tabletHigh/macCinematic |
| Per-pass frame time measurement | Gap — no GPU profiling integration |
| Adaptive quality scaling | Gap |
| Particle budget scaling by preset | Gap |

---

## 11. Determinism Guarantees

### 11.1 Design Intent

The simulation must produce identical `WorldState` snapshots given identical command streams. This is required for replay regression tests and is the foundation for future co-op multiplayer. The GPU handles visual-only effects that do not feed back into simulation state.

### 11.2 Rules

1. **All gameplay state on CPU.** GPU handles visual-only effects (particles, trails, screen-space distortion). No GPU output feeds back into `WorldState`.

2. **Float determinism.** IEEE 754 on ARM64. Identical inputs and compilation settings produce identical results. Cross-architecture co-op would require fixed-point arithmetic (out of scope for v1).

3. **Sorted iteration.** All dictionary iterations use `.keys.sorted()` or equivalent sorted enumeration. This is an existing convention in the codebase.

4. **Spatial grid stability.** The grid stores `EntityID` values. Queries return unsorted arrays, but all consuming code sorts by entity ID before processing.

5. **Flow field determinism.** BFS with FIFO queue and deterministic neighbor order (East, West, South, North). Identical maps produce identical flow fields.

6. **No RNG in projectiles.** Direction is computed from turret-to-enemy vector (fully deterministic). Enemy spawning uses the existing deterministic `deterministicRaidRoll` hash.

7. **GPU particle RNG is visual-only.** Particle emission uses a deterministic pseudo-random hash based on `gid`, emission index, and slot — but since particles are visual-only, their randomness does not affect simulation.

### 11.3 Implementation Status

| Aspect | Status |
|--------|--------|
| Deterministic command ordering | Exists |
| Sorted dictionary iteration | Exists (convention) |
| Replay regression tests | Exists |
| Float determinism on ARM64 | Guaranteed by platform |
| GPU-simulation boundary | Gap — to be enforced by architecture |

---

## 12. Implementation Roadmap

### Phase 1: Spatial Indexing + Projectile Physics on CPU

**Goal:** Projectiles physically travel and collide. Spatial queries replace O(n) scans.

| Item | Details |
|------|---------|
| **Files modified** | `SimulationTypes.swift` (add `SimPosition`, extend `ProjectileRuntime`, `EnemyRuntime`, `CombatState`, `EventKind`), `Systems.swift` (rewrite `CombatSystem` and `ProjectileSystem`), `EntityStore.swift` (expose `nextEntityID`) |
| **Files created** | `SpatialGrid.swift` |
| **Dependencies** | None |
| **Tests** | Determinism (identical commands → identical snapshots), projectile trajectory verification, spatial grid query correctness, collision detection at various angles/speeds |
| **Done when** | Projectiles physically travel and collide. All existing tests pass. Determinism preserved. |

### Phase 2: Flow Field Pathfinding + Sub-Grid Enemy Movement

**Goal:** Enemies follow a shared flow field with smooth continuous movement.

| Item | Details |
|------|---------|
| **Files modified** | `SimulationTypes.swift` (`CombatState` extensions), `Systems.swift` (`EnemyMovementSystem` rewrite, `CommandSystem` dirty flagging) |
| **Files created** | `FlowField.swift` |
| **Dependencies** | Phase 1 (`SimPosition` type) |
| **Tests** | Flow field correctness (path to goal exists, impassable cells blocked), 1000-enemy performance benchmark (< 2ms/tick), dirty-flag rebuild triggers |
| **Done when** | Enemies follow flow field smoothly. Performance target met. All tests pass. |

### Phase 3: Interpolation Bridge Enhancement

**Goal:** Enemies and projectiles move smoothly at 60 FPS between 20 Hz simulation ticks.

| Item | Details |
|------|---------|
| **Files modified** | `Interpolation.swift` (add `InterpolatedEntityFrame`, extend `InterpolatedWorldFrame`), `SimulationEngine.swift`, `RenderTypes.swift` (`RenderContext`), `Renderer.swift`, `RuntimeController.swift` |
| **Files created** | None |
| **Dependencies** | Phase 1 (`SimPosition` in runtime types) |
| **Tests** | Interpolation produces positions between previous and current tick, alpha clamping, newly spawned entities handle missing previous state |
| **Done when** | Enemies/projectiles move smoothly at 60 FPS. No visual teleporting between ticks. |

### Phase 4: Instanced Entity Rendering Pipeline

**Goal:** All entities render via instanced draw calls. Visual parity with whitebox.

| Item | Details |
|------|---------|
| **Files modified** | `RenderTypes.swift` (`OpaquePBRNode` implementation), `RenderResources.swift`, `Renderer.swift` |
| **Files created** | `Shaders/SharedTypes.h`, `Shaders/entity_render.metal`, `InstanceTypes.swift`, `InstanceBufferPool.swift` |
| **Dependencies** | Phase 3 (`InterpolatedWorldFrame` with entity frames) |
| **Tests** | Visual parity with whitebox (manual), instance count matches entity count, buffer overflow handling |
| **Done when** | All entities render via instanced draw calls. No per-pixel compute for entities. |

### Phase 5: Projectile Trail Rendering

**Goal:** Projectiles render as bright sprites with trails.

| Item | Details |
|------|---------|
| **Files modified** | `RenderTypes.swift` (`TransparentVFXNode` implementation), `Shaders/entity_render.metal` |
| **Files created** | `TrailRenderer.swift` |
| **Dependencies** | Phase 4 (instanced rendering pipeline) |
| **Tests** | 500 simultaneous projectiles at 60 FPS, trails visually follow projectile path |
| **Done when** | Projectiles render as bright sprites with trails. 500 projectiles at 60 FPS. |

### Phase 6: GPU Particle System

**Goal:** Three core VFX effects (muzzle flash, impact explosion, death burst) trigger from simulation events.

| Item | Details |
|------|---------|
| **Files modified** | `RenderGraph.swift`, `RenderResources.swift` |
| **Files created** | `ParticleSystem.swift`, `VFXEventQueue.swift`, `Shaders/particle_update.metal`, `Shaders/particle_emit.metal`, `Shaders/particle_render.metal` |
| **Dependencies** | Phase 4 (instanced rendering, `CameraUniforms`), Phase 1 (sim events with positions) |
| **Tests** | 10K particles at 60 FPS, emission commands produce visible particles, particles expire correctly, atomic counter wraps gracefully |
| **Done when** | Three core VFX effects trigger from sim events. 10K particles at 60 FPS. |

### Phase 7: Board Renderer Transition

**Goal:** Board renders via instanced tiles instead of per-pixel compute.

| Item | Details |
|------|---------|
| **Files modified** | `RenderTypes.swift` (`WhiteboxBoardNode` replacement), `WhiteboxRenderer.swift` (retained as debug fallback) |
| **Files created** | `Shaders/tile_render.metal`, `TileRenderer.swift` |
| **Dependencies** | Phase 4 (`CameraUniforms`, instance pipeline infrastructure) |
| **Tests** | Visual parity with whitebox board (manual), tile count matches visible board cells, tile buffer rebuilds on board state change |
| **Done when** | Board renders via instanced tiles. Visual parity. Whitebox retained as debug mode. |

### Phase 8: Full VFX Suite + Environmental Particles

**Goal:** All 7 particle types implemented. Quality presets scale correctly.

| Item | Details |
|------|---------|
| **Files modified** | `ParticleSystem.swift`, `VFXEventQueue.swift`, particle shaders |
| **Files created** | None |
| **Dependencies** | Phase 6 (GPU particle system) |
| **Tests** | All 7 particle types render correctly, quality preset scaling produces expected counts, 60 FPS at macCinematic with full combat load |
| **Done when** | All 7 particle types implemented. Quality presets scale correctly. 60 FPS at macCinematic with full load. |

### Phase 9: Performance Optimization

**Goal:** All three quality presets hit 60 FPS on target hardware.

| Item | Details |
|------|---------|
| **Files modified** | Various — profiling-driven |
| **Files created** | None |
| **Dependencies** | All previous phases |
| **Tests** | Frame time within budget per quality preset, memory within budget, 1000 enemies + 500 projectiles + 30K particles at 60 FPS |
| **Done when** | All three quality presets hit 60 FPS on target hardware. Adaptive quality auto-adjusts if frame time exceeds budget. |

### Phase Dependency Graph

```
Phase 1 (Spatial + Projectile)
  ├── Phase 2 (Flow Field) ──────────────────────────────────────┐
  ├── Phase 3 (Interpolation) ──> Phase 4 (Instanced Rendering) ─┤
  │                                 ├── Phase 5 (Trails)         │
  │                                 ├── Phase 6 (Particles) ──> Phase 8 (Full VFX)
  │                                 └── Phase 7 (Board)         │
  └─────────────────────────────────────────────────────────────> Phase 9 (Optimization)
```

### Verification After Each Phase

1. `swift test` — all existing + new tests pass
2. `swift run FactoryDefense` — visual verification
3. Determinism test: identical command streams produce identical snapshots
4. Performance benchmark: frame time within budget at target entity counts

---

## Appendix A: New File Summary

| File | Phase | Purpose |
|------|-------|---------|
| `Sources/GameSimulation/SpatialGrid.swift` | 1 | Uniform grid spatial index for O(1) neighbor queries |
| `Sources/GameSimulation/FlowField.swift` | 2 | Flow field pathfinding (integration field + direction field) |
| `Sources/GameRendering/Shaders/SharedTypes.h` | 4 | Shared C header for Metal shaders and Swift bridging |
| `Sources/GameRendering/Shaders/entity_render.metal` | 4 | Instanced entity vertex/fragment shaders |
| `Sources/GameRendering/InstanceTypes.swift` | 4 | Swift mirror types for `EntityInstanceData`, `TileInstanceData` |
| `Sources/GameRendering/InstanceBufferPool.swift` | 4 | Triple-buffered instance buffer management |
| `Sources/GameRendering/TrailRenderer.swift` | 5 | Projectile trail rendering |
| `Sources/GameRendering/ParticleSystem.swift` | 6 | GPU particle pool, emission, update orchestration |
| `Sources/GameRendering/VFXEventQueue.swift` | 6 | Sim event → particle spawn request translation |
| `Sources/GameRendering/Shaders/particle_update.metal` | 6 | Compute shader: particle physics and aging |
| `Sources/GameRendering/Shaders/particle_emit.metal` | 6 | Compute shader: particle emission from command queue |
| `Sources/GameRendering/Shaders/particle_render.metal` | 6 | Vertex/fragment: billboard particle rendering |
| `Sources/GameRendering/Shaders/tile_render.metal` | 7 | Instanced tile quad vertex/fragment shaders |
| `Sources/GameRendering/TileRenderer.swift` | 7 | Tile instance buffer management and draw encoding |

---

## Appendix B: Modified File Summary

| File | Phase | Changes |
|------|-------|---------|
| `Sources/GameSimulation/SimulationTypes.swift` | 1 | Add `SimPosition`, `ProjectileType`. Extend `ProjectileRuntime` (position, velocity, collision). Extend `EnemyRuntime` (position, previousPosition, speed, heading, healthFraction). Extend `CombatState` (projectiles dict, flowField, flowFieldDirty). Add `projectileImpact`/`projectileMissed` to `EventKind`. Add position/direction to `SimEvent`. |
| `Sources/GameSimulation/Systems.swift` | 1, 2 | Rewrite `CombatSystem` (spatial targeting, per-turret types, projectile spawning). Rewrite `ProjectileSystem` (per-tick movement, collision detection). Rewrite `EnemyMovementSystem` (flow field, sub-grid movement). Extend `CommandSystem` (flow field dirty flagging). |
| `Sources/GameSimulation/EntityStore.swift` | 1 | Expose `nextEntityID` for projectile spawning. |
| `Sources/GameSimulation/Interpolation.swift` | 3 | Add `InterpolatedEntityFrame`. Extend `InterpolatedWorldFrame` with per-entity position interpolation. |
| `Sources/GameSimulation/SimulationEngine.swift` | 3 | Pass previous WorldState to interpolation bridge. |
| `Sources/GameRendering/RenderTypes.swift` | 3, 4 | Extend `RenderContext` with entity frames. Implement `OpaquePBRNode` and `TransparentVFXNode`. |
| `Sources/GameRendering/RenderResources.swift` | 4, 6 | Allocate instance buffers and particle buffers. |
| `Sources/GameRendering/Renderer.swift` | 4 | Use instance buffers for rendering. Integrate triple-buffering. |
| `Sources/GameRendering/RenderGraph.swift` | 6 | Wire particle system into render pass sequence. |
| `Sources/GameRendering/WhiteboxRenderer.swift` | 7 | Retained as debug fallback. Disabled by default when instanced pipeline is active. |
| `Sources/GamePlatform/RuntimeController.swift` | 3 | Feed interpolated entity frames to renderer. |

---

## Appendix C: Implementation Priority Matrix

| Feature | Impact | Effort | Phase | Priority |
|---------|--------|--------|-------|----------|
| `SimPosition` + spatial grid | Critical | Medium | 1 | **P0** |
| Real projectile physics + collision | Critical | Medium | 1 | **P0** |
| Flow field pathfinding | Critical | Medium | 2 | **P0** |
| Sub-grid enemy movement | Critical | Low | 2 | **P0** |
| Per-entity position interpolation | High | Medium | 3 | **P0** |
| `SharedTypes.h` + instance types | High | Low | 4 | **P1** |
| Instanced entity rendering | Critical | High | 4 | **P1** |
| Instance buffer pool (triple-buffered) | High | Medium | 4 | **P1** |
| Projectile trail rendering | Medium | Medium | 5 | **P1** |
| GPU particle system (core 3 effects) | High | High | 6 | **P1** |
| VFX event bridge | Medium | Low | 6 | **P1** |
| Instanced tile board rendering | Medium | Medium | 7 | **P2** |
| Full VFX suite (7 particle types) | Medium | Medium | 8 | **P2** |
| Quality-scaled particle budgets | Medium | Low | 8 | **P2** |
| Performance optimization pass | High | High | 9 | **P2** |
| Adaptive quality auto-scaling | Low | Medium | 9 | **P3** |

---

## Changelog

- 2026-02-15: Initial draft — full architecture spec for combat physics, rendering pipeline, and VFX system with 9-phase implementation roadmap.
- 2026-02-16: Cross-PRD alignment: Updated per-turret type stats and fire rate tracking to Exists (Milestone 0). Fixed raider targeting from probability-based (70/30) to deterministic (seeks nearest non-wall structure) per wave_threat_system.md.
