# Run Bootstrap & Session Initialization

Version: 1.0-draft
Date: 2026-02-16
Status: Draft
Depends on: `factory_economy.md`, `building_specifications.md`, `ore_patches_resource_nodes.md`, `wave_threat_system.md`

## Purpose

This document defines everything that happens between "the player starts a new run" and "the player has control." It unifies scattered bootstrap details from other PRDs into a single authoritative sequence and specifies the map layout, starter conditions, and difficulty parameterization that compose the T0 gameplay loop.

---

## 1. Run Lifecycle Overview

```
[Main Menu] → New Run → Difficulty Select → Session Init → Grace Period → Wave 1 → ... → End
```

### 1.1 States

| State | Description |
|-------|-------------|
| `initializing` | World is being constructed. No player input. |
| `gracePeriod` | Player has full control. No enemies. Timer visible. |
| `playing` | Normal play: build windows + wave/trickle cycles. |
| `gameOver` | HQ destroyed. Run ends. |
| `extracted` | Player voluntarily ended at a milestone. |

The current `RunState` in code tracks `baseIntegrity`, `extracted`, and `gameOver`. This PRD adds `gracePeriod` as a distinct phase so the simulation and UI can differentiate "safe build time" from "wave play."

### 1.2 Transitions

```
initializing → gracePeriod     (bootstrap complete, tick 0)
gracePeriod  → playing          (grace timer expires)
playing      → gameOver         (HQ health ≤ 0)
playing      → extracted        (player extracts at milestone checkpoint)
```

---

## 2. Difficulty Parameters

A single `Difficulty` enum (`easy`, `normal`, `hard`) gates all bootstrap variance. No individual parameters are independently tunable at T0 — difficulty is a single selector.

### 2.1 Aggregated Difficulty Table

All values sourced from linked PRDs. This table is the canonical cross-reference.

| Parameter | Easy | Normal | Hard | Source PRD |
|-----------|------|--------|------|------------|
| **Grace period** | 180s (3600 ticks) | 120s (2400 ticks) | 60s (1200 ticks) | wave_threat |
| **Ring 0 ore patches** | 7 | 5 | 3 | ore_patches / wave_threat |
| **Starting ore_iron** | 30 | 20 | 12 | wave_threat |
| **Starting ore_copper** | 20 | 12 | 8 | wave_threat |
| **Starting ore_coal** | 10 | 6 | 4 | wave_threat |
| **Starting plate_iron** | 8 | 4 | 2 | wave_threat |
| **Starting wall_kit** | 6 | 4 | 2 | wave_threat |
| **Starting ammo_light** | 20 | 12 | 6 | wave_threat |
| **Trickle spawn interval** | 15s | 12s | 8s | wave_threat |
| **Trickle enemies/spawn** | 1 | 1–2 | 2–3 | wave_threat |
| **Trickle composition** | Swarmlings | Swarmlings | Swarmlings + scouts | wave_threat |
| **Inter-wave gap base** | TBD | TBD | TBD | wave_threat |
| **HQ health** | 500 | 500 | 500 | wave_threat |

### 2.2 Data Representation

Difficulty parameters live in `hq.json` (starting resources, HQ stats) and `waves.json` (grace period, trickle config). The bootstrap sequence reads both.

---

## 3. Map Layout

### 3.1 Starter Board

| Property | Value | Rationale |
|----------|-------|-----------|
| Width | 96 tiles | Enough horizontal space for factory + buffer before spawn edge |
| Height | 64 tiles | Comfortable vertical space for multi-lane layouts |
| HQ position | (40, 32) | Left-of-center; factory builds left, defenses build right toward spawn |
| Spawn edge X | 56 | 16 tiles east of HQ — room for walls/turrets but close enough for pressure |
| Spawn Y range | 27–36 | 10-tile corridor centered on HQ row |

### 3.2 Spatial Zones

The map has three implicit zones that the player discovers through play:

```
 ← West                                              East →
 ┌──────────────────┬────────────────┬───────────────────┐
 │   Factory Zone   │  Defense Zone  │   Kill Zone       │
 │  (ore, buildings)│ (walls,turrets)│  (spawn → HQ path)│
 │   x: 0–39       │  x: 40–50     │   x: 50–56+       │
 └──────────────────┴────────────────┴───────────────────┘
                    ▲ HQ at (40,32)
```

