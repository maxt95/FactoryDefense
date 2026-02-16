# Wave & Threat System PRD

> Authoritative specification for wave spawning, enemy behavior, wall fortifications, and the ammo distribution network. Companion to `factory_economy.md` (production/balance), `combat_rendering_vfx.md` (rendering/physics), and `building_specifications.md` (logistics).

---

## 1. Design Pillars

1. **Continuous pressure** — No phase gates. Building and defending happen simultaneously. The factory IS the thing worth protecting.
2. **Full perimeter threat** — Enemies spawn from any map edge. There is no safe side. Expansion means more surface area to defend.
3. **Death by attrition** — Enemies destroy factory structures. The economy crumbles before the HQ falls. Recovery is possible but increasingly desperate.
4. **Walls are the defense layer** — Turrets mount only on walls. Wall placement IS turret placement. The fortification line defines the player's territory.
5. **No foreknowledge** — Players don't see wave composition previews. Build generalized, resilient defenses rather than optimizing for specific threats.

---

## 2. HQ — The Starting Seed

The HQ is the only structure the player begins with. It is both the origin of the factory and the loss condition.

| Property | Value |
|---|---|
| Grid footprint | 2×2 |
| Health | 500 |
| Build cost | N/A (placed at game start) |
| Storage capacity | 24 slots (shared input/output) |
| Power draw | 0 |
| Ports | 4 bidirectional (one per cardinal face): each port serves as output for starting resources and input for repair_kit delivery |

### 2.1 Starting Resources

The HQ begins pre-loaded with enough resources to bootstrap the first production chain. Exact quantities scale by difficulty:

| Resource | Easy | Normal | Hard |
|---|---|---|---|
| ore_iron | 30 | 20 | 12 |
| ore_copper | 20 | 12 | 8 |
| ore_coal | 10 | 6 | 4 |
| plate_iron | 18 | 14 | 10 |
| plate_copper | 8 | 6 | 4 |
| plate_steel | 10 | 8 | 6 |
| gear | 5 | 4 | 3 |
| circuit | 5 | 4 | 2 |
| turret_core | 2 | 1 | 1 |
| wall_kit | 8 | 6 | 3 |
| ammo_light | 24 | 16 | 8 |

### 2.2 HQ Role Across Game Phases

- **Early game**: Acts as the central storage hub. First miners and smelters route through it. The starting ammo_light feeds the player's first wall turret.
- **Mid game**: Dedicated storage buildings and distributed logistics reduce reliance on HQ. It remains a useful storage node but is no longer the bottleneck.
- **Late game**: HQ's primary importance is the loss condition. A well-designed base has the HQ deep inside layered walls, rarely under direct threat — until it is.

### 2.3 Loss Condition

**The game ends when the HQ is destroyed.** There is no grace period. If HQ health reaches 0, the run is over.

The HQ cannot be repaired by passive means — only repair_kit deliveries via conveyors restore its health. This makes HQ damage a serious event that demands immediate logistical response.

---

## 3. Wave Model — Continuous Surges with Trickle

There are no build/wave phases. The game runs continuously from the moment the player places their first structure. Waves arrive on a timer.

### 3.1 Timeline Structure

```
Game Start
  │
  ├── Grace Period (difficulty-scaled, no enemies)
  │     Easy: 180s │ Normal: 120s │ Hard: 60s
  │
  ├── Trickle begins (probing scouts, continuous from here)
  │
  ├── Wave 1 surge
  │     ↕ Inter-wave gap (difficulty-scaled)
  ├── Wave 2 surge
  │     ↕ Inter-wave gap (compresses over time)
  ├── Wave 3 surge
  │     ...
  └── Endless escalation
```

### 3.2 Grace Period

After game start, the player gets uninterrupted time to build. No enemies spawn during this period. The grace period is the player's only guaranteed safe window.

### 3.3 Trickle Spawns

Once the grace period ends, trickle spawns run continuously for the rest of the game — including during wave surges.

| Property | Easy | Normal | Hard |
|---|---|---|---|
| Spawn interval | 15s | 12s | 8s |
| Enemies per spawn | 1 | 1–2 | 2–3 |
| Composition | Swarmlings only | Swarmlings only | Swarmlings + drone scouts |
| Spawn location | Single random edge point | Single random edge point | Single random edge point |

