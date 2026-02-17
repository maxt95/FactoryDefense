# Building Specifications PRD

**Version:** 1.0-draft
**Parent:** `docs/prd/factory_economy.md`
**Status:** Implemented in v1 runtime
**Last updated:** 2026-02-17

> **Design model:** Conveyor-routed connections with per-building buffers. Items physically move between buildings via directed conveyor tiles. Each building has local input/output buffers with limited capacity. Backpressure propagates naturally through the system.

> **Implementation decision update (2026-02-17):**
> - Production/storage buildings are side-agnostic at runtime: any cardinal side may accept valid input or emit output.
> - Conveyors own directionality via explicit per-entity input/output directions; placement rotation sets defaults, interact mode can reconfigure later.
> - `EconomyState.inventories` is aggregate/display-only and is not a transport or production pull source.
> - If older examples/tables in this doc imply fixed building-side ingress/egress, this update supersedes those side constraints.

---

## Table of Contents

1. [Port System Architecture](#1-port-system-architecture)
2. [Conveyor System](#2-conveyor-system)
3. [Per-Building Buffer Model](#3-per-building-buffer-model)
4. [Building Specifications](#4-building-specifications)
5. [Item Flow Rules](#5-item-flow-rules)
6. [Worked Examples](#6-worked-examples)
7. [Quick Reference Table](#7-quick-reference-table)
8. [New Types Required](#8-new-types-required)
9. [Implementation Sequencing](#9-implementation-sequencing)

---

## Terminology

| Term | Definition |
|------|-----------|
| **Port** | A connection point on a building's side where items enter (input) or exit (output) |
| **Buffer** | Local item storage at a port; finite capacity, items queue in FIFO order |
| **Backpressure** | When a downstream buffer is full, upstream items stall, propagating backward through conveyors |
| **Starvation** | When an input buffer is empty and the building cannot start its next craft cycle |
| **Wall network ammo pool** | Per-wall-network shared ammo pool (capacity = segmentCount × 12); conveyors inject ammo at any wall segment, turrets draw from their network's pool. Supersedes the previous "logical ammo pool" model. |
| **Recipe pinning** | Player manually locks a building to a specific recipe, overriding auto-selection |

---

## 1. Port System Architecture

### 1.1 Cardinal Directions

Every 1x1 tile has four cardinal sides: North, South, East, West.

| Direction | Grid Offset | Adjacent Tile |
|-----------|------------|---------------|
| North | (0, -1) | Above |
| South | (0, +1) | Below |
| East | (+1, 0) | Right |
| West | (-1, 0) | Left |

### 1.2 Port Definition

Each port has:
- **Direction** — which side of the building (N/S/E/W)
- **Type** — input or output
- **Item filter** — what items the port accepts or emits
- **Buffer capacity** — maximum items the port can hold

Item filters:
- `any` — accepts all item types
- `kind(raw)` — only raw ores
- `kind(processed)` — only plates, gears, circuits, etc.
- `kind(ammo)` — only ammunition
- `specific([...])` — only listed item IDs

### 1.3 Default Orientation & Rotation

Building rotation is still placement metadata and visual orientation. Runtime intake/output for production/storage structures is side-agnostic.

For conveyors, rotation determines default I/O only:
- default `outputDirection` = facing direction from rotation
- default `inputDirection` = opposite of output

Players can later override conveyor I/O explicitly from interact controls.

### 1.4 How Items Enter & Exit Ports

**Entering (building inputs):**
1. An adjacent conveyor pushes its carried item toward a building.
2. The building accepts if: (a) input capacity is not full, AND (b) the item passes structure/item filter rules.
3. Building side does not gate acceptance; conveyors gate ingress by their configured output and the receiver's acceptance rules.
4. If rejected, the item stays on the conveyor (backpressure).

**Exiting (building outputs):**
1. When a building finishes crafting, output items are placed into the structure output buffer.
2. The building attempts to push output to adjacent consumers on any cardinal side.
3. If no valid route is available (or target is full), items remain buffered (backpressure halts further crafting once output capacity is full).

---

## 2. Conveyor System

### 2.1 Conveyor Tile Model

Each conveyor occupies 1 tile and has:
- **Input direction** — side where the conveyor accepts incoming items
- **Output direction** — side where the conveyor forwards items
- **Item slot** — holds at most **1 item** at a time
- **Progress** — 0.0 (just entered) to 1.0 (ready to hand off to next tile)

### 2.2 Conveyor Speed

**1 item traverses one conveyor tile in 5 ticks (0.25 seconds).**

- Progress increases by 0.2 per tick
- Throughput: **4 items/second per conveyor lane**
- This creates meaningful constraints — a single lane can carry moderate traffic, but high-throughput chains may need parallel lanes

Speed rationale at 20 Hz:
- A smelter outputs 1 plate every 40 ticks (2s) — easily served by 1 lane
- An ammo module outputs 4 ammo_light every 40 ticks (2s) — 2 items/s, fits in 1 lane
- 2 smelters outputting to 1 assembler = 1 plate/s, fits in 1 lane
- But 4+ smelters feeding a common line would saturate a single lane

### 2.3 Connection Rules

Connections are **implicit** based on adjacency and conveyor I/O direction:

**Conveyor to conveyor:**
A conveyor at position P with `outputDirection = east` hands off to P+(1,0) if that tile is a conveyor, the receiving conveyor is empty, and P matches the receiver's configured input side.

**Conveyor to building input:**
A conveyor at P with `outputDirection = east`, where P+(1,0) is a building, attempts delivery into that building's input buffer. The target building side is not fixed; item acceptance is validated by structure/filter/capacity rules.

**Building output to conveyor:**
A building at P can push output to an adjacent conveyor on any side, as long as the conveyor is empty and configured to intake from P.

No explicit "link" entities needed. Adjacency + direction alignment = connection.

### 2.4 Conveyor Variants

**Standard Conveyor** (`conveyor`):
- 1 input side + 1 output side, both explicitly configurable per entity
- Rotation at placement time sets default input/output directions
- Holds 1 item, 5 ticks to traverse
- Does NOT block enemy movement

**Splitter** (`splitter`, new StructureType):
- 1 input side, 2 output sides (configurable at placement)
- Alternates items between the 2 outputs (round-robin)
- If current output is blocked, tries the other (does NOT flip — retries originally-blocked side next)
- If both blocked, item waits (backpressure)
- Same speed as standard conveyor
- Does NOT block enemy movement

**Merger** (`merger`, new StructureType):
- 2 input sides, 1 output side
- Alternates pulling from inputs (round-robin: even ticks from A, odd ticks from B)
- If selected input is empty, immediately tries the other
- Same speed as standard conveyor
- Does NOT block enemy movement

### 2.5 Backpressure on Conveyors

Items do NOT stack on conveyors. Each tile holds exactly 1 item. When an item reaches progress 1.0 but cannot hand off, it stays at 1.0 on its tile. This blocks any item behind it from advancing, creating a natural queue that propagates backward.

This is the core flow-control mechanism: full output buffer -> backed-up conveyors -> upstream production stalls.

---

## 3. Per-Building Buffer Model

### 3.1 Production Cycle (per tick, per building)

**Step 1 — Recipe Selection:**
If `pinnedRecipeID` is set, use that. Otherwise, auto-select from allowed recipes (in priority order) by checking which recipe has sufficient inputs in the input buffers.

**Step 2 — Input Consumption (when craft starts):**
When `craftProgress == 0.0` and a recipe is selected:
- Check if input buffers contain all required items for one batch
- If yes: remove items from input buffers, place in internal processing slot, begin crafting
- If no: remain idle (starvation), `craftProgress` stays at 0.0

**Step 3 — Craft Progress:**
If crafting is in progress (internal slot occupied):
- Advance `craftProgress` by `powerEfficiency / (recipeSeconds x 20.0)`
- At efficiency 1.0, a 2.0s recipe advances by 0.025 per tick (completes in 40 ticks)
- At efficiency 0.5, same recipe takes 80 ticks

**Step 4 — Output (when craft completes):**
When `craftProgress >= 1.0`:
- Check if output buffer has room for all output items
- If yes: place outputs in output buffer, clear internal slot, carry fractional progress remainder
- If no: halt — `craftProgress` stays at 1.0, internal slot remains occupied (**output blocked**)

### 3.2 Buffer Sizing Philosophy

Buffer sizes balance three concerns:
- **Too small:** constant micromanagement, frustrating
- **Too large:** no visible bottlenecks, conveyors feel meaningless
- **Just right:** 5-10 seconds of runway before starvation or blocking

At 20 Hz with 2-4s recipe times:
- Input buffer of 8 items = ~4 batches of a 2-input recipe = ~8 seconds of work
- Output buffer of 4 items = ~4 batches before blocking = ~8 seconds of runway

### 3.3 Status Indicators

Each building shows its current status:
- **Running** (green) — actively crafting
- **Input Starved** (orange) — recipe requires inputs not in buffers
- **Output Blocked** (red) — output buffer full, crafting halted
- **Underpowered** (yellow) — power efficiency < 1.0, crafting slowed
- **No Ore Patch** (red, miners only) — not adjacent to any ore patch
- **Idle** (gray) — no recipe selected, or no applicable recipe for current inputs

---

## 4. Building Specifications

Runtime note: production/storage building tables below keep item filter/capacity intent, but side-specific ingress/egress is superseded by side-agnostic building I/O in current runtime.

### 4.1 Miner

**Purpose:** Extracts raw ore from adjacent ore patches.

```
     N
   +---+
W  | M |  E --> [OUTPUT: 8 raw ore]
   +---+
     S
```

| Property | Value |
|----------|-------|
| Grid footprint | 1x1 |
| Input ports | None |
| Output ports | 1 — East, filter: `kind(raw)`, buffer: **8** |
| Internal buffer | 1 slot (ore being extracted) |
| Processing speed | 1 ore per 20 ticks (1.0 second) at 1.0 efficiency |
| Power draw | 2 |
| Health | 60 |
| Build cost | 6 plate_iron + 3 gear |
| Blocks movement | Yes |

**Special rules:**
- Must be placed cardinally adjacent (N/S/E/W) to a revealed ore patch (not on the patch tile)
- Ore type produced matches the patch type (iron, copper, or coal)
- If ore patch depletes, miner goes idle
- Exactly one miner can be bound to a patch (1:1 miner-patch binding)
- Extraction per tick: if output buffer is not full AND adjacent patch has richness remaining, increment progress by `powerEfficiency / 20.0`. When progress >= 1.0, produce 1 ore, decrement patch richness by 1

**Effective output rates (at 1.0 efficiency):**

| Ore Type | Output/second | Output per 20s build phase |
|----------|--------------|---------------------------|
| ore_iron | 1.0 | 20 |
| ore_copper | 1.0 | 20 |
| ore_coal | 1.0 | 20 |

---

### 4.2 Smelter

**Purpose:** Converts raw ores and intermediate plates into refined plates through thermal processing.

```
          N
        +---+
[IN:8]  | S |  [OUT:4]
  W --> | M | --> E
        +---+
          S
```

| Property | Value |
|----------|-------|
| Grid footprint | 1x1 |
| Input ports | 1 — West, filter: `specific(ore_iron, ore_copper, ore_coal, plate_iron)`, buffer: **8** |
| Output ports | 1 — East, filter: `kind(processed)`, buffer: **4** |
| Internal buffer | 1 batch (items being smelted) |
| Recipes | `smelt_iron`, `smelt_copper`, `smelt_steel` |
| Power draw | 3 |
| Health | 80 |
| Build cost | 4 plate_steel |
| Blocks movement | Yes |

**Recipes & timing:**

| Recipe | Inputs | Outputs | Ticks (at 1.0) | Output/sec |
|--------|--------|---------|----------------|------------|
| `smelt_iron` | 2 ore_iron | 1 plate_iron | 40 (2.0s) | 0.5 |
| `smelt_copper` | 2 ore_copper | 1 plate_copper | 40 (2.0s) | 0.5 |
| `smelt_steel` | 2 plate_iron + 1 ore_coal | 1 plate_steel | 80 (4.0s) | 0.25 |

**Auto-select priority:** `smelt_steel` > `smelt_iron` > `smelt_copper` (highest tier first).

**Mixed input note:** The single input port accepts multiple item types. For `smelt_steel`, the buffer needs both plate_iron AND ore_coal simultaneously. The player must route both item types to the same input (use a merger upstream to combine two conveyor lines). Buffer holds a mixed collection; recipe selection checks the buffer contents.

---

### 4.3 Assembler

**Purpose:** Creates intermediate components and utility items from refined materials.

```
     N
   [IN:6]
   +---+
W  | A |  E
[IN:6] | --> [OUT:4]
   +---+
     S
```

| Property | Value |
|----------|-------|
| Grid footprint | 1x1 |
| Input ports | 2 — West, filter: `any`, buffer: **6**; North, filter: `any`, buffer: **6** |
| Output ports | 1 — East, filter: `any`, buffer: **4** |
| Internal buffer | 1 batch |
| Recipes | `forge_gear`, `etch_circuit`, `assemble_power_cell`, `craft_wall_kit`, `craft_turret_core`, `craft_repair_kit` |
| Power draw | 3 |
| Health | 80 |
| Build cost | 4 plate_iron + 2 circuit |
| Blocks movement | Yes |

**Recipes & timing:**

| Recipe | Inputs | Outputs | Ticks (at 1.0) | Output/sec |
|--------|--------|---------|----------------|------------|
| `forge_gear` | 2 plate_iron | 1 gear | 30 (1.5s) | 0.67 |
| `etch_circuit` | 2 plate_copper + 1 ore_coal | 1 circuit | 40 (2.0s) | 0.5 |
| `assemble_power_cell` | 1 plate_copper + 1 circuit | 1 power_cell | 50 (2.5s) | 0.4 |
| `craft_wall_kit` | 1 plate_steel + 1 gear | 1 wall_kit | 24 (1.2s) | 0.83 |
| `craft_turret_core` | 1 plate_steel + 1 circuit + 1 gear | 1 turret_core | 50 (2.5s) | 0.4 |
| `craft_repair_kit` | 1 plate_steel + 1 circuit | 1 repair_kit | 40 (2.0s) | 0.5 |

**Auto-select priority:** `craft_turret_core` > `craft_wall_kit` > `craft_repair_kit` > `assemble_power_cell` > `etch_circuit` > `forge_gear`.

**Two input ports:** Many assembler recipes need 2-3 distinct input types. Two ports let the player dedicate one to the primary ingredient and the other to the secondary. Recipe selection draws from both input buffers combined.

---

### 4.4 Ammo Module

**Purpose:** Manufactures all ammunition types consumed by turrets.

```
     N
   [IN:6]
   +---+
W  |AM |  E
[IN:6] | --> [OUT:8 ammo]
   +---+
     S
```

| Property | Value |
|----------|-------|
| Grid footprint | 1x1 |
| Input ports | 2 — West, filter: `any`, buffer: **6**; North, filter: `any`, buffer: **6** |
| Output ports | 1 — East, filter: `kind(ammo)`, buffer: **8** |
| Internal buffer | 1 batch |
| Recipes | `craft_ammo_light`, `craft_ammo_heavy`, `craft_ammo_plasma` |
| Power draw | 4 |
| Health | 100 |
| Build cost | 2 circuit + 2 plate_steel |
| Blocks movement | Yes |

**Recipes & timing:**

| Recipe | Inputs | Outputs | Ticks (at 1.0) | Output/sec |
|--------|--------|---------|----------------|------------|
| `craft_ammo_light` | 1 plate_iron | 4 ammo_light | 40 (2.0s) | 2.0 |
| `craft_ammo_heavy` | 1 plate_steel + 2 ammo_light | 3 ammo_heavy | 52 (2.6s) | 1.15 |
| `craft_ammo_plasma` | 1 power_cell + 1 circuit | 2 ammo_plasma | 60 (3.0s) | 0.67 |

**Auto-select priority:** `craft_ammo_plasma` > `craft_ammo_heavy` > `craft_ammo_light`.

**Larger output buffer (8):** Ammo recipes produce multiple units per batch (4 light, 3 heavy, 2 plasma). The larger buffer prevents immediate blocking after a single batch.

**Wall network delivery:** Ammo in the output buffer is delivered to wall networks via conveyors connected to wall segments. Turrets draw ammo from their wall network's shared pool (see §4.11).

---

### 4.5 Power Plant

**Purpose:** Generates power for all buildings on the grid.

```
     N
   +---+
W  | P |  E
   | W |
   +---+
     S
   (no ports)
```

| Property | Value |
|----------|-------|
| Grid footprint | 1x1 |
| Input ports | None |
| Output ports | None |
| Internal buffer | N/A |
| Recipes | None |
| Power generation | **12** (passive, continuous) |
| Power draw | -12 (net generator) |
| Health | 80 |
| Build cost | 2 circuit + 4 plate_copper |
| Blocks movement | Yes |

**Special rules:**
- Power is distributed globally — no conveyor connections needed
- All buildings share the same efficiency factor: `min(1.0, totalSupply / totalDemand)`
- Destroying a power plant immediately reduces supply, potentially triggering a brownout cascade
- No fuel required (v1)

**One power plant (12 supply) supports:**

| Configuration | Power Demand | Headroom |
|--------------|-------------|----------|
| 1 miner + 1 smelter + 1 ammo module | 9 | 3 |
| 2 miners + 2 smelters | 10 | 2 |
| 1 miner + 1 smelter + 1 assembler + 1 ammo module | 12 | 0 |
| Starter base + 2 conveyors | 11 | 1 |

---

### 4.6 Conveyor

**Purpose:** Physically transports items between building ports.

```
  [item enters] --> [==========>] --> [item exits]
     West              5 ticks           East
```

| Property | Value |
|----------|-------|
| Grid footprint | 1x1 |
| Input | Back side (opposite of direction), accepts any 1 item |
| Output | Front side (direction of travel), emits carried item |
| Capacity | **1 item**, with progress counter 0.0–1.0 |
| Speed | 5 ticks per tile (0.25s), **4 items/second throughput** |
| Power draw | 1 |
| Health | 30 |
| Build cost | 1 plate_iron |
| Blocks movement | **No** |

**Special rules:**
- Placed with a direction (N/S/E/W)
- Items enter from opposite side, exit in direction
- When exit is blocked, item waits at progress 1.0 (backpressure)
- Cheapest structure — designed to be placed in quantity
- Does not block enemy pathing (enemies walk over conveyors)

---

### 4.7 Splitter (new)

**Purpose:** Divides a single item stream into two output directions.

```
                  N --> [OUT]
                  |
  [IN] --> W --> [SPL]
                  |
                  S --> [OUT]
```

| Property | Value |
|----------|-------|
| Grid footprint | 1x1 |
| Input | 1 side (configurable at placement) |
| Output | 2 sides (configurable at placement, the other 2 cardinal sides) |
| Capacity | 1 item, with progress counter |
| Speed | 5 ticks per tile |
| Power draw | 1 |
| Health | 30 |
| Build cost | 2 plate_iron + 1 gear |
| Blocks movement | **No** |

**Distribution logic:**
1. Item reaches progress 1.0
2. Check current output side (alternates round-robin)
3. If current output available: transfer, flip to other output for next time
4. If current blocked but other available: transfer to other (do NOT flip — retry original next time)
5. If both blocked: item waits (backpressure)

---

### 4.8 Merger (new)

**Purpose:** Combines two item streams into a single output direction.

```
  [IN] --> N ---+
                |
               [MRG] --> E --> [OUT]
                |
  [IN] --> S ---+
```

| Property | Value |
|----------|-------|
| Grid footprint | 1x1 |
| Input | 2 sides (configurable at placement) |
| Output | 1 side (configurable at placement) |
| Capacity | 1 item, with progress counter |
| Speed | 5 ticks per tile |
| Power draw | 1 |
| Health | 30 |
| Build cost | 2 plate_iron + 1 gear |
| Blocks movement | **No** |

**Pull logic:**
1. Alternates pulling from inputs each tick (even ticks: input A, odd ticks: input B)
2. If selected input is empty, immediately tries the other
3. Guarantees fair throughput sharing between sources

---

### 4.9 Storage

**Purpose:** Large-capacity buffer that smooths production/consumption mismatches.

```
     N
   [IN:24]
   +---+
W  |STO|  E
[IN:24]| [OUT:24]
   +---+
  [OUT:24]
     S
```

| Property | Value |
|----------|-------|
| Grid footprint | 1x1 |
| Input ports | 2 — West, filter: `any`, buffer: **24**; North, filter: `any`, buffer: **24** |
| Output ports | 2 — East, filter: `any`, buffer: **24**; South, filter: `any`, buffer: **24** |
| Internal capacity | **48** total (shared pool — inputs and outputs draw from same inventory) |
| Processing | Instant pass-through (deposited items are immediately available at output ports) |
| Power draw | 0 |
| Health | 60 |
| Build cost | 3 plate_steel + 2 gear |
| Blocks movement | Yes |

**Shared pool model:** Unlike production buildings, storage has a single internal inventory. All input ports deposit into it; all output ports withdraw from it. This makes storage work as a logistics hub.

**Output priority:** Items are pulled from outputs in FIFO order. When multiple output ports have connected conveyors, each port serves independently from the shared pool.

**Ammo routing:** Ammo stored here can be routed via conveyors to wall segments for injection into wall network ammo pools.

**4 ports (2 in, 2 out):** Allows storage to serve as a junction — accept items from multiple sources, distribute to multiple destinations. Critical for mid-game logistics.

---

### 4.10 Wall

**Purpose:** Blocks enemy pathing and absorbs damage.

```
     N
   +---+
W  | W |  E
   +---+
     S
   (no ports)
```

| Property | Value |
|----------|-------|
| Grid footprint | 1x1 |
| Ports | None |
| Power draw | 0 |
| Health | **150** |
| Build cost | 1 wall_kit |
| Blocks movement | Yes |

**Special rules:**
- Highest health of any structure
- No production or logistics role
- Enemies (breacher type) target walls directly when blocking their path
- Can be repaired with repair_kits (future: auto-repair from adjacent storage)

---

### 4.11 Turret Mount (Wall-Mounted)

> **Superseded model.** This section previously described turrets as standalone 1×1 buildings with an ammo input port. Per the living PRD and `wave_threat_system.md`, turrets now mount on wall segments (1:1) and draw ammo from per-wall-network shared pools. The standalone turret building model is removed.

**Purpose:** Mounts on a wall segment to fire projectiles at enemies within range, consuming ammo from the wall network's shared pool.

```
   +---+
   | W |  ← wall segment
   | T |  ← turret mounted on wall (same tile)
   +---+
   (no ports — ammo from wall network pool)
```

| Property | Value |
|----------|-------|
| Grid footprint | Shares wall segment's 1×1 tile (turret is an attachment, not a separate entity) |
| Input ports | None — draws ammo from the wall network's shared pool |
| Output ports | None |
| Power draw | 0 |
| Health | **100** (independent from wall). Turret is also destroyed if the host wall segment is destroyed, regardless of turret HP. |
| Build cost | 1 turret_core + 2 plate_steel (placed on an existing wall segment) |
| Blocks movement | Yes (inherited from wall segment) |

**Turret type stats (determined by `turretDefID` on entity):**

| Turret Type | Ammo Type | Fire Rate (shots/s) | Ticks Between Shots | Range | Damage |
|-------------|-----------|--------------------|--------------------|-------|--------|
| turret_mk1 | ammo_light | 2.0 | 10 | 8 | 12 |
| turret_mk2 | ammo_heavy | 1.4 | 14 | 10 | 25 |
| gattling_tower | ammo_light | 4.2 | 5 | 6.5 | 8 |
| plasma_sentinel | ammo_plasma | 0.9 | 22 | 11 | 45 |

**Wall network ammo pool model:**
- Each connected group of wall segments forms a **wall network** (connected components via cardinal adjacency).
- Each wall network has a **shared ammo pool** with capacity = `segmentCount × 12`.
- Conveyors inject ammo into the wall network at any segment along the wall line.
- Turrets draw from their network's shared pool. No ammo in the pool = turret cannot fire.
- When a wall segment is destroyed, the turret mounted on it is also destroyed. If the segment's destruction splits the network, each resulting sub-network gets its own pool (ammo redistributed proportionally).

**Key design implications:**
- Players must route conveyors to wall segments to supply ammo — turrets have no direct input ports.
- Longer wall lines have larger ammo pools, providing more buffer during sustained attacks.
- A wall breach can destroy both the wall and its turret, and may split the ammo pool.

---

## 5. Item Flow Rules

### 5.1 Push/Pull Model

| Transfer | Model | Description |
|----------|-------|-------------|
| Building output -> conveyor | Push | Buildings push finished items onto adjacent conveyors on any cardinal side each tick |
| Conveyor -> conveyor | Push | Items advance along configured conveyor output/input directions |
| Conveyor -> building input | Push | Conveyors push items into adjacent buildings when structure/filter/capacity checks pass |
| Building input -> processing | Pull | Buildings pull items from their own input buffers to start crafting |

### 5.2 Conveyor System Execution Order

The `ConveyorSystem` runs after `ProductionSystem` and before `TechSystem` (8 systems total):

```
Command > Economy/Production > Conveyor > Tech > Wave > EnemyMovement > Combat > Projectile
```

Processing within the ConveyorSystem per tick:

**Phase 1 — Output Ejection:**
For each production/storage building (sorted by EntityID ascending), attempt to push items from output buffers onto adjacent conveyors on all cardinal sides.

**Phase 2 — Conveyor Advancement:**
For each conveyor tile carrying an item with progress < 1.0, advance progress by 0.2.

**Phase 3 — Conveyor Handoff:**
For each conveyor tile with item progress >= 1.0 (processed **downstream-first** to prevent multi-tile jumps in one tick):
1. If next tile is empty conveyor: transfer item, reset progress to 0.0
2. If next tile is a building that accepts the item and has space: transfer into buffer
3. Otherwise: item waits (backpressure)

### 5.3 Edge Cases

**Conveyor facing empty tile / wall:** Item sits at progress 1.0 indefinitely, backing up the chain. Player error — build menu could warn.

**Conveyor loop (circular):** Items circulate forever. Simulation handles gracefully (items just loop). A content validator could warn about cycles.

**Building with no conveyors connected:** Output buffer fills up, production halts. "Output Blocked" status displayed.

**Power plant destroyed mid-game:** All buildings recalculate efficiency next tick. If efficiency drops, production slows globally. Conveyors still run (1 power draw each is minimal).

---

## 6. Worked Examples

### 6.1 Light Ammo Chain (Simplest)

```
[ORE PATCH] -- [MINER] --> [CONVEYOR] --> [SMELTER] --> [CONVEYOR] --> [AMMO MODULE]
   (iron)       (3,5)       (4,5)E         (5,5)         (6,5)E         (7,5)
```

| Step | Timing | What Happens |
|------|--------|-------------|
| Miner produces | Every 20 ticks | 1 ore_iron into output buffer (cap 8) |
| Ore enters conveyor | Next tick | Pushed from miner output to conveyor at (4,5) |
| Conveyor transit | 5 ticks | Item travels across tile |
| Ore enters smelter | After transit | Pushed into smelter West input buffer (cap 8) |
| Smelter accumulates | 40 ticks | Needs 2 ore_iron. Gets 1/second. 2 seconds to accumulate. |
| Smelting | 40 ticks | 2 ore -> 1 plate_iron. Progress 0.025/tick. |
| Plate enters conveyor | Next tick | Pushed from smelter output to conveyor at (6,5) |
| Plate enters ammo module | 5 ticks | Into ammo module West input buffer |
| Ammo crafting | 40 ticks | 1 plate -> 4 ammo_light |

**Steady-state throughput:**
- Miner: 1 ore/sec
- Smelter: 1 batch every 2s (waits for 2 ore) = 0.5 plates/sec
- Ammo module: 1 batch every 2s (waits for 1 plate) = 2 ammo_light/sec

**Result: 2 ammo_light/second from one chain. One turret_mk1 consumes 2 ammo/second. One chain exactly sustains one turret.**

### 6.2 Steel Ammo Chain (Multi-input)

```
[IRON PATCH] -- [MINER A] --> [CONV] --> [SMELTER A: iron] --> [CONV] --+
                                                                         |
                                                                      [MERGER] --> [CONV] --> [SMELTER B: steel]
                                                                         |
[COAL PATCH] -- [MINER B] --> [CONV] --> [CONV] --> [CONV] ----------+

[SMELTER B] --> [CONV] --> [AMMO MODULE: heavy]
                              ^
                              |
     [AMMO MODULE: light] --> [CONV] (light ammo fed as input)
```

**Throughput analysis:**
- Miner A: 1 ore_iron/s
- Smelter A (smelt_iron): 0.5 plate_iron/s (2 ore per batch, 2s cycle)
- Miner B: 1 ore_coal/s
- Smelter B (smelt_steel): needs 2 plate_iron + 1 ore_coal per batch, 4s cycle. Gets 0.5 plates/s from Smelter A, so 1 batch every 4s = 0.25 plate_steel/s
- Ammo Module (heavy): needs 1 plate_steel + 2 ammo_light, 2.6s cycle. Gets 0.25 steel/s, so 1 batch every 4s = 0.75 ammo_heavy per 4s

**Bottleneck:** Smelter A is the constraint — it can only produce 0.5 plates/s, and Smelter B needs 2 per batch. Adding a second iron miner + using parallel smelting would double throughput.

### 6.3 Wall Network Ammo Supply

**Conveyor feeds wall network:**
```
[AMMO MODULE] --> [CONV] --> [CONV] --> [WALL SEGMENT] ── [WALL+TURRET] ── [WALL+TURRET]
```
- Ammo flows from ammo module into a wall segment via conveyor
- Wall segment injects ammo into the wall network's shared pool
- All turrets mounted on walls in that connected network draw from the shared pool
- Pool capacity = segmentCount × 12 (e.g., 5 wall segments = 60 ammo capacity)

**Storage as intermediate buffer:**
```
[AMMO MODULE] --> [CONV] --> [STORAGE] --> [CONV] --> [WALL SEGMENT]
```
- Storage smooths production/consumption mismatches before ammo enters the wall network
- Useful when ammo production is bursty but turret consumption is steady

**Split wall network risk:**
```
[WALL+TURRET] ── [WALL] ── [WALL+TURRET]    (if middle wall destroyed → 2 separate networks)
```
- If the connecting wall segment is destroyed, the network splits into two sub-networks
- Each sub-network gets its own ammo pool — turrets on each side only draw from their local pool
- Redundant conveyor feeds to different wall segments mitigate this risk

---

## 7. Quick Reference Table

| Building | HP | Power | In Ports (side: filter, cap) | Out Ports (side: filter, cap) | Internal | Recipes | Blocks |
|----------|-----|-------|-----|------|-----|---------|--------|
| Miner | 60 | +2 | — | Any side: raw, 8 | 1 | extraction | Yes |
| Smelter | 80 | +3 | Any side: ore+plate, 8 | Any side: processed, 4 | 1 batch | smelt_* | Yes |
| Assembler | 80 | +3 | Any side: any, 12 total | Any side: any, 4 | 1 batch | forge/etch/assemble/craft_* | Yes |
| Ammo Module | 100 | +4 | Any side: any, 12 total | Any side: ammo, 8 | 1 batch | craft_ammo_* | Yes |
| Power Plant | 80 | -12 | — | — | — | — | Yes |
| Conveyor | 30 | +1 | Configured input side: any, 1 | Configured output side: any, 1 | 1 item | — | No |
| Splitter | 30 | +1 | back: any, 1 | 2x front: any, 1 | 1 item | — | No |
| Merger | 30 | +1 | 2x back: any, 1 | front: any, 1 | 1 item | — | No |
| Storage | 60 | 0 | Any side: any, 48 shared | Any side: any, 48 shared | 48 shared | pass-through | Yes |
| Wall | 150 | 0 | — | — | — | — | Yes |
| Turret Mount | 100 | 0 | — (wall network pool) | — | — | wall-mounted, fires projectiles; also destroyed if wall dies | Yes (wall) |

---

## 8. New Types Required

### 8.1 Content Types (GameContent)

**New `BuildingDef` type** — data-driven definition loaded from `Content/bootstrap/buildings.json`:

```swift
public struct BuildingDef: Codable, Hashable, Sendable {
    public var structureType: String          // matches StructureType raw value
    public var health: Int
    public var powerDraw: Int                 // negative = generates
    public var blocksMovement: Bool
    public var ports: [PortDef]
    public var allowedRecipeIDs: [String]     // ordered by priority
    public var internalBufferCapacity: Int
    public var buildCost: [ItemStack]
    public var extractionTicksPerUnit: Int?   // miners only
    public var conveyorTicksPerTile: Int?     // conveyors only
}
```

**Supporting types:**
- `CardinalDirection` — N/S/E/W enum with offset and opposite
- `PortDef` — direction, type (in/out), item filter, buffer capacity
- `ItemFilter` — any, kind, specific, none

### 8.2 Simulation Types (GameSimulation)

**Per-building runtime state:**

```swift
public struct BuildingProductionState: Codable, Hashable, Sendable {
    public var activeRecipeID: String?
    public var pinnedRecipeID: String?
    public var craftProgress: Double              // 0.0 to 1.0
    public var inputBuffers: [CardinalDirection: ItemBuffer]
    public var outputBuffers: [CardinalDirection: ItemBuffer]
    public var internalSlot: [ItemStack]          // items being processed
}
```

**Per-conveyor runtime state:**

```swift
public struct ConveyorState: Codable, Hashable, Sendable {
    public var direction: CardinalDirection
    public var item: ItemID?
    public var progress: Double                   // 0.0 to 1.0
}
```

**Buffer type:**

```swift
public struct ItemBuffer: Codable, Hashable, Sendable {
    public var entries: [ItemBufferEntry]
    public var capacity: Int
}
```

### 8.3 WorldState Extensions

```swift
// New fields on WorldState
public var buildingStates: [EntityID: BuildingProductionState]
public var conveyorStates: [EntityID: ConveyorState]
```

### 8.4 New StructureTypes

```swift
case splitter
case merger
```

### 8.5 New Command Payloads

```swift
case placeConveyor(position: GridPosition, direction: CardinalDirection)
case rotateBuilding(entityID: EntityID)
case pinRecipe(entityID: EntityID, recipeID: String?)
```

---

## 9. Implementation Sequencing

| Phase | What | Files |
|-------|------|-------|
| **1. Data layer** | Add BuildingDef, PortDef, CardinalDirection, ItemFilter to content types. Create `buildings.json`. Extend content loader and validator. | `ContentTypes.swift`, `ContentLoader.swift`, `ContentValidator.swift`, new `buildings.json` |
| **2. Runtime state** | Add BuildingProductionState, ConveyorState, ItemBuffer to simulation types. Extend WorldState. Add splitter/merger to StructureType. Add rotation to Entity. | `SimulationTypes.swift`, `EntityStore.swift` |
| **3. Production system** | Replace EconomySystem with recipe-driven ProductionSystem using per-building state. Handle miner extraction, recipe timing, auto-selection, pinning. | `Systems.swift` |
| **4. Conveyor system** | Implement ConveyorSystem with 3-phase tick logic. Handle backpressure, splitter/merger. | `Systems.swift` (new system) |
| **5. Integration** | Update SimulationEngine system list. Update CombatSystem for buffer + pool ammo. Update CommandSystem for new payloads. Extend snapshot serialization. | `SimulationEngine.swift`, `Systems.swift` |
| **6. UI** | Build menu with splitter/merger. Conveyor direction placement. Building rotation. Buffer visualization. Recipe pinning. | `ProductionUI.swift` |

---

## Relationship to Factory Economy PRD

This document **supersedes** section 5 (Logistics & Transport) of `docs/prd/factory_economy.md` and refines section 3 (Production Chain Architecture) with the conveyor-routed, per-building-buffer model. The following from the economy PRD remains valid:
- Recipe definitions and timing (section 3.3)
- Power generation/consumption values (section 4)
- Structure health values (section 7.6)
- Build costs (section 6.2)
- Balance framework (section 8)

The key change: items no longer live in a global `EconomyState.inventories` dictionary. They live in building buffers and on conveyor tiles. The "global inventory" is a computed aggregate for HUD/analytics and is not used as a logistics fallback.

---

## Changelog

- 2026-02-15: Initial draft — conveyor-routed connection model with per-building buffers.
- 2026-02-16: Cross-PRD alignment: Rewrote Turret Mount section (§4.11) from standalone building with ammo input port to wall-mounted model with wall network shared ammo pools per wave_threat_system.md and living PRD. Updated terminology, quick reference table, ammo pool references in Ammo Module and Storage sections, and worked example §6.3.
- 2026-02-16: Implementation status updated to reflect shipped v1 runtime parity for directional conveyors, splitter/merger behavior, storage shared pools, rotation-aware ports, and recipe pinning integration.
- 2026-02-17: Runtime policy update: production/storage I/O is side-agnostic; conveyors now expose explicit per-entity input/output directions configurable after placement; global inventory fallback removed from logistics/production flows.