- **Factory Zone** (west of HQ): Where ore patches spawn and production chains are built. Protected by distance from spawn edge.
- **Defense Zone** (around and east of HQ): Where walls and turrets are placed. The player's defensive line.
- **Kill Zone** (between defense line and spawn edge): Open ground where enemies approach. Turret range should cover this area.

These zones are not enforced — the player can build anywhere. They emerge naturally from HQ placement and spawn edge geometry.

### 3.3 Ring 0 Ore Patch Placement

Per `ore_patches_resource_nodes.md`, Ring 0 patches are within immediate reach of the HQ. For bootstrap:

- **Count**: 3 / 5 / 7 by difficulty (hard / normal / easy)
- **Placement region**: Within 6 tiles of HQ (x: 34–46, y: 26–38), excluding restricted cells
- **Composition**: Weighted by rarity — iron (1.0), copper (0.6), coal (0.4)
- **Guarantee**: At least 2 iron patches and 1 copper patch in Ring 0 regardless of difficulty. Coal is not guaranteed.
- **Richness**: Ring 0 patches are always `normal` richness tier.
- **Algorithm**: Poisson-disc sampling within the placement region with minimum 3-tile separation between patches. Deterministic from run seed.

### 3.4 Restricted Cells

The following cells cannot have structures or ore patches placed on them:

- HQ footprint: 2×2 centered at (40, 32) → cells (39–40, 31–32) per `wave_threat_system.md`
- Ramp cells: (47, 31), (47, 32), (47, 33) per existing `BoardDef.starter`

> **Note**: The current code has a 5-cell cross pattern for restricted cells around HQ. This should be reconciled with the 2×2 HQ footprint from `wave_threat_system.md`. The PRD-canonical HQ footprint is 2×2.

---

## 4. Bootstrap Sequence

This is the ordered list of operations that compose `WorldState.bootstrap(difficulty:seed:)`.

### Step 1: Create Board
- Instantiate `BoardState` from `BoardDef.starter` (96×64).
- Apply restricted cells and ramp definitions.

### Step 2: Place HQ Entity
- Spawn HQ as a 2×2 structure entity at base position (40, 32).
- Set HQ health to 500 (from `wave_threat_system.md`).
- HQ has 24-slot storage capacity and 4 output ports (N/S/E/W).
- HQ acts as the initial storage hub — starting resources are placed in the HQ's buffer.

### Step 3: Generate Ring 0 Ore Patches
- Read difficulty to determine patch count.
- Run deterministic placement algorithm (see §3.3) using run seed.
- Spawn ore patch entities at computed positions with type and richness assigned.

### Step 4: Grant Starting Resources
- Load starting resource table from `hq.json` keyed by difficulty.
- Place resources into HQ storage buffer (not a global inventory).
- Starting resources include raw ores, some plates, wall kits, and ammo to survive early pressure while the player's factory spins up.
- **There are no other pre-placed structures.** The HQ is the only building on the map at tick 0. The player uses the grace period to place their entire factory and defense line from scratch using starting resources. This maximizes player agency from the very first moment of the run.

### Step 5: Initialize Threat State
- Set `nextWaveTick` based on difficulty grace period.
- Set `waveIndex = 0`, `isWaveActive = false`.
- Trickle spawns begin when grace period ends (per `wave_threat_system.md`).

### Step 6: Initialize Run State
- `baseIntegrity` → replaced by HQ entity health (500).
- `extracted = false`, `gameOver = false`.
- `phase = .gracePeriod`.

### Step 7: Emit Run Started
- Emit `SimEvent.runStarted` at tick 0.
- No derived power state to compute — power supply/demand is 0 until the player places structures.

---

## 5. Grace Period

### 5.1 Behavior

During the grace period:
- The player can build, remove, and rearrange structures freely.
- Production runs normally (miners extract, smelters process, conveyors move).
- No enemies spawn. No trickle. No raids.
- A countdown timer is visible in the HUD showing remaining grace time.
- The player may optionally end the grace period early (future — not required for T0).

### 5.2 Transition to Playing

When the grace timer expires:
- `RunState.phase` transitions from `gracePeriod` to `playing`.
- Trickle spawns begin immediately per the difficulty trickle table.
- The first authored wave is scheduled per `waves.json` timing.
- `SimEvent.gracePeriodEnded` is emitted.