**Purpose**: Trickle scouts keep the player alert between surges. They test for gaps in the wall perimeter and apply light, constant pressure. They pose minimal threat to a defended base but will damage unprotected outer structures.

### 3.4 Wave Surges

Wave surges are the primary threat. Each surge spawns a group of enemies determined by the wave's budget and available enemy types.

**Inter-wave gap** (time between surges):

| Difficulty | Base gap | Minimum gap (floor) | Compression rate |
|---|---|---|---|
| Easy | 120s | 70s | −2s per wave |
| Normal | 90s | 50s | −2s per wave |
| Hard | 60s | 35s | −2s per wave |

The gap between surges shrinks by 2 seconds per wave until it hits the floor. This creates an accelerating rhythm: early game is relaxed, late game is near-continuous.

**Example (Normal difficulty):**
- Wave 1 → 90s gap → Wave 2 → 88s gap → Wave 3 → 86s gap → ... → Wave 21+ → 50s gap (floor)

---

## 4. Wave Composition

### 4.1 Hand-Authored Waves (1–8)

Waves 1–8 use hand-authored compositions from `waves.json`. These provide a curated early-game ramp that introduces enemy types at a controlled pace.

| Wave | Budget | Composition |
|---|---|---|
| 1 | 12 | 6 swarmling, 2 drone_scout |
| 2 | 18 | 8 swarmling, 4 drone_scout |
| 3 | 22 | 6 drone_scout, 1 raider |
| 4 | 26 | 6 drone_scout, 2 raider |
| 5 | 32 | 10 swarmling, 2 raider, 1 breacher |
| 6 | 38 | 8 drone_scout, 2 raider, 1 breacher |
| 7 | 40 | 12 swarmling, 3 raider, 2 breacher |
| 8 | 68 | 10 drone_scout, 3 raider, 2 breacher, 1 overseer |

### 4.2 Procedural Waves (9+)

Waves 9 and beyond are procedurally generated from a budget curve.

**Budget formula:**

```
budget(w) = 10 + (4 × w) + floor(0.5 × w²)
```

| Wave | Budget | Approximate threat level |
|---|---|---|
| 9 | 87 | Slightly above wave 8 |
| 10 | 100 | First triple-digit wave |
| 15 | 183 | Mid-game escalation |
| 20 | 290 | Heavy sustained assault |
| 25 | 423 | Requires layered defenses |
| 30 | 580 | Late-game stress test |
| 50 | 1,310 | Endgame |

### 4.3 Budget-Gated Enemy Unlocks

Enemy types become available for procedural composition once the wave budget exceeds a threshold. This prevents overly complex early waves and ensures a natural ramp.

| Enemy | Threat cost | Min budget to appear | First possible wave (procedural) |
|---|---|---|---|
| swarmling | 1 | 0 | Always |
| drone_scout | 2 | 0 | Always |
| raider | 5 | 20 | Wave 9 (budget 87) — already unlocked |
| breacher | 8 | 30 | Wave 9 (budget 87) — already unlocked |
| overseer | 14 | 60 | Wave 9 (budget 87) — already unlocked |
| ~~artillery_bug~~ | ~~10~~ | ~~45~~ | **Deferred to post-v1** |

> Note: artillery_bug is defined in data but deferred to post-v1. The v1 enemy roster is 5 types: swarmling, drone_scout, raider, breacher, overseer.

### 4.4 Procedural Composition Algorithm

Given a wave budget `B` and the set of unlocked enemy types:

1. **Reserve 30% of budget for swarmlings** — guarantees every wave has fodder.
2. **Spend remaining 70% greedily** — pick a random unlocked enemy type, subtract its cost, repeat until budget is exhausted.
3. **Fill remainder with swarmlings** — any leftover budget < cheapest unlocked non-swarmling type gets spent on swarmlings.
4. **Apply difficulty multiplier** — Hard: budget × 1.15, Easy: budget × 0.85.

This produces varied compositions where every wave has a swarmling screen and a random mix of heavier threats.

---

## 5. Spawn Mechanics

### 5.1 Spawn Point Selection

For each wave surge, the system picks **2–4 spawn clusters** along the map edge:

1. Generate a random angle (0–360°) for each cluster.
2. Map the angle to a position on the map border.
3. Ensure clusters are separated by at least 60° of arc to prevent stacking.
4. Distribute the wave's enemies across clusters (roughly even split, ±20% random variance).

### 5.2 Spawn Stagger

