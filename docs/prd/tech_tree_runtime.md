# Tech Tree Runtime PRD

**Version:** 1.0-draft
**Parent:** `docs/GAME_PRD_LIVING.md`
**Status:** Forward-looking v1 design
**Last updated:** 2026-02-15

> **Core truth:** The tech tree is the third investment axis. Production buys present survival, defense buys spatial control, and research buys future capability. Every item consumed by research is an item not feeding turrets right now.

**Companion docs:**
- [`factory_economy.md`](factory_economy.md) — build costs, resource system, structure upgrades (section 6.5), economy-combat coupling
- [`building_specifications.md`](building_specifications.md) — per-building specs, port/buffer model, conveyor system

---

## Table of Contents

1. [Design Intent](#1-design-intent)
2. [Lab Building Specification](#2-lab-building-specification)
3. [Research Flow](#3-research-flow)
4. [Tech Node Effect Taxonomy](#4-tech-node-effect-taxonomy)
5. [Gating Rules](#5-gating-rules)
6. [Simulation Integration](#6-simulation-integration)
7. [Determinism](#7-determinism)
8. [UI Requirements](#8-ui-requirements)
9. [Balance Framework](#9-balance-framework)
10. [Implementation Sequencing](#10-implementation-sequencing)
- [Appendix A: Extended TechNodeDef Schema](#appendix-a-extended-technodedef-schema)
- [Appendix B: Implementation Priority Matrix](#appendix-b-implementation-priority-matrix)
- [Appendix C: Files Requiring Modification](#appendix-c-files-requiring-modification)

---

## Terminology

| Term | Definition |
|------|-----------|
| **Tech node** | A single researchable entry in the tech tree, defined in `tech_nodes.json` |
| **Research** | The act of consuming items and accumulating progress over time to unlock a tech node |
| **Lab** | A 2x2 production structure that performs research; research speed scales with Lab count |
| **Gating** | Requiring a specific tech node to be unlocked before allowing an action (building, recipe, upgrade) |
| **Passive bonus** | A persistent modifier applied when a tech node is unlocked, affecting structure stats or economy formulas |
| **Tier** | Depth in the tech tree DAG; root = Tier 0, its children = Tier 1, etc. |
| **TechState** | The simulation-side struct tracking unlocked nodes, active research, and progress |

---

## 1. Design Intent

### 1.1 The Third Axis

The game's tension triangle (factory_economy.md §1.2) currently has two investment axes: **production expansion** (more miners, smelters, ammo modules) and **defense expansion** (more turrets, walls). The tech tree adds a third: **research investment**.

```
         Production Expansion
              /        \
             /          \
    Defense Expansion -- Research Investment
```

Every item consumed by research is an item not available for building structures or feeding turrets. A player who researches aggressively runs leaner defenses in the short term but unlocks superior buildings, recipes, and bonuses for the mid and late game. A player who ignores research survives early waves comfortably but hits a ceiling when enemies outscale their base-tier production.

### 1.2 Core Tension

**Short-term output vs. long-term capability.** Research costs are paid in produced items — the same items used for build costs and turret operation. Starting research on `steel_working` (25 plate_steel) means 25 fewer plates available for heavy ammo, walls, or turret cores. The player must judge when they have enough surplus to invest without starving defenses.

### 1.3 Progression Feel by Phase

| Phase | Waves | Research Feel |
|-------|-------|---------------|
| Early | 1-4 | Player builds their first Lab (wave 2-3), starts first Tier 1 research. Costs are cheap (20 plates, 40 ammo). Learning the system. First Tier 1 unlock around wave 3-5. |
| Mid | 5-9 | 2-3 Tier 2 nodes unlocked. Steel and electronics branches open. Gated buildings (gattling_tower, storage) become available. Multi-Lab setups appear. |
| Late | 10+ | Tier 3-4 nodes provide decisive upgrades (Mk2 turrets, plasma, auto-repair). Research costs compete heavily with combat consumption. Completing the tree is a late-game achievement, not a mid-game expectation. |

### 1.4 Implementation Status

| Aspect | Status |
|--------|--------|
| 19 tech nodes in `tech_nodes.json` | Exists |
| `TechTreeViewModel` in GameUI | Exists — UI-only, not simulation-integrated |
| `TechNodeDef` content type | Exists — loaded and validated |
| `TechState` on `WorldState` | Gap — no simulation-side tech state |
| Lab building | Gap — no `StructureType.lab` |
| Research commands (`startResearch`, `cancelResearch`) | Gap — not in `CommandPayload` |
| `TechSystem` | Gap — no simulation system for research |
| Gating checks in `CommandSystem` | Gap — no tech prerequisite validation |
| Passive bonuses | Gap — no bonus application |

---

## 2. Lab Building Specification

### 2.1 Building Definition

The Lab is a dedicated research structure. It does not produce items — it converts items into tech progress over time.

```
       N
   +---+---+
W  | L   A |  E
   | B     |
   +---+---+
       S
   (no item ports)
```

| Property | Value |
|----------|-------|
| Grid footprint | **2x2** |
| Input ports | None (items consumed directly from global inventory on research start) |
| Output ports | None |
| Internal buffer | N/A |
| Recipes | None (research is not recipe-driven) |
| Power draw | **5** |
| Health | **80** |
| Build cost | **4 plate_steel + 2 circuit + 2 gear** |
| Blocks movement | Yes |

### 2.2 Design Rationale

- **2x2 footprint:** Larger than production buildings (1x1). Research is a significant spatial investment — the Lab competes for grid real estate with turrets, production chains, and walls. The player feels the physical cost of committing to research.
- **5 power draw:** Higher than any single production building (ammo module = 4, smelter = 3). With a 12-supply power plant, a Lab consumes nearly half the output. Forces a power plant expansion decision.
- **80 HP:** Same as smelter/assembler. Labs are vulnerable to structure-targeting enemies (artillery_bug), creating defend-your-investment pressure.
- **No ports/conveyors:** Research items are consumed from global inventory on research start, not routed via conveyors. This keeps Labs placement-flexible and avoids forcing a conveyor feed for a non-production building.
- **Build cost:** 4 plate_steel + 2 circuit + 2 gear requires Tier 1+ production chains (steel smelting, circuit etching, gear forging). The Lab is not an early wave 1 structure — it requires investment in intermediate production first.

### 2.3 Multi-Lab Scaling

Multiple Labs accelerate active research:

```
researchSpeedMultiplier = 1.0 + (additionalLabCount x 0.5)
```

| Lab Count | Speed Multiplier | Effective Research Time (100s base) |
|-----------|------------------|-------------------------------------|
| 1 | 1.0x | 100s |
| 2 | 1.5x | 67s |
| 3 | 2.0x | 50s |
| 4 | 2.5x | 40s |

**Diminishing returns by cost, not formula.** The formula is linear (+0.5x per Lab), but each additional Lab costs 4 plate_steel + 2 circuit + 2 gear + 5 power + 4 grid tiles. The marginal cost of the 3rd Lab (power plant needed, space constrained) far exceeds the 1st. This creates a natural soft cap — most players will run 1-2 Labs.

### 2.4 Lab Requirements

- At least one Lab must exist and be alive (HP > 0) for research to progress.
- If all Labs are destroyed mid-research, progress is **paused** (not lost). Rebuilding a Lab resumes from where it stopped.
- Labs require power. If power efficiency < 1.0, research speed is scaled by efficiency (same as production structures):
  ```
  effectiveResearchSpeed = researchSpeedMultiplier x powerEfficiency
  ```
- A Lab at 0 efficiency (blackout) contributes nothing to research speed.

---

## 3. Research Flow

### 3.1 Command-Driven Research

Research is initiated and cancelled via `PlayerCommand` objects, maintaining the simulation's deterministic command pattern.

**Start research:**
```
PlayerCommand(
    tick: currentTick,
    actor: playerID,
    payload: .startResearch(nodeID: "steel_working")
)
```

**Cancel research:**
```
PlayerCommand(
    tick: currentTick,
    actor: playerID,
    payload: .cancelResearch
)
```

### 3.2 Start Research Validation

When `CommandSystem` processes a `startResearch(nodeID)` command, it validates in order:

1. **Lab exists** — at least one `StructureType.lab` entity exists in `EntityStore` with HP > 0.
2. **No active research** — `TechState.activeResearch` is nil (one research at a time globally).
3. **Not already unlocked** — `nodeID` is not in `TechState.unlockedNodes`.
4. **Prerequisites met** — all entries in the node's `prerequisites` array are in `TechState.unlockedNodes`.
5. **Items available** — `EconomyState.inventories` contains all items in the node's `costs` array.

If any check fails, emit `SimEvent.researchFailed(nodeID, reason)` with a specific failure reason. No state changes.

If all checks pass:
1. **Consume items** — deduct all cost items from `EconomyState.inventories`.
2. **Set active research** — `TechState.activeResearch = ResearchProgress(nodeID: nodeID, accumulatedTicks: 0)`.
3. **Emit event** — `SimEvent.researchStarted(nodeID)`.

### 3.3 Research Progress Accumulation

`TechSystem.update()` runs once per tick. If `TechState.activeResearch` is non-nil:

```
let labCount = entityStore.structures(ofType: .lab).filter { $0.health > 0 }.count
guard labCount > 0 else { return }  // paused — no alive Labs

let speedMultiplier = 1.0 + (Double(labCount - 1) * 0.5)
let efficiency = economyState.efficiency  // min(1.0, supply / demand)
let effectiveSpeed = speedMultiplier * efficiency

activeResearch.accumulatedTicks += effectiveSpeed
```

Progress is stored as accumulated effective ticks (a `Double`). The target is `researchSeconds x 20.0` ticks.

### 3.4 Research Completion

When `activeResearch.accumulatedTicks >= targetTicks`:

1. **Unlock node** — add `nodeID` to `TechState.unlockedNodes`.
2. **Apply passive bonuses** — if the node has passive effects, apply them (see §4).
3. **Clear active research** — `TechState.activeResearch = nil`.
4. **Emit event** — `SimEvent.researchCompleted(nodeID)`.

### 3.5 Cancel Research

When `CommandSystem` processes `cancelResearch`:

1. **Check active** — if `TechState.activeResearch` is nil, no-op.
2. **Refund 50%** — return `floor(cost x 0.5)` for each item in the node's `costs` array to `EconomyState.inventories`.
3. **Clear active research** — `TechState.activeResearch = nil`.
4. **Emit event** — `SimEvent.researchCancelled(nodeID, refundedItems)`.

Progress is lost on cancellation. The player must restart from zero if they re-research the same node.

---

## 4. Tech Node Effect Taxonomy

All 19 nodes from `tech_nodes.json` with their assigned effects. Each node falls into one or more effect categories.

### 4.1 Effect Categories

| Category | Description | When Applied |
|----------|-------------|--------------|
| **Building gate** | Unlocks a `StructureType` for placement | `CommandSystem` checks before `placeStructure` |
| **Recipe gate** | Unlocks a recipe for use by production buildings | Recipe auto-selection and pinning filter by unlocked recipes |
| **Upgrade gate** | Unlocks an in-place structure upgrade | `CommandSystem` checks before `upgradeStructure` |
| **Passive bonus** | Modifies a structure or economy parameter | Applied at query-time from `TechState` |
| **Mechanic unlock** | Enables a gameplay mechanic not available at start | System-specific checks against `TechState` |

### 4.2 Complete Node Effect Table

#### Tier 0 — Root

| Node | Costs | Prerequisites | Effects |
|------|-------|---------------|---------|
| `root` | Free | None | Auto-unlocked at game start. No direct effects — serves as the tree root. |

#### Tier 1 — Foundation Branches

| Node | Costs | Prerequisites | Effects |
|------|-------|---------------|---------|
| `logistics_1` | 20 plate_iron | root | **Passive bonus:** conveyors draw 0 power (down from 1). (Conveyors are ungated — available from start. This node rewards early logistics investment with free conveyor power.) |
| `defense_1` | 40 ammo_light | root | **Building gate:** unlocks `gattling_tower` turret type. **Passive bonus:** all turret mounts gain +25 HP (100 -> 125). |
| `smelting_advanced` | 20 plate_copper | root | **Recipe gate:** unlocks `smelt_steel` recipe. **Upgrade gate:** Smelter Mk2 upgrade (1.3x production speed, cost: 3 plate_steel + 2 gear). **Passive bonus:** smelters gain +15% production speed (craft progress += 1.15x base rate). |

#### Tier 2 — Specialization

| Node | Costs | Prerequisites | Effects |
|------|-------|---------------|---------|
| `conveyor_mk2` | 12 gear | logistics_1 | **Building gate:** unlocks `splitter` and `merger` placement. **Upgrade gate:** Miner Mk2 upgrade (1.5x extraction rate, cost: 4 gear + 2 circuit). **Building gate:** unlocks `conveyor_mk2` building variant (faster conveyors, 3 ticks/tile instead of 5). |
| `storage_bins` | 14 plate_steel | logistics_1 | **Building gate:** unlocks `storage` placement. **Passive bonus:** global inventory base capacity +50 (100 -> 150). |
| `heavy_ammo` | 25 ammo_heavy | defense_1 | **Recipe gate:** unlocks `craft_ammo_heavy` recipe. **Mechanic unlock:** heavy ammo has AoE splash damage (2-cell radius, 40% damage to adjacent enemies). |
| `fortification` | 16 wall_kit | defense_1 | **Passive bonus:** walls gain +10% HP (150 -> 165). |
| `steel_working` | 25 plate_steel | smelting_advanced | **Recipe gate:** unlocks `craft_turret_core` recipe. **Passive bonus:** power plants generate +3 power each (12 -> 15). |
| `electronics_1` | 20 circuit | smelting_advanced | **Recipe gate:** unlocks `assemble_power_cell` recipe. (Assembler building is ungated — available from start for gear, circuit, and other base recipes.) |
| `geology_survey_1` | 12 gear | logistics_1 | **Mechanic unlock:** reveals Ring 1 ore patches (distance 7–14 tiles). See `ore_patches_resource_nodes.md` §8. |

#### Tier 3 — Advanced

| Node | Costs | Prerequisites | Effects |
|------|-------|---------------|---------|
| `logistics_2` | 22 plate_steel | conveyor_mk2, storage_bins | **Mechanic unlock:** conveyor priority routing — players can set item filters on splitters. **Passive bonus:** storage internal capacity +12 (48 -> 60). |
| `turret_core_fabrication` | 8 turret_core | steel_working | **Building gate:** unlocks `turret_mk2` turret type. **Upgrade gate:** Turret Mk2 upgrade (uses `turret_mk2` stats, cost: 2 turret_core). |
| `power_cells` | 12 power_cell | electronics_1 | **Recipe gate:** unlocks `craft_ammo_plasma` recipe. **Passive bonus:** ammo module output buffer +4 (8 -> 12). |
| `plasma_research` | 12 ammo_plasma | electronics_1 | **Building gate:** unlocks `plasma_sentinel` turret type. **Passive bonus:** all turrets gain +1 range. |
| `geology_survey_2` | 18 plate_steel | geology_survey_1 | **Mechanic unlock:** reveals Ring 2 ore patches (distance 15–22 tiles). See `ore_patches_resource_nodes.md` §8. |

#### Tier 4 — Endgame

| Node | Costs | Prerequisites | Effects |
|------|-------|---------------|---------|
| `mk2_turrets` | 12 turret_core | turret_core_fabrication | **Upgrade gate:** Turret Mk2 upgrade for all turret mounts (uses `turret_mk2` stats). **Passive bonus:** turret fire rate +10% (ticks between shots reduced by 10%, rounded). |
| `explosive_payloads` | 35 ammo_heavy | heavy_ammo | **Mechanic unlock:** heavy ammo AoE radius increased to 3 cells, damage to adjacent increased to 60%. **Passive bonus:** ammo_heavy recipe output +1 per batch (3 -> 4). |
| `reactive_walls` | 30 wall_kit | fortification | **Upgrade gate:** Reinforced Wall upgrade (2x health, 150 -> 300, cost: 2 wall_kit). **Mechanic unlock:** walls reflect 10% of melee damage back to attacking enemies. |
| `automated_repair` | 18 repair_kit | logistics_2 | **Mechanic unlock:** structures adjacent to a storage containing repair_kits auto-repair 2 HP/second. Consumes 1 repair_kit per 20 HP repaired. |
| `plasma_turrets` | 25 ammo_plasma | power_cells, plasma_research | **Passive bonus:** plasma_sentinel damage +10 (45 -> 55). |
| `geology_survey_3` | 14 circuit | geology_survey_2 | **Mechanic unlock:** reveals Ring 3 ore patches (distance 23–32 tiles). See `ore_patches_resource_nodes.md` §8. |

### 4.3 Effect Summary by Category

**Building gates (5 nodes):**

| Node | Unlocked Building/Turret |
|------|------------------------|
| `logistics_1` | conveyor (if gated) |
| `defense_1` | gattling_tower |
| `conveyor_mk2` | splitter, merger, conveyor_mk2 (faster variant) |
| `storage_bins` | storage |
| `plasma_research` | plasma_sentinel |

**Recipe gates (5 nodes):**

| Node | Unlocked Recipe |
|------|----------------|
| `smelting_advanced` | smelt_steel |
| `heavy_ammo` | craft_ammo_heavy |
| `steel_working` | craft_turret_core |
| `electronics_1` | assemble_power_cell |
| `power_cells` | craft_ammo_plasma |

**Upgrade gates (5 nodes):**

| Node | Unlocked Upgrade | Cost |
|------|-----------------|------|
| `conveyor_mk2` | Miner Mk2 (1.5x extraction) | 4 gear + 2 circuit |
| `turret_core_fabrication` | Turret Mk2 (turret_mk2 stats) | 2 turret_core |
| `mk2_turrets` | Turret Mk2 (all mounts) | 2 turret_core |
| `reactive_walls` | Reinforced Wall (2x HP) | 2 wall_kit |
| `smelting_advanced` | Smelter Mk2 (1.3x speed) | 3 plate_steel + 2 gear |

**Passive bonuses (10 nodes):**

| Node | Bonus |
|------|-------|
| `logistics_1` | Conveyors: 0 power draw |
| `defense_1` | Turret mounts: +25 HP |
| `smelting_advanced` | Smelters: +15% speed |
| `storage_bins` | Global inventory: +50 base capacity |
| `heavy_ammo` | (AoE mechanic, see below) |
| `fortification` | Walls: +10% HP |
| `steel_working` | Power plants: +3 generation |
| `plasma_research` | Turrets: +1 range |
| `logistics_2` | Storage: +12 internal capacity |
| `power_cells` | Ammo modules: +4 output buffer |
| `mk2_turrets` | Turrets: +10% fire rate |
| `explosive_payloads` | Heavy ammo: +1 output per batch |
| `plasma_turrets` | Plasma sentinel: +10 damage |

**Mechanic unlocks (7 nodes):**

| Node | Mechanic |
|------|----------|
| `heavy_ammo` | AoE splash on heavy ammo (2-cell, 40%) |
| `logistics_2` | Splitter item filtering |
| `explosive_payloads` | Enhanced AoE (3-cell, 60%) |
| `reactive_walls` | Damage reflect (10% melee) |
| `automated_repair` | Auto-repair from adjacent storage |
| `geology_survey_1` | Reveals Ring 1 ore patches |
| `geology_survey_2` | Reveals Ring 2 ore patches |
| `geology_survey_3` | Reveals Ring 3 ore patches |

---

## 5. Gating Rules

### 5.1 Building Placement Gating

When `CommandSystem` processes `placeStructure(BuildRequest)`, it checks the building/turret type against the gating table before the existing placement validation (bounds, occupancy, cost):

```swift
let gatedBuildings: [StructureType: String] = [
    .storage:    "storage_bins",
]

let gatedTurrets: [String: String] = [
    "gattling_tower":   "defense_1",
    "turret_mk2":       "turret_core_fabrication",
    "plasma_sentinel":  "plasma_research",
]

// Splitter and Merger (when added as StructureType cases)
let gatedLogistics: [StructureType: String] = [
    .splitter: "conveyor_mk2",
    .merger:   "conveyor_mk2",
]
```

If the required tech node is not in `TechState.unlockedNodes`, emit `SimEvent.placementFailed(reason: .techRequired(nodeID))` and reject the command.

### 5.2 Recipe Gating

Recipes available to a building are filtered by tech state:

```swift
let gatedRecipes: [String: String] = [
    "smelt_steel":          "smelting_advanced",
    "craft_ammo_heavy":     "heavy_ammo",
    "craft_turret_core":    "steel_working",
    "assemble_power_cell":  "electronics_1",
    "craft_ammo_plasma":    "power_cells",
]
```

During recipe auto-selection and recipe pinning validation, only recipes whose gate is either absent (ungated) or present in `TechState.unlockedNodes` are considered. Ungated recipes (`smelt_iron`, `smelt_copper`, `forge_gear`, `etch_circuit`, `craft_ammo_light`, `craft_wall_kit`, `craft_repair_kit`) are always available.

### 5.3 Upgrade Gating

Structure upgrades (factory_economy.md §6.5) require their gate node:

```swift
let gatedUpgrades: [String: String] = [
    "miner_mk2":       "conveyor_mk2",
    "smelter_mk2":     "smelting_advanced",
    "turret_mk2":      "mk2_turrets",
    "reinforced_wall":  "reactive_walls",
]
```

### 5.4 Gating Check Order

For all gated actions, tech checks occur **before** cost checks. This provides better player feedback — "Research X first" is more actionable than "Not enough resources" when the player hasn't unlocked the prerequisite.

Validation order for `placeStructure`:
1. Tech gate check
2. Bounds check
3. Cell availability check
4. Cost check
5. Type-specific rules (ore patch adjacency, etc.)

---

## 6. Simulation Integration

### 6.1 New Types

**TechState** — added to `WorldState`:

```swift
public struct TechState: Codable, Hashable, Sendable {
    public var unlockedNodes: Set<String>
    public var activeResearch: ResearchProgress?

    public init(unlockedNodes: Set<String> = ["root"], activeResearch: ResearchProgress? = nil) {
        self.unlockedNodes = unlockedNodes
        self.activeResearch = activeResearch
    }
}

public struct ResearchProgress: Codable, Hashable, Sendable {
    public var nodeID: String
    public var accumulatedTicks: Double  // effective ticks accumulated

    public init(nodeID: String, accumulatedTicks: Double = 0.0) {
        self.nodeID = nodeID
        self.accumulatedTicks = accumulatedTicks
    }
}
```

**WorldState extension:**

```swift
public struct WorldState: Codable, Hashable, Sendable {
    // ... existing fields ...
    public var tech: TechState  // NEW
}
```

Bootstrap initializes with `TechState(unlockedNodes: ["root"])`.

### 6.2 New Command Payloads

```swift
public enum CommandPayload: Codable, Hashable, Sendable {
    // ... existing cases ...
    case startResearch(nodeID: String)   // NEW
    case cancelResearch                  // NEW
}
```

### 6.3 New Simulation Events

```swift
public enum SimEvent {
    // ... existing cases ...
    case researchStarted(nodeID: String)
    case researchCompleted(nodeID: String)
    case researchCancelled(nodeID: String, refundedItems: [ItemStack])
    case researchFailed(nodeID: String, reason: ResearchFailureReason)
}

public enum ResearchFailureReason: Codable, Hashable, Sendable {
    case noLab
    case alreadyResearching
    case alreadyUnlocked
    case prerequisitesNotMet
    case insufficientItems
}
```

### 6.4 TechSystem

New system implementing `SimulationSystem`. Runs **between Conveyor and Wave** in the execution order (8 systems total):

```
Command > Economy/Production > Conveyor > Tech > Wave > EnemyMovement > Combat > Projectile
```

**Why between Conveyor and Wave:** Research progress depends on power efficiency (computed by Economy) and should complete before Wave checks enable new wave-phase behaviors that might depend on tech state. Conveyor runs before Tech so item deliveries are resolved before research completion checks.

**TechSystem.update() logic:**

```swift
func update(state: inout WorldState, context: SystemContext) {
    guard var research = state.tech.activeResearch else { return }

    // Count alive Labs
    let labCount = state.entities.structures(ofType: .lab)
        .filter { state.entities[$0]?.health ?? 0 > 0 }
        .count
    guard labCount > 0 else { return }  // paused

    // Calculate speed
    let speedMultiplier = 1.0 + (Double(labCount - 1) * 0.5)
    let efficiency = state.economy.efficiency
    let effectiveSpeed = speedMultiplier * efficiency

    research.accumulatedTicks += effectiveSpeed

    // Look up target from content
    let nodeDef = contentLoader.techNode(id: research.nodeID)
    let targetTicks = nodeDef.researchSeconds * 20.0

    if research.accumulatedTicks >= targetTicks {
        // Unlock
        state.tech.unlockedNodes.insert(research.nodeID)
        state.tech.activeResearch = nil
        context.emit(.researchCompleted(research.nodeID))
    } else {
        state.tech.activeResearch = research
    }
}
```

### 6.5 CommandSystem Extensions

`CommandSystem` handles `startResearch` and `cancelResearch` commands and adds tech gate checks to existing commands:

**startResearch processing** — see §3.2 for full validation sequence.

**cancelResearch processing** — see §3.5 for refund logic.

**placeStructure gate check** — see §5.1, inserted before existing validation.

**Recipe filtering** — production systems filter available recipes per §5.2.

### 6.6 Passive Bonus Application

Passive bonuses are applied at **query-time**, not stored as persistent modifiers. This keeps the simulation simple and avoids stale modifier cleanup:

```swift
// Example: turret range with plasma_research bonus
func effectiveRange(for turretDef: TurretDef, tech: TechState) -> Double {
    var range = turretDef.range
    if tech.unlockedNodes.contains("plasma_research") {
        range += 1.0
    }
    return range
}

// Example: power generation with steel_working bonus
func effectivePowerGeneration(for structure: Entity, tech: TechState) -> Int {
    var power = structure.basePowerGeneration  // 12 for power plant
    if structure.type == .powerPlant && tech.unlockedNodes.contains("steel_working") {
        power += 3
    }
    return power
}

// Example: smelter speed with smelting_advanced bonus
func craftSpeedMultiplier(for structure: Entity, tech: TechState) -> Double {
    var multiplier = 1.0
    if structure.type == .smelter && tech.unlockedNodes.contains("smelting_advanced") {
        multiplier *= 1.15
    }
    return multiplier
}
```

This pattern scales cleanly — each bonus is a simple conditional check. The `TechState.unlockedNodes` set lookup is O(1).

### 6.7 New StructureType

```swift
public enum StructureType: String, Codable, CaseIterable, Sendable {
    // ... existing cases ...
    case lab  // NEW
}
```

Lab footprint: `StructureFootprint(width: 2, height: 2)`.

---

## 7. Determinism

### 7.1 Fixed-Tick Progress

Research progress uses the same deterministic tick accumulation as production:

```swift
accumulatedTicks += effectiveSpeed  // Double addition, deterministic per tick
```

- `effectiveSpeed` is computed from `labCount` (integer), `speedMultiplier` (deterministic Double formula), and `efficiency` (deterministic from integer power values).
- Completion check is `>=`, so minor floating-point variance cannot cause stuck research.

### 7.2 Pure Formulas

All passive bonus computations are pure functions of `TechState.unlockedNodes` (a `Set<String>`) and entity properties. No accumulated state, no order-dependent side effects.

### 7.3 IEEE 754 Compliance

The same guarantees from the existing simulation apply:
- All targets run ARM64 (Apple Silicon / A-series), ensuring identical IEEE 754 behavior.
- `Double` (64-bit) precision for `accumulatedTicks` avoids meaningful precision loss over even the longest research durations (120s = 2400 ticks, well within safe integer range for Double).
- No transcendental functions (sin, cos, sqrt) in research calculations — only addition, multiplication, and comparison.

### 7.4 Snapshot Compatibility

`TechState` is added to `WorldState` as a `Codable` struct:
- **Forward compatibility:** snapshots without `tech` field decode with a default `TechState(unlockedNodes: ["root"])`.
- **Backward compatibility:** older decoders ignore the new `tech` field via `decodeIfPresent`.

```swift
public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // ... existing fields ...
    self.tech = try container.decodeIfPresent(TechState.self, forKey: .tech)
        ?? TechState()
}
```

### 7.5 Replay Determinism

`startResearch` and `cancelResearch` commands are recorded in the command stream like all other commands. Replaying the same command stream against the same initial state produces identical `TechState` at every tick.

---

## 8. UI Requirements

### 8.1 Tech Node Visual States

Each node in the tech tree UI has one of four states:

| State | Visual | Condition |
|-------|--------|-----------|
| **Locked** | Grayed out, no interaction | Prerequisites not in `unlockedNodes` |
| **Available** | Full color, tappable | All prerequisites met, not yet unlocked, no active research |
| **Researching** | Pulsing glow, progress bar | `activeResearch.nodeID == this node` |
| **Unlocked** | Checkmark, solid fill | Node ID is in `unlockedNodes` |

### 8.2 TechTreeViewModel Migration

The existing `TechTreeViewModel` (GameUI/ProductionUI.swift) currently maintains its own `unlockedNodeIDs: Set<String>` and mutates UI state directly. This must be migrated to a **read-only projection** of `TechState`:

```swift
public struct TechTreeViewModel: Sendable {
    public var nodeDefs: [TechNodeDef]

    // Read from WorldState.tech — no longer mutable UI state
    public func nodes(techState: TechState, inventory: [ItemID: Int]) -> [TechNodePresentation] {
        // ... derive locked/available/researching/unlocked from TechState ...
    }
}
```

The `productionPreset` static factory should be removed in favor of loading full tech node data from `tech_nodes.json`.

### 8.3 Research Confirmation Dialog

When the player taps an available node:

1. Show a confirmation dialog with:
   - Node name and description
   - Item costs (with current inventory counts, highlighting shortages in red)
   - Estimated research time (accounting for current Lab count and power efficiency)
   - Effects that will be unlocked (building gates, recipes, bonuses)
2. "Start Research" button (enabled only if all items are available and no active research)
3. "Cancel" button

### 8.4 Lab Building HUD

When a Lab is selected:

- Current research status (node name, progress bar, estimated time remaining)
- "Cancel Research" button (with 50% refund warning)
- If no active research: "No research in progress"
- Lab count and speed multiplier display

### 8.5 Build Menu Gating Indicators

Buildings and turrets gated by tech show:

- A **lock icon** overlay on the build menu entry
- Tapping a locked entry shows: "Requires: [Tech Node Name]" with a button to navigate to that node in the tech tree
- Once unlocked, the lock icon disappears and the entry becomes interactive

### 8.6 HUD Research Progress Indicator

A persistent, non-occluding indicator in the HUD (top bar area, near wave timer):

- When research is active: small progress bar with node icon and percentage
- Tapping opens the full tech tree view
- When no research is active and Labs exist: "Idle" indicator to prompt the player

### 8.7 Recipe Gating in Build Menu

Production buildings with gated recipes show:

- Available recipes in the recipe selection/pinning UI
- Locked recipes are visible but grayed with "Requires: [Tech Node Name]"
- Helps the player understand what research enables for each building

---

## 9. Balance Framework

### 9.1 Research Duration by Tier

Research seconds scale with tier depth, reflecting increasing strategic commitment:

| Tier | Research Seconds | Ticks (at 1.0 speed) | Real Time (1 Lab, full power) |
|------|-----------------|---------------------|-------------------------------|
| 1 | 60 | 1,200 | 60 seconds |
| 2 | 80 | 1,600 | 80 seconds |
| 3 | 100 | 2,000 | 100 seconds |
| 4 | 120 | 2,400 | 120 seconds |

### 9.2 Node-Level Duration Table

| Node | Tier | Research Seconds | Item Cost Summary |
|------|------|-----------------|-------------------|
| `root` | 0 | 0 (auto) | Free |
| `logistics_1` | 1 | 60 | 20 plate_iron |
| `defense_1` | 1 | 60 | 40 ammo_light |
| `smelting_advanced` | 1 | 60 | 20 plate_copper |
| `conveyor_mk2` | 2 | 80 | 12 gear |
| `storage_bins` | 2 | 80 | 14 plate_steel |
| `heavy_ammo` | 2 | 80 | 25 ammo_heavy |
| `fortification` | 2 | 80 | 16 wall_kit |
| `steel_working` | 2 | 80 | 25 plate_steel |
| `electronics_1` | 2 | 80 | 20 circuit |
| `logistics_2` | 3 | 100 | 22 plate_steel |
| `turret_core_fabrication` | 3 | 100 | 8 turret_core |
| `power_cells` | 3 | 100 | 12 power_cell |
| `plasma_research` | 3 | 100 | 12 ammo_plasma |
| `mk2_turrets` | 4 | 120 | 12 turret_core |
| `explosive_payloads` | 4 | 120 | 35 ammo_heavy |
| `reactive_walls` | 4 | 120 | 30 wall_kit |
| `automated_repair` | 4 | 120 | 18 repair_kit |
| `plasma_turrets` | 4 | 120 | 25 ammo_plasma |
| `geology_survey_1` | 2 | 80 | 12 gear |
| `geology_survey_2` | 3 | 100 | 18 plate_steel |
| `geology_survey_3` | 4 | 120 | 14 circuit |

### 9.3 Path-to-Leaf Analysis

Total research time from root to each leaf node (1 Lab, full power):

| Leaf Node | Path | Total Research (s) | Total Nodes |
|-----------|------|-------------------|-------------|
| `mk2_turrets` | root > smelting_advanced > steel_working > turret_core_fabrication > mk2_turrets | 60 + 80 + 100 + 120 = **360s** | 4 |
| `plasma_turrets` | root > smelting_advanced > electronics_1 > power_cells + plasma_research > plasma_turrets | 60 + 80 + 100 + 100 + 120 = **460s** | 5 (sequential bottleneck: both prerequisites) |
| `explosive_payloads` | root > defense_1 > heavy_ammo > explosive_payloads | 60 + 80 + 120 = **260s** | 3 |
| `reactive_walls` | root > defense_1 > fortification > reactive_walls | 60 + 80 + 120 = **260s** | 3 |
| `automated_repair` | root > logistics_1 > conveyor_mk2 + storage_bins > logistics_2 > automated_repair | 60 + 80 + 80 + 100 + 120 = **440s** | 5 (bottleneck: both T2 prerequisites) |
| `geology_survey_3` | root > logistics_1 > geology_survey_1 > geology_survey_2 > geology_survey_3 | 60 + 80 + 100 + 120 = **360s** | 4 |

With 2 Labs (1.5x speed), all times reduce by ~33%. The longest path (plasma_turrets, 460s) becomes ~307s.

### 9.4 Pacing Against Wave Progression

Cross-referencing with the continuous threat model (grace period + inter-wave gaps). On Normal difficulty: 120s grace period, 90s base inter-wave gap compressing by 2s/wave:

| Wave | Approx Game Time | Expected Research Milestone |
|------|-----------------|---------------------------|
| Grace end | 120s | Lab not yet built. Player focuses on starter production. |
| 1-2 | 120-300s | Lab built during early play. First Tier 1 research started. |
| 3-4 | 300-470s | First Tier 1 node completing (Lab built ~180s + 60s research). Player has basic unlocks. |
| 5-7 | 470-700s | 1-2 Tier 2 nodes completing. Steel or electronics branch opening. |
| 8-10 | 700-900s | 2-3 Tier 2 nodes done. Gated buildings (gattling, storage) available. |
| 11-13 | 900-1100s | First Tier 3 node completing. Turret Mk2 or plasma ammo unlocking. |
| 14+ | 1100s+ | Tier 3/4 nodes unlocking. Advanced capability. |

**Key pacing constraint:** The player should NOT have gattling_tower or turret_mk2 before they face raiders (wave 3-4). With Lab build time (~30-60s) plus research time (60s Tier 1 + 80s Tier 2 = 140s minimum from research start), these are reliably mid-game unlocks (wave 5+), not early-game trivials.

### 9.5 Lab Economics

**Lab build cost analysis:**
- 4 plate_steel: requires steel smelting chain (2 plate_iron + 1 ore_coal per plate, 4s per batch). 4 plates = 16s of smelter time.
- 2 circuit: requires copper + coal chain (2 plate_copper + 1 ore_coal per circuit, 2s per batch). 2 circuits = 4s of assembler time.
- 2 gear: requires iron chain (2 plate_iron per gear, 1.5s per batch). 2 gears = 3s of assembler time.

**Total factory time to build a Lab:** approximately 20-30 seconds of dedicated production, depending on parallelism. This means a Lab is realistically buildable during build phase 2-3 (waves 2-3).

**Opportunity cost:** Building a Lab means NOT building:
- 1 turret mount (1 turret_core + 2 plate_steel) — direct defense
- ~1 smelter (4 plate_steel) — production capacity
- Several walls (1 wall_kit each) — base protection

This is the intended tension — the Lab competes directly with immediate-value alternatives.

### 9.6 Power Budget Impact

Adding a Lab:
- Lab draws 5 power
- 1 power plant (12) supports starter base (9) with headroom 3 — adding a Lab (5) exceeds capacity
- Player MUST build a 2nd power plant before or with the Lab
- 2 power plants (24 supply) support: starter base (9) + Lab (5) + expansion room (10)

### 9.7 Research Item Consumption Impact

**Example — `defense_1` costs 40 ammo_light:**
- 40 ammo_light = 10 batches of craft_ammo_light = 10 plate_iron consumed
- One ammo module produces 2 ammo_light/s, so 40 ammo = 20 seconds of production
- During a wave, 2 turret_mk1 turrets consume 4 ammo/s = 10 seconds to drain 40 ammo
- **Researching defense_1 costs the equivalent of 10 seconds of turret fire** — significant but survivable with stockpile management

---

## 10. Implementation Sequencing

### Phase 1: Data Layer
**What:** Extend `TechNodeDef` with `researchSeconds` and `TechEffectDef`. Add Lab to content definitions. Extend content validation.

| Task | Files |
|------|-------|
| Add `researchSeconds` field to `TechNodeDef` | `ContentTypes.swift` |
| Add `TechEffectDef` enum/struct for typed effects | `ContentTypes.swift` |
| Add Lab building definition | `buildings.json` (if exists), `ContentTypes.swift` |
| Update `tech_nodes.json` with `researchSeconds` per node | `tech_nodes.json` |
| Extend `ContentValidator` for research time, effect validity | `ContentValidator.swift` |

### Phase 2: Simulation Types
**What:** Add `TechState`, `ResearchProgress` to `SimulationTypes.swift`. Extend `WorldState`. Add `lab` to `StructureType`. Add new command payloads and events.

| Task | Files |
|------|-------|
| Define `TechState` and `ResearchProgress` structs | `SimulationTypes.swift` |
| Add `tech: TechState` to `WorldState` | `SimulationTypes.swift` |
| Add `case lab` to `StructureType` | `SimulationTypes.swift` |
| Add Lab footprint (2x2) | `SimulationTypes.swift` or `EntityStore.swift` |
| Add `startResearch`, `cancelResearch` to `CommandPayload` | `SimulationTypes.swift` |
| Add research events to `SimEvent` | `SimulationTypes.swift` |
| Update `WorldState.bootstrap()` with default `TechState` | `SimulationTypes.swift` |
| Add backward-compatible snapshot decoding | `SimulationTypes.swift` |

### Phase 3: TechSystem + CommandSystem Integration
**What:** Implement `TechSystem` with per-tick research progress. Extend `CommandSystem` with research commands and tech gating checks.

| Task | Files |
|------|-------|
| Implement `TechSystem` (progress accumulation, completion) | `Systems.swift` |
| Add `TechSystem` to system execution order (after Economy, before Wave) | `SimulationEngine.swift` |
| Handle `startResearch` in `CommandSystem` (validation, item consumption) | `Systems.swift` |
| Handle `cancelResearch` in `CommandSystem` (refund, clear) | `Systems.swift` |
| Add building placement tech gate checks | `Systems.swift` |
| Add recipe filtering by tech state | `Systems.swift` |
| Add upgrade gate checks | `Systems.swift` |

### Phase 4: Passive Bonuses
**What:** Implement query-time bonus application for all passive effects.

| Task | Files |
|------|-------|
| Power generation bonus (steel_working: +3) | `Systems.swift` (EconomySystem) |
| Smelter speed bonus (smelting_advanced: +15%) | `Systems.swift` (EconomySystem) |
| Turret HP bonus (defense_1: +25) | `EntityStore.swift` or health query |
| Wall HP bonus (fortification: +10%) | `EntityStore.swift` or health query |
| Conveyor power bonus (logistics_1: 0 draw) | `Systems.swift` (EconomySystem) |
| Turret range bonus (plasma_research: +1) | `Systems.swift` (CombatSystem) |
| Turret fire rate bonus (mk2_turrets: +10%) | `Systems.swift` (CombatSystem) |
| Storage capacity bonus (logistics_2: +12) | Building spec query |
| Ammo module buffer bonus (power_cells: +4) | Building spec query |
| Ammo output bonus (explosive_payloads: +1) | Recipe output query |
| Plasma damage bonus (plasma_turrets: +10) | `Systems.swift` (CombatSystem) |
| Inventory capacity bonus (storage_bins: +50) | `Systems.swift` (EconomySystem) |

### Phase 5: UI Integration
**What:** Migrate `TechTreeViewModel` to read-only projection. Add Lab building to build menu. Add gating indicators, research HUD, confirmation dialog.

| Task | Files |
|------|-------|
| Migrate `TechTreeViewModel` to read from `TechState` | `ProductionUI.swift` |
| Remove `productionPreset` static, load full tree from content | `ProductionUI.swift` |
| Add Lab to build menu | `ProductionUI.swift` |
| Research confirmation dialog | `ProductionUI.swift` |
| Build menu lock icons for gated buildings | `ProductionUI.swift` |
| Recipe gating indicators in recipe selection | `ProductionUI.swift` |
| HUD research progress indicator | `ProductionUI.swift` or `HUDViewModel` |
| Lab selection HUD (cancel research, speed display) | `ProductionUI.swift` |

### Phase 6: Balance Tuning
**What:** Playtest research pacing, adjust durations, costs, and passive bonus values.

| Task | Files |
|------|-------|
| Automated balance test: research timeline vs wave progression | `GameSimulationTests` |
| Golden replay tests with research commands | `GameSimulationTests` |
| Adjust `researchSeconds` per node based on playtest | `tech_nodes.json` |
| Validate passive bonus impact on economy throughput | `GameSimulationTests` |

---

## Appendix A: Extended TechNodeDef Schema

Current `tech_nodes.json` schema:

```json
{
    "id": "string",
    "costs": [{ "itemID": "string", "quantity": "int" }],
    "prerequisites": ["string"],
    "unlocks": ["string"]
}
```

Extended schema with research timing and effects:

```json
{
    "id": "string",
    "costs": [{ "itemID": "string", "quantity": "int" }],
    "prerequisites": ["string"],
    "unlocks": ["string"],
    "researchSeconds": "double",
    "effects": [
        {
            "type": "buildingGate",
            "structureType": "string"
        },
        {
            "type": "recipeGate",
            "recipeID": "string"
        },
        {
            "type": "upgradeGate",
            "upgradeID": "string"
        },
        {
            "type": "passiveBonus",
            "target": "string",
            "stat": "string",
            "value": "double",
            "mode": "add | multiply"
        },
        {
            "type": "mechanicUnlock",
            "mechanicID": "string"
        }
    ]
}
```

**Swift type:**

```swift
public struct TechNodeDef: Codable, Hashable, Sendable {
    public var id: String
    public var costs: [ItemStack]
    public var prerequisites: [String]
    public var unlocks: [String]
    public var researchSeconds: Double          // NEW
    public var effects: [TechEffectDef]         // NEW
}

public enum TechEffectDef: Codable, Hashable, Sendable {
    case buildingGate(structureType: String)
    case recipeGate(recipeID: String)
    case upgradeGate(upgradeID: String)
    case passiveBonus(target: String, stat: String, value: Double, mode: BonusMode)
    case mechanicUnlock(mechanicID: String)
}

public enum BonusMode: String, Codable, Hashable, Sendable {
    case add
    case multiply
}
```

---

## Appendix B: Implementation Priority Matrix

| Feature | Impact | Effort | Priority |
|---------|--------|--------|----------|
| `TechState` + `ResearchProgress` on `WorldState` | Critical | Low | **P0** |
| `startResearch` / `cancelResearch` commands | Critical | Low | **P0** |
| `TechSystem` (progress accumulation + completion) | Critical | Medium | **P0** |
| Lab `StructureType` + 2x2 footprint | Critical | Low | **P0** |
| Building placement tech gating | High | Low | **P0** |
| Recipe gating by tech state | High | Low | **P0** |
| Passive bonus: power generation (+3) | Medium | Low | **P1** |
| Passive bonus: smelter speed (+15%) | Medium | Low | **P1** |
| Passive bonus: turret HP, range, fire rate | Medium | Low | **P1** |
| Upgrade gating | Medium | Medium | **P1** |
| `TechTreeViewModel` migration to read-only | High | Medium | **P1** |
| Research confirmation dialog | Medium | Medium | **P1** |
| Build menu gating indicators | Medium | Low | **P1** |
| HUD research progress indicator | Medium | Low | **P2** |
| Mechanic unlocks (AoE, reflect, auto-repair) | Low | High | **P2** |
| Extended `tech_nodes.json` with effects | Medium | Medium | **P2** |
| Balance tuning + automated tests | Medium | High | **P2** |

---

## Appendix C: Files Requiring Modification

| File | Changes |
|------|---------|
| `Sources/GameSimulation/SimulationTypes.swift` | **Major**: Add `TechState`, `ResearchProgress`, `lab` StructureType case, `startResearch`/`cancelResearch` CommandPayload cases, research SimEvent cases. Extend `WorldState` with `tech` field. |
| `Sources/GameSimulation/Systems.swift` | **Major**: New `TechSystem` implementation. Extend `CommandSystem` with research command handling and tech gate checks. Extend `EconomySystem` for passive bonus queries (power, speed). Extend `CombatSystem` for turret stat bonuses (range, fire rate, damage). |
| `Sources/GameSimulation/SimulationEngine.swift` | **Minor**: Insert `TechSystem` into system execution array between Economy and Wave. |
| `Sources/GameSimulation/EntityStore.swift` | **Minor**: Lab footprint (2x2), Lab entity spawning. |
| `Sources/GameContent/ContentTypes.swift` | **Medium**: Extend `TechNodeDef` with `researchSeconds` and `TechEffectDef`. Add `BonusMode` enum. |
| `Sources/GameContent/ContentLoader.swift` | **Minor**: Load extended tech node fields. |
| `Sources/GameContent/ContentValidator.swift` | **Minor**: Validate `researchSeconds > 0` for non-root nodes, validate effect references (structureType, recipeID exist). |
| `Content/bootstrap/tech_nodes.json` | **Medium**: Add `researchSeconds` and `effects` fields to all 19 nodes. |
| `Sources/GameUI/ProductionUI.swift` | **Major**: Migrate `TechTreeViewModel` to read-only projection. Remove `productionPreset` static. Add Lab to build menu. Add gating indicators. Add research confirmation dialog. Add HUD research progress. |
| `Apps/macOS/Sources/FactoryDefensemacOSRootView.swift` | **Minor**: Wire updated `TechTreeViewModel` initialization. |
| `Apps/iOS/Sources/FactoryDefenseiOSRootView.swift` | **Minor**: Wire updated `TechTreeViewModel` initialization. |
| `Apps/iPadOS/Sources/FactoryDefenseiPadOSRootView.swift` | **Minor**: Wire updated `TechTreeViewModel` initialization. |
| `Tests/GameSimulationTests/` | **Medium**: New tests for TechSystem determinism, research start/cancel/complete, tech gating, passive bonuses. |
| `Tests/GameContentTests/` | **Minor**: Validate extended tech_nodes.json schema. |

---

## Changelog

- 2026-02-15: Initial draft — tech tree runtime design with Lab building, research flow, all 19 node effects, gating rules, simulation integration, and balance framework.