---

## 6. End-of-Run Conditions

### 6.1 Loss — HQ Destroyed

Per `wave_threat_system.md` §2.3: **the run ends when HQ health reaches 0.** This is the only loss condition.

**Damage sources that can destroy the HQ:**
- Enemy entities that reach the HQ position deal their damage value (varies by type: swarmling ~1, raider ~3).
- No passive repair — only `repair_kit` deliveries via conveyors restore HQ health (per `wave_threat_system.md`).

**When HQ health hits 0:**
1. `RunState.phase` transitions to `gameOver`.
2. `SimEvent.gameOver` is emitted with the final tick count.
3. Simulation systems stop executing (engine returns empty events).
4. The run is frozen — no further commands are processed.

### 6.2 V1 Scope — No Win Condition

Per the living PRD: "Endless survival escalation in v1; extraction/meta conversion is deferred."

There is **no win state** at T0. The run is endless — you survive until the HQ falls. The implicit goal is "how long can you last."

Extraction (`RunState.phase = .extracted`) exists as a placeholder for future milestone-based voluntary exit, but is **out of scope for T0**. The extract command and UI button should be removed or hidden until the extraction economy is designed.

### 6.3 End-of-Run Summary

When the run ends (gameOver), the player sees a summary screen. This is the only feedback on "how well did you do."

**T0 summary stats** (derived from events already tracked in simulation):

| Stat | Source | Display |
|------|--------|---------|
| Waves survived | `ThreatState.waveIndex` | "Survived 12 waves" |
| Run duration | `WorldState.tick` / 20 | "Lasted 8m 32s" |
| Enemies destroyed | Count of `.enemyDestroyed` events | "142 enemies destroyed" |
| Structures built | Count of `.structurePlaced` events | "23 structures built" |
| Ammo spent | Sum of `.ammoSpent` event values | "480 ammo spent" |
| Final HQ health | 0 (always, since run ended on destruction) | — |

**No scoring formula at T0.** Stats are informational only. No leaderboard, no meta-progression currency, no unlocks. The summary exists so the player can compare runs mentally and understand what went wrong.

### 6.4 Post-Summary Flow

After the summary screen:
- **"New Run"** → returns to difficulty select → new bootstrap.
- **"Main Menu"** → returns to title screen.
- No auto-save of the dead run. The run is gone.

### 6.5 Run State Machine (Complete)

```
                    ┌─────────────┐
                    │ initializing │
                    └──────┬──────┘
                           │ bootstrap complete
                    ┌──────▼──────┐
                    │ gracePeriod  │
                    └──────┬──────┘
                           │ timer expires
                    ┌──────▼──────┐
              ┌─────│   playing    │
              │     └──────┬──────┘
              │            │ HQ health ≤ 0
              │     ┌──────▼──────┐
              │     │  gameOver    │──→ Summary → New Run / Menu
              │     └─────────────┘
              │
              │ (future: extraction at milestone)
              │     ┌─────────────┐
              └────▶│  extracted   │──→ Summary → New Run / Menu
                    └─────────────┘
                    (out of scope for T0)
```

---

## 7. What the Player Sees at Tick 0

This section describes the intended player experience in the first 30 seconds, serving as a design target for rendering and UI.

1. **Camera** centers on HQ. The factory zone is visible to the west, the kill zone to the east.
2. **HQ** is visible as the largest structure on the map, with a health bar.
3. **Ore patches** are visible as colored terrain markers (iron = blue-grey, copper = orange, coal = dark) scattered around the HQ.
4. **Nothing else is built.** The map is empty except for the HQ and ore patches.
5. **Resource HUD** shows starting inventory from HQ storage.
6. **Grace period timer** counts down prominently.
7. **Build menu** is accessible and immediately obvious. The player's first action is to open it and start placing structures.

The implicit message to the player: "Here's your base and some supplies. The clock is ticking — build."

---

## 7. Seed & Determinism

- Each run has a `UInt64` seed set at run creation.
- The seed determines: ore patch placement, ore type/richness rolls.
- All other bootstrap state is deterministic from difficulty + seed.
- Two runs with the same difficulty and seed produce identical `WorldState` at tick 0.
- The seed is stored in the snapshot for replay fidelity.

---

## 8. Reconciliation with Current Code