Enemies within a cluster don't all appear on the same tick. They spawn with a stagger delay to create a streaming effect:

- **Stagger interval**: 3 ticks (150ms at 20 Hz) between each enemy in a cluster.
- **Cluster activation delay**: Clusters activate 0–40 ticks (0–2s) apart, so different directions hit at slightly different times.

### 5.3 Spawn Edge Buffer

Enemies spawn 2 cells outside the playable map border and path inward. This gives turrets on the perimeter a brief window to begin firing before enemies reach structures.

---

## 6. Enemy Behavior

### 6.1 Core Pathfinding

All enemies use the **shared flow field** (see `combat_rendering_vfx.md` §4.2). The flow field is a BFS from the HQ, where walls and structures are impassable cells. Every enemy follows the flow field toward the HQ.

When the navigation map changes (structure placed, wall destroyed), the flow field is marked dirty and rebuilt.

### 6.2 Attack Behavior — Nearest Blocking Structure

Enemies do not have complex target selection. The behavior is:

1. **Follow flow field** toward HQ.
2. **When adjacent to an impassable structure** (wall, building) that blocks the path, attack it.
3. **When the structure is destroyed**, resume pathing (flow field rebuilds).
4. **When reaching HQ**, attack it.

This means:
- **Walls absorb attacks** because they block enemy paths. A complete wall perimeter guarantees enemies hit walls before anything else.
- **Gaps in the wall** let enemies flood through. They path past unblocked buildings and only attack what's directly in their way.
- **A broken wall** triggers flow field recalculation. Enemies reroute through the breach, potentially bypassing turrets on intact wall segments.

### 6.3 Enemy Type Behaviors

While the default is "attack nearest blocking structure," specific enemy types have behavioral modifiers:

| Enemy | Modifier |
|---|---|
| swarmling | None — pure flow field follower. Fast, fragile. |
| drone_scout | None — slightly tougher swarmling. |
| raider | **Structure seeker**: If a non-wall structure is within 4 cells and reachable without crossing a wall, the raider diverts to attack it instead of following the flow field. Targets the nearest qualifying structure. |
| breacher | **Wall breaker**: Deals 2× damage to walls. Prioritizes attacking walls even when a gap exists nearby. Bred to create breaches. |
| overseer | **Aura buffer**: Follows flow field normally but grants nearby enemies (4-cell radius) +25% damage and +15% speed. High priority target for the player. |
| ~~artillery_bug~~ | **Deferred to post-v1.** Ranged attacker concept: stops at range, fires projectiles at structures. Targeting behavior TBD. |

### 6.4 Death & Cleanup

When an enemy dies:
- It is removed from the entity store.
- A death event (`SimEvent.enemyDied`) is emitted for VFX/audio.
- No resource drops in v1. (Future: scrap/currency drops.)

---

## 7. Wall Fortification System

Walls are the defensive backbone. They block enemy pathing, absorb damage, and serve as the mounting point for turrets.

### 7.1 Wall Segments

| Property | Value |
|---|---|
| Grid footprint | 1×1 |
| Health (Basic) | 150 |
| Health (Reinforced, via `reactive_walls` tech) | 300 |
| Build cost | 1 wall_kit |
| Power draw | 0 |
| Blocks movement | Yes |
| Blocks flow field | Yes |

- Walls **auto-connect** visually to adjacent wall segments (N/S/E/W). The underlying data is still 1×1 grid cells; auto-connection is purely visual and determines the wall network topology.
- A **wall network** is a connected component of wall segments (4-directional adjacency).

### 7.2 Wall Tiers

| Tier | Unlock | HP | Special |
|---|---|---|---|
| Basic Wall | Available from start | 150 | — |
| Fortified Wall | `fortification` tech (Tier 2) | 165 (passive +10%) | — |
| Reinforced Wall | `reactive_walls` tech (Tier 4) | 300 (upgrade) | Reflects 10% melee damage to attackers |

The `fortification` passive bonus applies globally to all walls. The `reactive_walls` upgrade must be applied per-wall-segment (costs 2 wall_kit each).

### 7.3 Wall Repair

Walls can be repaired by delivering `repair_kit` items via conveyor to the wall network's ammo injection point (see §8). Repair kits restore HP:

- **Repair amount**: 50 HP per repair_kit consumed.
- **Repair rate**: 1 repair_kit consumed per second per wall network (repairs the most-damaged segment first).
- **Cannot exceed max HP**.

