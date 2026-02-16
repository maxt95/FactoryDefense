# Factory & Economy PRD

**Version:** 1.0-draft
**Parent:** `docs/GAME_PRD_LIVING.md`
**Status:** Forward-looking v1 design
**Last updated:** 2026-02-16

> **Core truth:** If any link in the production chain breaks, ammo starves, turrets go silent, and the base takes damage. The factory IS the weapon.

**Companion doc:** [`building_specifications.md`](building_specifications.md) — detailed per-building specs (ports, buffers, connections, processing speeds). That doc supersedes section 5 (Logistics & Transport) of this PRD with the conveyor-routed, per-building-buffer model.

---

## Table of Contents

1. [Core Gameplay Loop](#1-core-gameplay-loop)
2. [Resource System](#2-resource-system)
3. [Production Chain Architecture](#3-production-chain-architecture)
4. [Power Grid](#4-power-grid)
5. [Logistics & Transport](#5-logistics--transport)
6. [Building Placement & Costs](#6-building-placement--costs)
7. [Economy-Combat Coupling](#7-economy-combat-coupling)
8. [Balance Framework](#8-balance-framework)
- [Appendix A: Full Production Chain Graph](#appendix-a-full-production-chain-graph)
- [Appendix B: Implementation Priority Matrix](#appendix-b-implementation-priority-matrix)
- [Appendix C: Files Requiring Modification](#appendix-c-files-requiring-modification)

---

## Terminology

| Term | Definition |
|------|-----------|
| **Tick** | One simulation step at 20 Hz (50ms real-time) |
| **Per-second rate** | Per-tick value multiplied by 20 |
| **Throughput multiplier** | `efficiency x logisticsBoost` — the single scalar gating all production |
| **Recipe time** | Duration in seconds from `recipes.json`; translates to `ceil(seconds x 20)` ticks |
| **ItemID** | String key matching `items.json` entries (e.g., `"ore_iron"`, `"plate_steel"`) |
| **Build phase** | Period between waves (default 400 ticks / 20 seconds) |
| **Wave phase** | Active enemy attack period (default 160 ticks / 8 seconds) |

System execution order per tick: Command > Economy > Wave > EnemyMovement > Combat > Projectile.

---

## 1. Core Gameplay Loop

### 1.1 Design Intent

The player is not directly clicking to kill enemies. The player builds and optimizes a production system whose output (ammo, repairs, power) determines whether turrets can fire and walls hold. This is the fundamental differentiator from tower defense games where towers are self-sufficient. If the factory can't produce it, defenses can't use it.

### 1.2 Minute-to-Minute Loop

**Build Phase** (between waves, default 20 seconds):
- Factory runs at full speed. Inventory accumulates.
- Player places structures, adjusts production priorities, expands resource coverage.
- Key decision each build phase: expand production breadth (more miners, new ore types) vs. deepen existing chains (more smelters) vs. expand defense (turrets, walls).

**Wave Phase** (during active attack, default 8 seconds):
- Factory still runs, but now ammo is being consumed by turrets. The player watches stockpiles drain.
- Core tension: can the factory produce ammo as fast as turrets consume it?
- Player can still build during waves but should feel urgency.

**The Tension Triangle:**

```
         Production Expansion
              /        \
             /          \
    Defense Expansion -- Resource Coverage
```

More turrets demand more ammo, which demands more production buildings, which demand more power, which demand more power plants, which compete for grid space with turrets and walls. Every expansion decision creates downstream pressure on another axis.

### 1.3 Player-Facing Behavior

HUD surfaces at all times:
- **Ammo stock** — per ammo type, with depletion rate during waves
- **Power headroom** — available vs demand, efficiency percentage
- **Wave timer** — countdown to next wave
- **Currency** — current bank
- **Base integrity** — health bar

Warning banners (non-occluding):
- `Low Ammo` — < 10 ammo of any type a turret needs during wave phase
- `Base Critical` — integrity <= 20
- `Raid Imminent` — raid cooldown about to expire during wave phase
- `Power Shortage` — efficiency < 0.8

Build menu organized by category: Defense, Production, Logistics, Utility.

### 1.4 Simulation Rules

- Fixed 20 Hz tick loop. Six systems run sequentially per tick.
- Economy runs every tick regardless of wave state. Waves add enemies; combat consumes ammo from the same inventory the economy fills.
- Currency earns +1 per tick during active waves.
- Milestone rewards: `waveIndex x 10` currency every 5 waves.
- Game ends when base integrity reaches 0, or player voluntarily extracts.

### 1.5 Implementation Status

| Aspect | Status |
|--------|--------|
| Phase timing via ThreatState | Exists |
| Economy and Combat in same tick loop | Exists |
| Ammo truth (turrets check inventory) | Exists |
| Build cost enforcement | Exists — simulation-enforced (Milestone 0) |
| Build/wave phase UI distinction | Gap — no visual mode switch |
| Warning banner system | Partial — `HUDViewModel.build()` generates `baseCritical`, `lowAmmo`, `raidImminent` warnings from `WorldState`; gap: warnings not rendered in gameplay view, `powerShortage` warning type missing |

### 1.6 Open Questions

- Should building be restricted or more expensive during wave phase?
- Should there be a "planning pause" before wave 1 where the tick clock is frozen?
- What is the exact extraction reward formula for meta-progression?

---

## 2. Resource System

### 2.1 Design Intent

Resources create a multi-layered dependency chain where each tier of processing requires outputs from the previous tier. This creates natural bottlenecks the player must diagnose and solve. The player's core skill is reading these bottlenecks and knowing where to invest next.

### 2.2 Resource Taxonomy

**Tier 0 — Raw Ores** (extracted by miners from ore patches)

| ItemID | Name | Source | Role |
|--------|------|--------|------|
| `ore_iron` | Iron Ore | Iron ore patches | Foundation of most production chains |
| `ore_copper` | Copper Ore | Copper ore patches | Electronics, power cells |
| `ore_coal` | Coal | Coal deposits | Steel alloying, circuit etching |

**Tier 1 — Plates** (produced by smelters)

| ItemID | Name | Input | Output | Role |
|--------|------|-------|--------|------|
| `plate_iron` | Iron Plate | 2 ore_iron | 1 plate | Light ammo, gears, steel |
| `plate_copper` | Copper Plate | 2 ore_copper | 1 plate | Circuits, power cells |
| `plate_steel` | Steel Plate | 2 plate_iron + 1 ore_coal | 1 plate | Heavy ammo, walls, turret cores |

**Tier 2 — Components** (produced by assemblers)

| ItemID | Name | Input | Output | Role |
|--------|------|-------|--------|------|
| `gear` | Gear | 2 plate_iron | 1 gear | Wall kits, turret cores, structure build costs |
| `circuit` | Circuit | 2 plate_copper + 1 ore_coal | 1 circuit | Power cells, turret cores, ammo modules |
| `power_cell` | Power Cell | 1 plate_copper + 1 circuit | 1 cell | Plasma ammo production |

**Tier 3 — Consumables** (produced by ammo modules and assemblers)

| ItemID | Name | Input | Output | Consumer |
|--------|------|-------|--------|----------|
| `ammo_light` | Light Ammo | 1 plate_iron | 4 ammo | turret_mk1, gattling_tower |
| `ammo_heavy` | Heavy Ammo | 1 plate_steel + 2 ammo_light | 3 ammo | turret_mk2 |
| `ammo_plasma` | Plasma Ammo | 1 power_cell + 1 circuit | 2 ammo | plasma_sentinel |
| `wall_kit` | Wall Kit | 1 plate_steel + 1 gear | 1 kit | Wall placement cost |
| `turret_core` | Turret Core | 1 plate_steel + 1 circuit + 1 gear | 1 core | Turret mount placement cost |
| `repair_kit` | Repair Kit | 1 plate_steel + 1 circuit | 1 kit | Structure repair |

### 2.3 Resource Node Placement

The map has ore patches at fixed positions defined in level data. Miners must be placed on or adjacent to ore patches to produce.

**Rules:**
- Each ore patch has a type (iron, copper, coal) and a richness value (total extractable units).
- A miner placed on/adjacent to an ore patch extracts at its base rate, modified by throughput multiplier.
- Multiple miners can operate on the same patch (shared depletion, no diminishing returns — keeps it simple).
- Ore patches are visible on the map before placement, displayed as resource node entities.
- A miner not adjacent to any ore patch produces nothing.

**Ore patch richness values (recommended):**

| Type | Richness | Time to deplete (1 miner, 1.0 throughput) |
|------|----------|-------------------------------------------|
| Iron | 2000 | ~100 seconds (2000 ticks) |
| Copper | 1500 | ~94 seconds (1875 ticks at 0.8/tick) |
| Coal | 1200 | ~100 seconds (2000 ticks at 0.6/tick) |

At these values, a single ore patch lasts through roughly waves 1-5 before the player needs to expand to new patches. This forces map exploration and expansion without being punishing in the early game.

**Starter map layout (recommended):**
- 2 iron patches near base (accessible immediately)
- 1 copper patch near base
- 1 coal patch near base
- 2-3 additional patches of each type further from base (expansion targets)
- Distant patches are closer to spawn edges (risk/reward)

### 2.4 Implementation Status

| Aspect | Status |
|--------|--------|
| 15 items in `items.json` | Exists |
| 12 recipes in `recipes.json` | Exists — now consumed by simulation (Milestone 0) |
| `gear` production | Exists (Milestone 0) |
| `ammo_plasma` production | Exists (Milestone 0) |
| `wall_kit`, `turret_core`, `repair_kit` production | Exists (Milestone 0) |
| Miners produce from ore patches | Gap — miners produce from nothing |
| ResourceNode entity type | Gap — no concept of ore patches |
| Ore depletion tracking | Gap |

---

## 3. Production Chain Architecture

### 3.1 Design Intent

Production chains should be legible (player can trace input > output > consumer), rate-limited (throughput creates natural tension), and breakable (any interruption cascades through the entire system).

### 3.2 Full Dependency Graph

```
ore_iron ──> plate_iron ──┬──> ammo_light ────────────> turret_mk1, gattling_tower
                          ├──> gear ──────────┬────────> wall_kit (+ plate_steel)
                          │                   ├────────> turret_core (+ plate_steel + circuit)
                          └──> plate_steel ───┼────────> ammo_heavy (+ ammo_light)
                               (+ ore_coal)   ├────────> wall_kit (+ gear)
                                              ├────────> repair_kit (+ circuit)
                                              └────────> turret_core (+ circuit + gear)

ore_copper ──> plate_copper ──┬──> circuit ───┬────────> turret_core
                              │   (+ ore_coal)├────────> power_cell (+ plate_copper)
                              │               ├────────> ammo_plasma (+ power_cell)
                              │               └────────> repair_kit (+ plate_steel)
                              └──> power_cell ────────> ammo_plasma (+ circuit)
                                  (+ circuit)

ore_coal ──> consumed directly by:
             - smelt_steel: plate_iron + coal -> plate_steel
             - etch_circuit: plate_copper + coal -> circuit
```

**Critical path for each ammo type:**
- **Light ammo:** ore_iron > plate_iron > ammo_light (2 processing steps)
- **Heavy ammo:** ore_iron > plate_iron > plate_steel (+ coal) > ammo_heavy (+ ammo_light) (3 processing steps, 2 ore types)
- **Plasma ammo:** ore_copper > plate_copper > circuit (+ coal) > power_cell (+ plate_copper) > ammo_plasma (+ circuit) (4 processing steps, 2 ore types)

Longer chains = higher tier ammo = more structures required = more power demanded = harder to sustain.

### 3.3 Recipe Timing

**Design: Hybrid accumulated production.** Each structure accumulates fractional progress per tick based on throughput multiplier. When accumulated progress reaches the recipe's craft time, a batch completes. This preserves the current EconomySystem's per-tick architecture while adding a meaningful time dimension.

**How it works:**
1. Each producing structure has a `craftProgress: Double` field (initialized to 0).
2. Each tick, progress increases by `throughputMultiplier / (recipeSeconds x 20)`.
3. When `craftProgress >= 1.0`, one batch completes: inputs are consumed, outputs are produced, progress resets to `craftProgress - 1.0` (carry remainder).
4. If inputs are unavailable when a batch would complete, progress is paused (capped at 1.0) until inputs arrive.

**Recipe times from `recipes.json`:**

| Recipe ID | Seconds | Ticks (at 1.0 throughput) | Structure |
|-----------|---------|--------------------------|-----------|
| `smelt_iron` | 2.0 | 40 | Smelter |
| `smelt_copper` | 2.0 | 40 | Smelter |
| `smelt_steel` | 4.0 | 80 | Smelter |
| `forge_gear` | 1.5 | 30 | Assembler |
| `etch_circuit` | 2.0 | 40 | Assembler |
| `assemble_power_cell` | 2.5 | 50 | Assembler |
| `craft_ammo_light` | 2.0 | 40 | Ammo Module |
| `craft_ammo_heavy` | 2.6 | 52 | Ammo Module |
| `craft_ammo_plasma` | 3.0 | 60 | Ammo Module |
| `craft_wall_kit` | 1.2 | 24 | Assembler |
| `craft_turret_core` | 2.5 | 50 | Assembler |
| `craft_repair_kit` | 2.0 | 40 | Assembler |

**Effective output rates (per structure, at 1.0 throughput):**

| Recipe | Output/second | Output per 20s build phase |
|--------|--------------|---------------------------|
| smelt_iron | 0.5 plate_iron/s | 10 plates |
| smelt_copper | 0.5 plate_copper/s | 10 plates |
| smelt_steel | 0.25 plate_steel/s | 5 plates |
| forge_gear | 0.67 gear/s | 13 gears |
| etch_circuit | 0.5 circuit/s | 10 circuits |
| craft_ammo_light | 2.0 ammo_light/s (4 per batch) | 40 ammo |
| craft_ammo_heavy | 1.15 ammo_heavy/s (3 per batch) | 23 ammo |
| craft_ammo_plasma | 0.67 ammo_plasma/s (2 per batch) | 13 ammo |

### 3.4 Structure-Recipe Binding

Each structure type can run a defined set of recipes. A structure auto-selects from its allowed recipes based on available inputs, preferring the first recipe in priority order that has sufficient inputs.

| Structure Type | Allowed Recipes (priority order) | Notes |
|---------------|--------------------------------|-------|
| Miner | N/A — special extraction logic | Produces raw ores from adjacent patches |
| Smelter | smelt_steel > smelt_iron > smelt_copper | Steel prioritized (highest tier) |
| Assembler | craft_turret_core > craft_wall_kit > craft_repair_kit > assemble_power_cell > etch_circuit > forge_gear | Utility items prioritized over components |
| Ammo Module | craft_ammo_plasma > craft_ammo_heavy > craft_ammo_light | Highest tier ammo prioritized |

Players can override auto-selection by pinning a recipe to a structure (tap structure > select recipe). Pinned structures only produce the pinned recipe.

### 3.5 Implementation Status

| Aspect | Status |
|--------|--------|
| Recipe definitions in `recipes.json` | Exists (authoritative source for simulation) |
| Recipe-driven EconomySystem | Exists — consumes JSON definitions (Milestone 0) |
| All production chains (gear, wall_kit, turret_core, ammo_plasma, repair_kit) | Exists (Milestone 0) |
| Per-structure recipe timing/progress | Partial — implemented for smelter/assembler/ammo module; miner extraction timing remains |
| Structure-recipe binding with priority | Partial — auto-selection exists; recipe pinning not yet implemented |
| Recipe pinning UI | Gap |

### 3.6 Open Questions

- Should structures auto-select recipes or require manual assignment?
- Recommendation: auto-select with manual override (recipe pinning). This keeps the game accessible while rewarding optimization.
- Should there be recipe queuing (produce 10 of X then switch to Y)?
- Recommendation: not for v1. Auto-select based on available inputs is sufficient.

---

## 4. Power Grid

### 4.1 Design Intent

Power is the universal constraint. A power shortage does not affect one chain — it affects everything simultaneously. It is the most catastrophic failure mode because it cascades across the entire factory.

### 4.2 Power Generation and Consumption

| Structure | Power | Notes |
|-----------|-------|-------|
| Power Plant | -12 (generates) | One plant supports a starter base |
| Miner | +2 (consumes) | Low draw, basic extraction |
| Smelter | +3 (consumes) | Medium draw, thermal processing |
| Assembler | +3 (consumes) | Medium draw, precision crafting |
| Ammo Module | +4 (consumes) | Highest draw, ammunition fabrication |
| Conveyor | +1 (consumes) | Minimal, motors only |
| Storage | 0 | Passive logistics hub (aligned with building_specifications.md) |
| Wall | 0 | Passive defense |
| Turret Mount | 0 | Mechanical, fires with ammo only |

**One power plant (12 supply) supports:**
- Starter base: 1 miner (2) + 1 smelter (3) + 1 ammo module (4) = 9 demand, headroom 3
- Or: 4 miners (8) + 1 smelter (3) = 11 demand
- Or: 2 smelters (6) + 2 ammo modules (8) = 14 demand (requires 2nd plant)

### 4.3 Efficiency (Brownout) Mechanics

```
efficiency = min(1.0, powerAvailable / powerDemand)
```

At efficiency < 1.0, ALL production structures run slower:
- Recipe progress per tick is multiplied by `efficiency`
- A smelter that normally completes in 40 ticks takes 80 ticks at 0.5 efficiency
- At 0.0 efficiency (total blackout), no production occurs — miners stop, smelters stop, ammo modules stop
- Turrets still fire (mechanical), but no new ammo is produced

**Visual feedback:**
- Structures at efficiency < 1.0 show a yellow power indicator
- Structures at 0 efficiency show a red power indicator
- HUD power bar changes color: green (>80%), yellow (50-80%), red (<50%)

### 4.4 Power Priority

**v1 design: uniform brownout.** All structures scale by the same efficiency factor. The player's lever is to build more power plants.

This is simple, already works in the current implementation, and creates a clear "build more power" signal. Player-configurable priority tiers (high/medium/low) would be a strong v1.1 feature if playtesting shows players want more control over which chains get power during shortages.

### 4.5 Implementation Status

| Aspect | Status |
|--------|--------|
| Power generation/consumption model | Exists |
| Efficiency calculation | Exists |
| Throughput multiplier applies efficiency | Exists |
| Per-structure power status visualization | Gap |
| HUD power bar | Gap — `powerHeadroom` exists in telemetry but no visual |

### 4.6 Open Questions

- Should power plants require fuel (coal or power_cells)?
  - Recommendation: no for v1. Adds another bottleneck that may overwhelm new players. Consider as a hard-mode modifier.
- Should there be power grid connectivity (structures must be physically connected to a power plant)?
  - Recommendation: no for v1. Zone-based logistics already adds spatial requirements. Grid connectivity would compound complexity.
- Should turrets consume power to fire?
  - Recommendation: no. Ammo consumption is already the binding constraint. Adding power consumption to turrets would make power shortage double-punish the player (less ammo production AND turrets can't fire).

---

## 5. Logistics & Transport

> **Superseded.** This section's zone-based proximity model has been replaced by the conveyor-routed, per-building-buffer model defined in [`building_specifications.md`](building_specifications.md). That document is the canonical logistics reference for v1.

**Key changes from the original zone-based design:**
- Items physically move on directed conveyor tiles instead of using proximity-radius throughput boosts.
- Each building has local input/output buffers with finite capacity instead of drawing from a global inventory.
- Backpressure propagates naturally through the conveyor network when downstream buffers fill.
- Splitters and mergers provide explicit routing control.
- Storage acts as a shared-pool logistics hub with 4 ports (2 in, 2 out) rather than a radius-based capacity booster.
- The "global inventory" becomes a computed aggregate for HUD display and turret ammo pool fallback.
- Storage power draw is 0 (not +1 as previously specified in this section).

**What remains valid from this section's design intent:**
- Logistics should create meaningful placement decisions.
- Bottleneck feedback (running, input starved, output blocked, underpowered, no ore patch) is carried forward into the building specifications.
- Storage capacity limits still apply — but per-building (48 internal capacity) rather than global.

See `building_specifications.md` sections 1-6 for the complete replacement design.

---

## 6. Building Placement & Costs

### 6.1 Design Intent

Every structure placed is resources committed, creating opportunity cost decisions. The player must earn the right to expand by investing factory output. This transforms the game from a planning exercise into an economic one.

### 6.2 Build Costs

| Structure | Cost | Category |
|-----------|------|----------|
| Power Plant | 2 circuit + 4 plate_copper | Utility |
| Miner | 6 plate_iron + 3 gear | Production |
| Smelter | 4 plate_steel | Production |
| Assembler | 4 plate_iron + 2 circuit | Production |
| Ammo Module | 2 circuit + 2 plate_steel | Production |
| Conveyor | 1 plate_iron | Logistics |
| Storage | 3 plate_steel + 2 gear | Logistics |
| Wall | 1 wall_kit | Defense |
| Turret Mount | 1 turret_core + 2 plate_steel | Defense |

**Bootstrap exception:** The starter structures (1 power plant, 1 miner, 1 smelter, 1 ammo module, 2 turret mounts) are placed for free at game start. All subsequent placements require full cost payment.

### 6.3 Placement Validation

When a player issues a `placeStructure` command, the simulation must validate:

1. **Bounds check** — target cell is within board dimensions
2. **Cell availability** — target cell is not blocked, restricted, or already occupied
3. **Cost check** — player inventory contains all required items
4. **Type-specific rules:**
   - Miners: must be on or adjacent to an ore patch (Manhattan distance <= 1)
   - All structures except conveyors: block enemy pathfinding
5. **Cost deduction** — consume required items from inventory on successful placement
6. **Failure feedback** — if validation fails, emit an event specifying the reason (insufficient resources, invalid position, etc.)

### 6.4 Removal & Refund

Players can demolish structures they've placed:

- **New command:** `removeStructure(entityID)` added to `CommandPayload`
- **Refund:** 50% of original build cost (rounded down per item)
- **Deconstruction time:** 20 ticks (1 second) — structure becomes non-functional immediately, entity removed after delay
- **No refund on starter structures** — the 5 bootstrap structures cannot be demolished (or return 0 if demolished)
- **During waves:** demolishing is allowed but risky (turrets/walls gone immediately)

### 6.5 Structure Upgrades

Certain tech tree unlocks enable in-place structure upgrades:

| Structure | Upgrade | Prerequisite Tech | Additional Cost | Effect |
|-----------|---------|-------------------|-----------------|--------|
| Miner | Miner Mk2 | `conveyor_mk2` | 4 gear + 2 circuit | 1.5x extraction rate |
| Smelter | Smelter Mk2 | `smelting_advanced` | 3 plate_steel + 2 gear | 1.3x production speed |
| Turret Mount | Turret Mk2 | `mk2_turrets` | 2 turret_core | Uses `turret_mk2` stats |
| Wall | Reinforced Wall | `reactive_walls` | 2 wall_kit | 2x health (300) |

Upgrades are in-place — no demolish-rebuild cycle needed. The upgrade command consumes resources and modifies the entity's properties.

### 6.6 Implementation Status

| Aspect | Status |
|--------|--------|
| `CommandSystem.placeStructure` | Exists — simulation-enforced cost check (Milestone 0) |
| Build costs in `BuildMenuViewModel` | Exists (UI displays costs; simulation enforces them) |
| Placement validation (bounds, occupancy, path) | Exists — `PlacementValidator` checks bounds, restricted zones, occupancy, and critical path blocking |
| Cost deduction on placement | Exists — `CommandSystem` consumes inventory on placement (Milestone 0) |
| Ore patch adjacency check for miners | Gap — miners can be placed anywhere |
| Assembler in build menu | Gap — no `BuildMenuEntry` for assembler in `productionPreset` |
| `removeStructure` command | Gap — does not exist in `CommandPayload` |
| Refund logic | Gap |
| Structure upgrade system | Gap |

---

## 7. Economy-Combat Coupling

### 7.1 Design Intent

This is the soul of the game. The factory-defense coupling must be tight enough that the player FEELS the factory's output constraining combat effectiveness in real time. When ammo runs out mid-wave, the player should immediately understand "I need more ammo modules" or "I need more smelters feeding the ammo modules."

### 7.2 The Ammo Truth

**Core rule:** A turret can only fire if the global inventory contains at least 1 unit of its required ammo type. If inventory is empty, the turret is silent.

This is correctly enforced in the current implementation:
```
CombatSystem checks economy.consume(itemID: ammoType, quantity: 1)
  success -> fire projectile
  failure -> dry fire event (.notEnoughAmmo), no damage dealt
```

The `notEnoughAmmo` event must be surfaced prominently in the HUD — this is the primary signal that the factory needs attention.

### 7.3 Turret Type System

Four turret types with distinct combat characteristics:

| Turret | AmmoType | Fire Rate (shots/s) | Ticks Between Shots | Range | Damage per Shot |
|--------|----------|--------------------|--------------------|-------|----------------|
| turret_mk1 | ammo_light | 2.0 | 10 | 8 | 12 |
| turret_mk2 | ammo_heavy | 1.4 | 14 | 10 | 25 |
| gattling_tower | ammo_light | 4.2 | 5 | 6.5 | 8 |
| plasma_sentinel | ammo_plasma | 0.9 | 22 | 11 | 45 |

**AmmoType to ItemID mapping:**

| AmmoType | ItemID | Production Chain Depth |
|----------|--------|----------------------|
| lightBallistic | `ammo_light` | 2 steps (ore > plate > ammo) |
| heavyBallistic | `ammo_heavy` | 3 steps (ore > plate > steel > ammo, also consumes light ammo) |
| plasma | `ammo_plasma` | 4 steps (ore > plate > circuit > power_cell > ammo) |

**Per-turret state:** Each turret entity tracks:
- `turretDefID`: which turret type definition to use
- `lastFireTick`: tick of last shot (for fire rate limiting)

**Combat system per-turret logic:**
1. Look up turret's definition (ammoType, fireRate, range, damage)
2. Check if `tick - lastFireTick >= ticksBetweenShots`
3. Find nearest enemy within range (Manhattan distance)
4. Attempt `economy.consume(itemID: ammoType, quantity: 1)`
5. On success: spawn projectile with turret's damage value, update `lastFireTick`
6. On failure: emit `notEnoughAmmo` event

### 7.4 Ammo Consumption Analysis

**Ammo drain rates per turret type (per second):**

| Turret | Ammo consumed/sec | Production needed |
|--------|-------------------|-------------------|
| turret_mk1 | 2.0 ammo_light/s | 1 ammo module at 1.0 throughput (produces 2.0/s) |
| gattling_tower | 4.2 ammo_light/s | ~2.1 ammo modules |
| turret_mk2 | 1.4 ammo_heavy/s | ~1.2 ammo modules (heavy recipe) |
| plasma_sentinel | 0.9 ammo_plasma/s | ~1.35 ammo modules (plasma recipe) |

**Key sustainability ratios:**

| Turret Count | Ammo Modules Needed (light) | Smelters Needed | Miners Needed | Power Plants |
|-------------|---------------------------|-----------------|---------------|-------------|
| 1 turret_mk1 | 1 | 1 | 1 | 1 |
| 2 turret_mk1 | 2 | 1-2 | 2 | 1-2 |
| 1 gattling | 2 | 1-2 | 2 | 2 |
| 1 turret_mk2 | 1 (heavy) | 2 (steel chain) | 2 | 2 |
| 1 plasma | 1 (plasma) | 2 + 1 assembler | 2 (iron + copper) | 2-3 |

### 7.5 Power-Production-Combat Cascade

The full failure cascade:

```
Power plant destroyed/insufficient
  -> efficiency drops (e.g., 0.5)
    -> smelters produce plates at half speed
      -> ammo modules receive fewer plates
        -> ammo production halved
          -> turrets run dry mid-wave
            -> enemies reach base/structures
              -> more structures damaged/destroyed
                -> production further reduced
                  -> deeper cascade (death spiral)
```

This cascade is what makes the game feel tense. The player must maintain redundancy in power and production to avoid entering a death spiral. Recovery from a cascade is possible but requires immediate attention (building emergency power plants, prioritizing ammo production).

### 7.6 Structure Targeting by Enemies

To make the cascade real, certain enemy types should target structures:

| Enemy | Targeting Behavior |
|-------|-------------------|
| swarmling | Always targets base (shortest path) |
| drone_scout | Always targets base (shortest path) |
| raider | 70% base, 30% nearest structure within 4 cells of path |
| breacher | Targets nearest wall or structure blocking its path; switches to base if path is clear |
| artillery_bug | Targets highest-value structure within range 6 (power plant > ammo module > smelter > assembler > miner) |
| overseer | Targets base; buffs nearby enemies (separate combat PRD topic) |

**Structure health values:**

| Structure | Health | Rationale |
|-----------|--------|-----------|
| Wall | 150 | Primary defense, absorbs hits |
| Turret Mount | 100 | Standard, protected behind walls |
| Power Plant | 80 | High-value target, somewhat fragile |
| Smelter | 80 | Production critical, medium health |
| Assembler | 80 | Production support |
| Miner | 60 | Expendable, replaceable |
| Ammo Module | 100 | Ammo critical, needs to survive |
| Storage | 60 | Utility, not critical |
| Conveyor | 30 | Cheap, easily replaced |

When a structure is destroyed:
- It is removed from the entity store
- Its power demand is removed
- Its production contribution stops
- Any in-progress crafting is lost
- Enemies that were targeting it re-evaluate targets next tick

### 7.7 Implementation Status

| Aspect | Status |
|--------|--------|
| Ammo truth enforcement | Exists |
| `notEnoughAmmo` event | Exists |
| Currency reward on enemy kill | Exists |
| Per-turret type combat (ammo type, range, fire rate, damage) | Exists (Milestone 0) |
| Fire rate tracking per turret | Exists (Milestone 0) |
| `ammo_heavy` / `ammo_plasma` consumption | Exists (Milestone 0) |
| Turret type per entity (`turretDefID`) | Exists (Milestone 0) |
| Structure targeting by enemies | Gap — enemies only path to base |
| Structure health differentiation | Gap — all structures have health=100 but enemies never attack them |

---

## 8. Balance Framework

### 8.1 Design Intent

The economy must produce a tight experience where the player is ALMOST overwhelmed but can succeed with good optimization. The margin between success and failure should shrink as waves progress. Early waves are forgiving (learn the systems). Mid waves are challenging (optimize or die). Late waves are a knife edge (every efficiency gain matters).

### 8.2 Bootstrap Analysis

**Starting state** (from `WorldState.bootstrap()`):
- 1 power plant (12 power), 1 miner (2), 1 smelter (3), 1 ammo module (4), 2 turret mounts (0 each)
- Power: 12 supply, 9 demand. Efficiency = 1.0, headroom = 3
- Starting inventory: 10 ore_iron, 80 ammo_light
- Time until first wave: 400 ticks = 20 seconds

**Pre-wave 1 production — with proposed recipe timing (target design):**
- Miner: 20 ore_iron produced (1 ore/s over 20s)
- Smelter: 10 plate_iron produced (from 20 ore_iron, 2:1 ratio, 2s per batch = 10 batches)
- Ammo module: 40 ammo_light produced (from 10 plate_iron, 4:1 output, 2s per batch)
- Plus starting 10 ore_iron > 5 more plates > 20 more ammo_light

**Total ammo at wave 1 start (proposed timing): ~140 ammo_light** (80 starting + ~60 produced)

**Current code behavior (instant-per-tick):** The current `EconomySystem` produces 1 ore_iron per tick per miner, smelts every tick ore is available (2:1 ratio), and converts plates to ammo instantly (1 plate > 4 ammo). With 1 miner producing 1 ore/tick and smelting consuming 2 ore/tick, the smelter alternates between running and waiting for ore accumulation. Over 400 ticks, the current code produces significantly more ammo than the proposed timing model — roughly **~800+ ammo_light** on top of the 80 starting. This overshoot is expected to shrink dramatically once recipe timing is implemented (P1 priority).

### 8.3 Early Game (Waves 1-3)

**Wave composition (from `waves.json`):**

| Wave | Enemies | Total HP | Shots to Kill (at 12 dmg) |
|------|---------|----------|--------------------------|
| 1 | 6 swarmlings (10hp) + 2 scouts (20hp) | 100 | ~12 shots |
| 2 | 8 swarmlings + 4 scouts | 160 | ~18 shots |
| 3 | 6 scouts + 1 raider (45hp) | 165 | ~16 shots |

**Ammo budget (proposed timing):** ~140 ammo available at wave 1 (80 starting + ~60 produced). 12 shots needed per turret, 2 turrets = ~24 shots. Comfortable surplus of ~116. This is intentional — early waves teach the player the production system without pressure. The generous starting ammo (80) provides a safety net while the player learns the production chain.

**Player goals in early game:**
- Understand the production chain (miner > smelter > ammo module > turret)
- Build 1-2 additional production structures
- Place walls to channel enemies
- Accumulate resources for mid-game expansion

**Recommended structure count by wave 3:**
- 1-2 miners, 1 smelter, 1 ammo module, 2-3 turrets, 1 power plant, 2-4 walls

### 8.4 Mid Game (Waves 4-8)

**Wave composition escalation:**

| Wave | Key Threats | Total HP (approx) | Challenge |
|------|------------|-------------------|-----------|
| 4 | 6 scouts + 2 raiders | ~200 | Raiders have 45+ hp, require multiple hits |
| 5 | 10 swarmlings + 2 raiders + 1 breacher (70hp) | ~230 | First breacher — tests wall integrity |
| 6 | 8 scouts + 2 raiders + 1 breacher | ~290 | Sustained pressure |
| 7 | 12 swarmlings + 3 raiders + 1 breacher + 1 artillery (90hp) | ~395 | First artillery — ranged structure damage |
| 8 | 10 scouts + 3 raiders + 2 breachers + 1 artillery + 1 overseer (140hp) | ~625 | Boss wave — all enemy types present |

**Mid-game production demands:**
- 2-3 turrets active = 4-6 ammo_light/s consumption
- Steel chain online for heavy ammo (need assembler for circuits, smelter for steel)
- ~2 ammo modules minimum
- 2 power plants (24 supply for ~18-22 demand)

**Recommended structure count by wave 8:**
- 3-4 miners, 2-3 smelters, 1 assembler, 2 ammo modules, 2-3 turrets, 2 power plants, 4-8 conveyors, 1-2 storages, 6-10 walls

### 8.5 Late Game (Waves 9+)

Beyond wave 8, waves are procedurally generated with escalating spawn budgets:

**Proposed procedural generation formula:**
```
spawnBudget = 30 + (waveIndex x 8) + (waveIndex / 5) x 15  (milestone spike)
```

| Wave | Budget | Typical Composition |
|------|--------|-------------------|
| 9 | 102 | Mixed scouts + raiders + breachers |
| 10 | 125 (milestone) | Heavy: multiple breachers + artillery + overseer |
| 12 | 126 | Sustained mixed composition |
| 15 | 175 (milestone) | Massive: every enemy type, multiple overseers |
| 20 | 235 (milestone) | Overwhelming: tests maximum factory output |

**Late-game production demands:**
- Plasma ammo chain online (full copper > circuit > power_cell > ammo_plasma path)
- 4-6 turrets of mixed types
- 3-4 power plants
- Full logistics network for throughput boost
- Storage capacity management critical (prevent production halts from full inventory)

**Recommended structure count by wave 15:**
- 5-6 miners, 4-5 smelters, 2-3 assemblers, 3-4 ammo modules, 4-6 turrets (mixed types), 3-4 power plants, 10-15 conveyors, 3-5 storages, 10-20 walls

### 8.6 Key Balance Ratios

| Metric | Early (W1-3) | Mid (W4-8) | Late (W9+) |
|--------|-------------|-----------|------------|
| Miners | 1-2 | 3-4 | 5-6 |
| Smelters | 1 | 2-3 | 4-5 |
| Assemblers | 0 | 1 | 2-3 |
| Ammo Modules | 1 | 2 | 3-4 |
| Power Plants | 1 | 2 | 3-4 |
| Turrets | 2 | 2-3 | 4-6 |
| Conveyors | 0-2 | 4-8 | 10-15 |
| Storages | 0 | 1-2 | 3-5 |
| Walls | 2-4 | 6-10 | 10-20 |
| Ammo surplus per wave | 30+ (comfortable) | 10-20 (tight) | 0-10 (knife edge) |

**The "golden ratio":** For every turret the player adds, they need approximately:
- 1 ammo module (light) or 1.5 (heavy/plasma)
- 0.5-1 additional smelter
- 0.5-1 additional miner
- 0.25 additional power plant

### 8.7 Implementation Status

| Aspect | Status |
|--------|--------|
| Wave composition in `waves.json` | Exists (waves 1-8 well-defined) |
| Wave spawning in WaveSystem | Exists — but uses formula, ignores `waves.json` composition |
| Enemy health scaling | Exists — formula-based per wave index |
| Procedural wave generation (wave 9+) | Gap — no system beyond wave 8 |
| Balance telemetry framework | Gap — `TuningDashboardSnapshot` exists but no automated balance testing |
| Ammo surplus tracking | Gap — no metric for "ammo headroom" |

---

## Appendix A: Full Production Chain Graph

```
                                RESOURCE NODES (ore patches on map)
                                    |           |           |
                                 [IRON]      [COPPER]     [COAL]
                                    |           |           |
                                 MINERS      MINERS      MINERS
                                    |           |           |
                                ore_iron    ore_copper   ore_coal
                                    |           |          /  \
                                    v           v         v    v
                              +-----------+  +----------+     |
                              | SMELTER   |  | SMELTER  |     |
                              | smelt_iron|  | smelt_cu |     |
                              +-----------+  +----------+     |
                                    |           |             |
                              plate_iron    plate_copper      |
                               /   |   \       / |            |
                              v    v    v     v   v            |
                         +------+ +------+  +--------+        |
                         | SMELT| | ASSM | | ASSEMB  |        |
                         | steel| | gear | | circuit |<-------+
                         +------+ +------+ +--------+
                            |       |         |    \
                      plate_steel  gear    circuit  |
                       / | \  \     |      / |  \   |
                      v  v  v  v    v     v  |   v  v
                   +-----+  +---+ +-----+ +-------+ +--------+
                   |AMMO | |AMMO| |ASSM | |ASSEMB | |ASSEMB  |
                   |light| |hvy | |wall | |turret | |pwr_cell|
                   +-----+ +---+ |kit  | |core   | +--------+
                      |      |   +-----+ +-------+     |
                 ammo_light  ammo_heavy  wall_kit turret_core
                      |          |                      |
                      v          v                      v
               turret_mk1   turret_mk2            +--------+
               gattling                            |AMMO    |
                                                   |plasma  |
                                                   +--------+
                                                       |
                                                  ammo_plasma
                                                       |
                                                       v
                                                plasma_sentinel
```

---

## Appendix B: Implementation Priority Matrix

| Feature | Impact | Effort | Priority | Status |
|---------|--------|--------|----------|--------|
| Build cost enforcement in simulation | Critical | Low | **P0** | **Done** (M0) |
| Wire turret type system (per-turret ammo/range/fire rate) | Critical | Medium | **P0** | **Done** (M0) |
| Replace hardcoded EconomySystem with recipe-driven production | Critical | High | **P0** | **Done** (M0) |
| Add missing production (gear, wall_kit, turret_core, plasma) | Medium | Low | **P0** | **Done** (M0) |
| Recipe timing (accumulated progress per structure) | High | High | **P1** | **Partial** — smelter/assembler/ammo module done |
| Ore patch / resource node entities | High | Medium | **P1** | Not started |
| Structure targeting by enemies (raider, breacher, artillery) | High | Medium | **P1** | Not started |
| Storage capacity limits | Medium | Low | **P1** | Not started |
| Structure removal / refund command | Medium | Low | **P1** | Not started |
| Wave spawning from `waves.json` (replace formula) | High | Medium | **P1** | Not started |
| Procedural wave generation (wave 9+) | Medium | Medium | **P1** | Not started |
| Conveyor-routed logistics (per-building buffers, backpressure) | Medium | High | **P2** | Not started (see `building_specifications.md`) |
| Power priority system | Low | Medium | **P2** | Not started |
| Structure upgrade system | Low | Medium | **P2** | Not started |
| Balance telemetry automation | Medium | High | **P2** | Not started |

---

## Appendix C: Files Requiring Modification

| File | Changes |
|------|---------|
| `Sources/GameSimulation/Systems.swift` | **Major rework**: EconomySystem (recipe-driven, timing, all production chains), CombatSystem (per-turret type, fire rate, ammo type), CommandSystem (build cost validation, removeStructure command) |
| `Sources/GameSimulation/SimulationTypes.swift` | **Extend**: EconomyState (crafting progress, storage capacity), CombatState (lastFireTick per turret, turretDefID per entity), CommandPayload (add removeStructure), new ResourceNode entity support, EnemyRuntime (target selection mode) |
| `Sources/GameSimulation/EntityStore.swift` | **Extend**: Structure health differentiation by type, resource node spawn/depletion, turret type storage per entity |
| `Sources/GameContent/ContentTypes.swift` | **New types**: ResourceNodeDef, StructureCostDef, structure-recipe binding, turret-type-to-ammo mapping |
| `Sources/GameContent/ContentLoader.swift` | **Extend**: Load resource node definitions, structure costs, bind turret defs to simulation |
| `Content/bootstrap/recipes.json` | No changes — becomes authoritative source (currently decorative) |
| `Content/bootstrap/turrets.json` | No changes — becomes authoritative source (currently decorative) |
| `Content/bootstrap/waves.json` | No changes — becomes authoritative source for waves 1-8 (currently decorative) |
| `Sources/GameUI/ProductionUI.swift` | **Update**: Build menu uses simulation-enforced costs, removal/refund UI, recipe pinning |

---

## Changelog

- 2026-02-15: Initial draft — forward-looking v1 design for factory and economy systems.
- 2026-02-15: Accuracy pass — fixed recipe times (craft_wall_kit 1.2s, craft_turret_core 2.5s, craft_repair_kit 2.0s), corrected bootstrap state (2 turrets, 80 starting ammo), fixed placement validation status (PlacementValidator exists), clarified current vs proposed production rates in balance framework, corrected balance ratio table turret counts.
- 2026-02-16: Post-Milestone-0 status update — marked completed P0 items (build cost enforcement, per-turret combat, recipe-driven production, all production chains). Replaced superseded section 5 (zone-based logistics) with pointer to `building_specifications.md`. Fixed storage power draw from +1 to 0 per building specs. Added status column to Appendix B priority matrix.