The current `WorldState.bootstrap()` differs from this PRD in several ways that need to be resolved:

| Current Code | PRD Target | Action |
|--------------|------------|--------|
| No difficulty parameter | `bootstrap(difficulty:seed:)` | Add params |
| No HQ entity (just position + integrity) | HQ is a 2×2 structure with 500HP and storage | Add HQ entity type |
| No ore patches | Ring 0 patches placed deterministically | Implement ore patch spawning |
| 6 hardcoded structures in a line | HQ only — no other pre-placed structures | Remove all starter structures from bootstrap |
| Global inventory (flat dict) | Resources in HQ storage buffer | Move to per-building buffer model |
| Grace period = 400 ticks (20s) hardcoded | Difficulty-scaled (1200/2400/3600 ticks) | Read from content data |
| `RunState.baseIntegrity = 100` | HQ entity health = 500 | Migrate to entity health |
| No run seed | Deterministic seed for ore placement | Add seed field |
| No phase tracking | `RunState.phase` enum | Add phase field |
| 5-cell cross restricted zone | 2×2 HQ footprint restricted zone | Reconcile geometry |
| No `gameOver` event emitted | `SimEvent.gameOver` with tick count | Add event kind |
| No end-of-run summary | Stats summary screen on game over | Build summary view |
| Extract button visible and functional | Extraction deferred — hide or remove | Remove from T0 UI |
| Raids deal flat 2 damage to `baseIntegrity` | Enemies deal typed damage to HQ entity | Migrate to entity damage model |

---

## 9. Implementation Phases

### Phase 1: Core Bootstrap (blocks T0 loop)
- Add `Difficulty` enum and `RunSeed` to `WorldState`.
- Add `RunPhase` enum (`initializing`, `gracePeriod`, `playing`, `gameOver`, `extracted`) to `RunState`.
- Refactor `WorldState.bootstrap()` → `WorldState.bootstrap(difficulty:seed:)`.
- Load starting resources from `hq.json` by difficulty.
- Set grace period ticks from difficulty.
- Emit `runStarted` and `gracePeriodEnded` events.

### Phase 2: HQ Entity & End-of-Run (blocks T0 loop)
- Add `StructureType.hq` with 2×2 footprint, 500HP, 24-slot storage, 4 ports.
- Spawn HQ entity during bootstrap.
- Migrate `RunState.baseIntegrity` → HQ entity health.
- Update `CombatSystem` and `EnemyMovementSystem` to deal damage to HQ entity instead of decrementing integrity.
- Game over when HQ entity health ≤ 0 → transition to `gameOver` phase.
- Add `SimEvent.gameOver` event kind with final tick count.
- Remove/hide extract button and extraction command from T0 UI.
- Build end-of-run summary view showing waves survived, duration, enemies destroyed, structures built, ammo spent.
- Add post-summary flow: "New Run" → difficulty select, "Main Menu" → title.

### Phase 3: Ore Patch Integration (blocks T0 loop)
- Implement Ring 0 ore patch placement algorithm (§3.3).
- No starter structures to wire — player places all miners and conveyors.

### Phase 4: Difficulty Tuning (enhances T0, not blocking)
- Implement full difficulty table for trickle spawns.
- Add optional early grace-period-end command.
- Balance starting resource quantities through playtesting.

---

## 10. Open Questions

1. ~~Should the player choose bootstrap structure placement?~~ **Resolved: HQ only.** The player places everything else. No pre-built production chain.
2. **Map rotation**: Should the factory-west / spawn-east orientation be fixed, or should spawn direction vary per run for replayability?
3. **Grace period skipping**: Should the player be able to end grace period early for a score/reward bonus?
4. **Starting resource balance**: Current difficulty tables from `wave_threat_system.md` were designed assuming some pre-placed structures. With HQ-only bootstrap, do starting resources need to be more generous to cover the cost of placing a power plant + miner + smelter + initial defenses?

---

## Changelog

- 2026-02-16: Initial draft. Unified bootstrap details from wave_threat, ore_patches, and factory_economy PRDs.
- 2026-02-16: Resolved bootstrap structures — HQ only, player builds everything else.
- 2026-02-16: Added §6 end-of-run conditions: loss (HQ destroyed), no win condition at T0, summary stats, post-summary flow, complete state machine diagram.