> Future enhancement (v2): Auto-repair from adjacent storage (gated by tech node).

### 7.4 Wall Destruction & Breach

When a wall segment reaches 0 HP:
1. The segment is removed from the grid.
2. The wall network potentially splits into two separate networks.
3. The flow field is marked dirty and rebuilds.
4. Enemies reroute through the breach.
5. If turrets were mounted on the destroyed segment, they are destroyed with it.
6. If the wall network carried ammo (§8), the network splits into independent pools.

**Breach cascading**: A single wall break can redirect an entire wave's worth of enemies into the interior. This makes breacher enemies extremely dangerous and wall repair a high-priority action.

---

## 8. Wall Ammo Network

Turrets require ammo to fire. Ammo reaches turrets through the wall network.

### 8.1 v1 — Shared Pool Model

In v1, each **wall network** (connected component of walls) shares a single ammo pool.

- A **conveyor connects to any wall segment** in the network, creating an **injection point**. Ammo items on the conveyor are deposited into the network's shared pool.
- **All turrets mounted on that wall network** draw from the same pool.
- The pool is **universal** — all ammo types (light, heavy, plasma) coexist. Turrets pull the type they need.
- When a turret fires, it consumes 1 ammo of the appropriate type from the pool.
- **If the pool has no ammo of the required type, the turret cannot fire** (dry fire event emitted).

**Pool capacity**: `segmentCount × 12` ammo. A 20-segment wall ring holds 240 ammo total.

**Network split**: If a wall segment is destroyed and the network splits, the pool is divided proportionally by segment count. Each resulting sub-network gets `(its segments / original total) × remaining ammo`, rounded down.

### 8.2 v2 — Flow Propagation Model (Future)

> Upgrades the shared pool to a per-segment buffer with flow propagation. Designed but deferred to post-v1.

- Each wall segment has a **local buffer** of 8–12 ammo.
- Ammo **propagates** from the injection point outward, filling adjacent segment buffers at a fixed rate (4 ammo/sec per segment-to-segment link).
- Turrets draw from the **buffer of the wall segment they sit on**.
- **Flow rate bottleneck**: Long wall runs naturally starve the far ends. Multiple injection points provide better coverage.
- **Breach cascading**: A destroyed segment cuts off downstream buffers from the supply. Turrets beyond the break fire on reserves only — then go silent.
- **Drain order**: Turrets near the injection point get ammo first and fire first. When supply is interrupted, they drain first (they've been actively consuming). Downstream turrets received ammo last but retain their buffer reserves longer.

---

## 9. Turret Mounting

Turrets are **not standalone buildings**. They are mounted on wall segments.

### 9.1 Placement Rules

- A turret can only be placed on a wall segment that does not already have a turret.
- One turret per wall segment (1:1).
- The turret inherits the wall segment's grid position for range calculations.
- Turret type must be unlocked via tech tree (see `tech_tree_runtime.md`).
- Turret build cost is paid from player resources as normal (see `building_specifications.md`).

### 9.2 Turret Stats

Turrets consume ammo from their wall network (§8) at their fire rate when targets are in range:

| Turret | Ammo type | Fire rate | Range | Damage | Ammo/sec |
|---|---|---|---|---|---|
| turret_mk1 | ammo_light | 2.0/s | 8.0 | 12 | 2.0 |
| gattling_tower | ammo_light | 4.2/s | 6.5 | 8 | 4.2 |
| turret_mk2 | ammo_heavy | 1.4/s | 10.0 | 25 | 1.4 |
| plasma_sentinel | ammo_plasma | 0.9/s | 11.0 | 45 | 0.9 |

### 9.3 Turret Destruction

Turrets have **independent health (100 HP)** and can be damaged separately from their wall. However, if the wall segment a turret is mounted on is destroyed, **the turret is also destroyed regardless of its remaining HP**. This dual-vulnerability is the primary risk of wall breaches — losing turrets is expensive and leaves a gap in firepower.

The turret's build cost is **not refunded** on destruction.

---

## 10. Difficulty Scaling Summary

All difficulty-dependent values in one place:

| Parameter | Easy | Normal | Hard |
|---|---|---|---|
| Grace period | 180s | 120s | 60s |
| Starting ore_iron | 30 | 20 | 12 |
| Starting ammo_light | 24 | 16 | 8 |
| Starting wall_kits | 8 | 6 | 3 |
| Starting processed bundle | plate/copper/steel + gear/circuit + turret_core | plate/copper/steel + gear/circuit + turret_core | plate/copper/steel + gear/circuit + turret_core |
| Inter-wave gap (base) | 120s | 90s | 60s |
| Inter-wave gap (floor) | 70s | 50s | 35s |
| Wave budget multiplier | ×0.85 | ×1.0 | ×1.15 |
| Trickle interval | 15s | 12s | 8s |
| Trickle size | 1 | 1–2 | 2–3 |
| Ore patches (Ring 0) | 7 | 5 | 3 |

---

## 11. Integration Points

### 11.1 Economy System (`factory_economy.md`)

- Ammo production chains feed wall network pools. Ammo throughput is the binding constraint on sustained defense.
- Wall_kit production is required for perimeter expansion. More factory = more perimeter = more wall_kits needed.
- Repair_kit production is required for wall maintenance under sustained assault.

### 11.2 Tech Tree (`tech_tree_runtime.md`)

- `defense_1`: Unlocks gattling_tower, +25 HP to turret mounts.
- `heavy_ammo`: Unlocks craft_ammo_heavy recipe, AoE splash.
- `fortification`: +10% wall HP globally.
- `turret_core_fabrication`: Unlocks turret_mk2.
- `plasma_research`: Unlocks plasma_sentinel, +1 turret range globally.
- `reactive_walls`: Reinforced Wall upgrade (300 HP), 10% melee reflect.
- `mk2_turrets`: Turret Mk2 upgrade for all mounts, +10% fire rate.
- `explosive_payloads`: Enhanced AoE, +1 ammo_heavy per batch.

### 11.3 Combat Rendering (`combat_rendering_vfx.md`)

- Flow field pathfinding drives all enemy movement.
- Spatial grid provides turret target acquisition (nearest enemy in range).
- Projectile physics governs turret-to-enemy damage delivery.
- Interpolation bridge smooths 20 Hz enemy movement to 60 FPS.

### 11.4 Building Specifications (`building_specifications.md`)

- Wall segments are buildings in the entity store with special properties (blocks flow field, carries ammo network).
- Turrets are child entities of wall segments rather than standalone buildings.
- Conveyor injection points are port connections between conveyor endpoints and wall segments.

### 11.5 Ore Patches (`ore_patches_resource_nodes.md`)

- Outer ore patches (Ring 1+) force the player to expand their perimeter.
- Expansion increases the surface area enemies can attack.
- This creates the core tension: expand for resources, but defend more perimeter.

---

## 12. Data Schema Changes

### 12.1 New: `hq.json`

```json
{
  "id": "hq",
  "displayName": "Headquarters",
  "footprint": { "width": 2, "height": 2 },
  "health": 500,
  "storageCapacity": 24,
  "powerDraw": 0,
  "startingResources": {
    "normal": {
      "ore_iron": 20, "ore_copper": 12, "ore_coal": 6,
      "plate_iron": 14, "plate_copper": 6, "plate_steel": 8,
      "gear": 4, "circuit": 4, "turret_core": 1,
      "wall_kit": 6, "ammo_light": 16
    },
    "easy": {
      "ore_iron": 30, "ore_copper": 20, "ore_coal": 10,
      "plate_iron": 18, "plate_copper": 8, "plate_steel": 10,
      "gear": 5, "circuit": 5, "turret_core": 2,
      "wall_kit": 8, "ammo_light": 24
    },
    "hard": {
      "ore_iron": 12, "ore_copper": 8, "ore_coal": 4,
      "plate_iron": 10, "plate_copper": 4, "plate_steel": 6,
      "gear": 3, "circuit": 2, "turret_core": 1,
      "wall_kit": 3, "ammo_light": 8
    }
  }
}
```

### 12.2 Extend: `enemies.json`

Add fields to each enemy definition:

```json
{
  "id": "breacher",
  "health": 70,
  "speed": 0.9,
  "threatCost": 8,
  "baseDamage": 15,
  "behaviorModifier": "wallBreaker",
  "wallDamageMultiplier": 2.0,
  "minBudgetToSpawn": 30
}
```

New fields: `baseDamage`, `behaviorModifier`, `wallDamageMultiplier` (optional), `minBudgetToSpawn`.

Behavior modifiers: `none`, `structureSeeker`, `wallBreaker`, `rangedAttacker`, `auraBuffer`.

### 12.3 Extend: `waves.json`

Add procedural generation parameters:

```json
{
  "handAuthoredWaves": [ ... existing waves 1-8 ... ],
  "proceduralConfig": {
    "budgetFormula": { "base": 10, "linear": 4, "quadratic": 0.5 },
    "swarmlingReserveRatio": 0.3,
    "difficultyMultipliers": { "easy": 0.85, "normal": 1.0, "hard": 1.15 }
  }
}
```

### 12.4 New: `difficulty.json`

```json
{
  "easy": {
    "gracePeriodSeconds": 180,
    "interWaveGapBase": 120,
    "interWaveGapFloor": 70,
    "gapCompressionPerWave": 2,
    "trickleIntervalSeconds": 15,
    "trickleSize": [1, 1],
    "waveBudgetMultiplier": 0.85
  },
  "normal": {
    "gracePeriodSeconds": 120,
    "interWaveGapBase": 90,
    "interWaveGapFloor": 50,
    "gapCompressionPerWave": 2,
    "trickleIntervalSeconds": 12,
    "trickleSize": [1, 2],
    "waveBudgetMultiplier": 1.0
  },
  "hard": {
    "gracePeriodSeconds": 60,
    "interWaveGapBase": 60,
    "interWaveGapFloor": 35,
    "gapCompressionPerWave": 2,
    "trickleIntervalSeconds": 8,
    "trickleSize": [2, 3],
    "waveBudgetMultiplier": 1.15
  }
}
```

---

## 13. Implementation Sequencing

### Phase 1 — Wave Timer & Budget Spawning
- Implement `WaveSystem` that runs on a continuous timer (no phase gates).
- Read hand-authored waves from `waves.json` for waves 1–8.
- Implement budget formula for wave 9+ with procedural composition algorithm (§4.4).
- Add grace period timer before first trickle/wave.
- Add trickle spawn logic between surges.
- Emit `SimEvent.waveStarted`, `SimEvent.waveCleared` events.

### Phase 2 — Spawn Point Selection
- Implement perimeter spawn point selection (§5.1): 2–4 clusters per surge, 60°+ separation.
- Add stagger delay for within-cluster spawning.
- Add edge buffer (enemies spawn 2 cells outside map border).

### Phase 3 — HQ Building
- Define HQ entity type (2×2, 500 HP, storage I/O).
- Place HQ at map center on game start.
- Load starting resources per difficulty.
- Implement loss condition: HQ health ≤ 0 → `RunState.lost`.

### Phase 4 — Wall Network & Turret Mounting
- Extend wall entity with network membership tracking (connected component ID).
- Implement wall network auto-detection (recalculate on wall place/destroy).
- Implement shared ammo pool per wall network (v1 model, §8.1).
- Change turret placement to require a wall segment host.
- Turret destruction on wall destruction.

### Phase 5 — Enemy Behavior Modifiers
- Implement raider structure-seeking (§6.3).
- Implement breacher wall-damage multiplier.
- Implement artillery_bug ranged attack behavior.
- Implement overseer aura buff.

### Phase 6 — Difficulty Scaling
- Load `difficulty.json` configuration.
- Apply difficulty multipliers to: grace period, wave gaps, trickle rate, budgets, starting resources.
- Integrate with ore patch counts from `ore_patches_resource_nodes.md`.

### Phase 7 — Wall Ammo Network v2 (Post-v1)
- Replace shared pool with per-segment buffers.
- Implement ammo flow propagation along wall segments.
- Implement breach-induced network splits with buffer isolation.
- Add flow rate bottleneck for long wall runs.

---

## 14. Open Questions

| Question | Recommendation | Status |
|---|---|---|
| Should walls have an upkeep cost (decay over time)? | No for v1. Wall repair via damage is enough resource pressure. | Deferred |
| Can enemies damage conveyors that are outside walls? | Yes — conveyors have 30 HP (see `building_specifications.md`). Trickle scouts will nibble exposed logistics. | Recommended |
| Should the overseer buff stack from multiple overseers? | No — aura should be non-stacking. Multiple overseers add threat through their own HP, not compounding buffs. | Recommended |
| Should there be a "wave survived" reward (currency/resources)? | Deferred to extraction/meta-progression design. | Open |
| Maximum number of concurrent enemies? | Cap at 500 for v1 (performance budget). Budget formula naturally limits this through enemy cost. | Recommended |
