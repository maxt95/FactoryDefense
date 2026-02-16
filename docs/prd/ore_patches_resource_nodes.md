# Ore Patches & Resource Nodes PRD

**Version:** 1.0-draft
**Parent:** `docs/GAME_PRD_LIVING.md`
**Status:** Forward-looking v1 design
**Last updated:** 2026-02-16

> **Core truth:** Ore patches are the finite fuel of every run. They deplete, they shift, and they pull the player outward into increasingly dangerous territory. The factory can only consume what the ground provides.

**Companion docs:**
- [`factory_economy.md`](factory_economy.md) — production chain, resource items, miner build cost
- [`building_specifications.md`](building_specifications.md) — miner building spec (ports, buffers, adjacency)
- [`tech_tree_runtime.md`](tech_tree_runtime.md) — geology survey tech nodes that reveal patch rings

---

## Table of Contents

1. [Design Intent](#1-design-intent)
2. [Patch Fundamentals](#2-patch-fundamentals)
3. [Richness & Type Variance](#3-richness--type-variance)
4. [Map Generation & Reveal Rings](#4-map-generation--reveal-rings)
5. [Depletion & Renewal](#5-depletion--renewal)
6. [Miner–Patch Relationship](#6-minerpatch-relationship)
7. [Difficulty Scaling](#7-difficulty-scaling)
8. [Tech Tree Integration](#8-tech-tree-integration)
9. [Visual Feedback](#9-visual-feedback)
10. [Simulation Integration](#10-simulation-integration)
11. [Balance Framework](#11-balance-framework)
12. [Implementation Sequencing](#12-implementation-sequencing)
- [Appendix A: Ore Rarity & Distribution Tables](#appendix-a-ore-rarity--distribution-tables)
- [Appendix B: Implementation Priority Matrix](#appendix-b-implementation-priority-matrix)
- [Appendix C: Files Requiring Modification](#appendix-c-files-requiring-modification)

---

## Terminology

| Term | Definition |
|------|-----------|
| **Ore patch** | A 1x1 indestructible terrain feature containing finite ore of a single type |
| **Richness tier** | The total ore capacity of a patch: poor, normal, or rich |
| **Reveal ring** | A concentric distance band around the base core; patches in unrevealed rings are hidden |
| **Depletion** | The process of a miner extracting ore until the patch reaches zero remaining |
| **Renewal** | Between-wave spawning of new patches to replace depleted ones |
| **Rarity weight** | A per-ore-type value controlling how frequently that type appears in patch generation |
| **Visual stage** | One of 4 appearance states reflecting approximate remaining ore (full → partial → low → exhausted) |

---

## 1. Design Intent

### 1.1 The Expansion Driver

Ore patches are the primary force pulling the player outward from their base core. The production chain (factory_economy.md §3) consumes ore continuously, but the ground beneath the factory is finite. Every run follows an arc:

1. **Exploit** nearby starter patches to bootstrap production
2. **Research** geology survey tech to reveal distant, richer deposits
3. **Expand** miners and logistics to reach new patches
4. **Defend** the longer supply lines against escalating threats

Without ore patches as a finite, shifting resource, the factory becomes self-sustaining and the tension triangle collapses. Depletion is what keeps the player building, researching, and expanding — not just optimizing in place.

### 1.2 Pressure Curve

```
Ore availability
  ▲
  │  ████                          ← starter patches sustain early game
  │      ████                      ← ring 1 revealed, new patches available
  │          ██                    ← depletion starts outpacing reveals
  │            ████████            ← ring 2 revealed, rich patches found
  │                    ████        ← renewals supplement depleted patches
  │                        ██████ ← ring 3 + renewals sustain late game
  └──────────────────────────────→ Time (waves)
```

The player should never feel permanently resource-starved, but should always feel one step behind — needing to plan their next mining expansion before the current patches run dry.

### 1.3 Implementation Status

| Aspect | Status |
|--------|--------|
| Ore items (ore_iron, ore_copper, ore_coal) in `items.json` | Exists |
| Miner structure type in `SimulationTypes.swift` | Exists |
| Miner ore generation (global, no patches) in `EconomySystem` | Replaced — miner extraction is now patch-bound with finite depletion and output-buffer coupling |
| Ore patch entity/runtime type | Exists — `OrePatch` now includes miner binding state (`boundMinerID`) and exhaustion helper |
| Patch generation / map layout | Partial — Ring 0 deterministic placement exists; full ring reveal/renewal generation remains |
| Depletion tracking | Partial — `remainingOre` decrement and depletion events (`patchExhausted`, `minerIdled`) are implemented for current Ring 0 runtime |
| Reveal ring system | Does not exist |
| Renewal spawning | Does not exist |
| Geology survey tech nodes | Does not exist |

---

## 2. Patch Fundamentals

### 2.1 Definition

An ore patch is a **1x1 indestructible terrain feature** that:
- Occupies a single grid tile
- Contains a finite amount of a single ore type
- Cannot be destroyed by enemies (terrain, not entity)
- Cannot be built on (blocks structure placement on its tile)
- Can have exactly one miner placed adjacent to it

### 2.2 Properties

```
OrePatchDef:
  id:           PatchID           // deterministic per-run integer ID
  oreType:      ItemID            // "ore_iron", "ore_copper", "ore_coal", etc.
  richness:     RichnessTier      // .poor, .normal, .rich
  totalOre:     Int               // initial ore capacity (derived from richness + type)
  remainingOre: Int               // current ore remaining
  position:     GridPosition      // grid tile this patch occupies
  revealRing:   Int               // which ring this patch belongs to (0-3)
  isRevealed:   Bool              // whether the player can see this patch
  boundMinerID: EntityID?         // 1:1 miner binding (or nil)
  isExhausted:  Bool              // true when remainingOre reaches 0
  exhaustedAtTick: UInt64?        // first tick where remainingOre reached 0
  renewalProcessed: Bool          // true once this exhaustion has been queued for renewal
  visualStage:  PatchVisualStage  // .full, .partial, .low, .exhausted
```

### 2.3 Terrain Rules

- Patches are placed during map generation and renewal; the player cannot create or move them
- A patch tile is impassable for structure placement (player cannot build on it)
- Enemies path through/around patches normally (patches do not block movement)
- Patches exist independently of structures — destroying a nearby miner does not affect the patch

---

## 3. Richness & Type Variance

### 3.1 Richness Tiers

Three richness tiers determine the total ore a patch contains. Amounts **vary by ore type** to reflect natural scarcity — common ores yield larger deposits, scarce ores yield smaller ones.

| Richness | Iron (common) | Copper (uncommon) | Coal (scarce) |
|----------|--------------|-------------------|----------------|
| **Poor** | 300 | 200 | 150 |
| **Normal** | 500 | 400 | 300 |
| **Rich** | 800 | 650 | 500 |

### 3.2 Rarity Weights

Each ore type has a **rarity weight** that controls how frequently it appears in patch generation. This system is extensible — future ore types simply define their own rarity weight and richness table row.

| Ore Type | Rarity Weight | Approx. Distribution |
|----------|--------------|---------------------|
| `ore_iron` | 1.0 | ~50% of patches |
| `ore_copper` | 0.6 | ~30% of patches |
| `ore_coal` | 0.4 | ~20% of patches |

Distribution is computed as: `probability(type) = weight(type) / sum(all weights)`

For the current 3 ore types: iron = 1.0/2.0 = 50%, copper = 0.6/2.0 = 30%, coal = 0.4/2.0 = 20%.

### 3.3 Richness Distribution by Ring

Patches closer to the base core tend to be poorer. Expansion is rewarded with richer deposits.

| Ring | Poor % | Normal % | Rich % |
|------|--------|----------|--------|
| Ring 0 (starting) | 40% | 50% | 10% |
| Ring 1 | 20% | 50% | 30% |
| Ring 2 | 10% | 40% | 50% |
| Ring 3 | 0% | 30% | 70% |

### 3.4 Extensibility

Adding a new ore type (e.g., `ore_titanium`) requires:
1. Add item to `items.json` with `"kind": "raw"`
2. Add richness row to `ore_patches.json` (poor/normal/rich amounts)
3. Add rarity weight to `ore_patches.json`
4. Distribution percentages recompute automatically

---

## 4. Map Generation & Reveal Rings

### 4.1 Ring Definitions

The map is divided into concentric rings around the base building (the core anchor). Ring boundaries are measured in **grid tiles from the base anchor** (Chebyshev distance).

| Ring | Distance (tiles) | Visibility | Patch Count (Normal) |
|------|-----------------|------------|---------------------|
| Ring 0 | 0–6 | Always visible | 5 (difficulty-scaled) |
| Ring 1 | 7–14 | Geology Survey I | 6–8 |
| Ring 2 | 15–22 | Geology Survey II | 8–10 |
| Ring 3 | 23–32 | Geology Survey III | 6–8 |

**Total patches across all rings: ~25–31** (Normal difficulty).

### 4.2 Generation Algorithm

Patch placement runs once at map creation (new run start). All rings are generated upfront but only Ring 0 is initially revealed.

```
// Ring 0: deterministic starter perimeter around base building
ring0Count = ringPatchCount(0, difficulty) // Easy 7, Normal 5, Hard 3
guaranteedTypes = ["ore_iron", "ore_copper", "ore_coal"]

for oreType in guaranteedTypes:
  richness = weightedRandom(ringRichnessDistribution[0])
  position = randomValidPosition(
    ring: 0,
    distanceRange: 2...4,   // near starter perimeter
    minSpacing: 3,
    fallbackMinSpacing: 2
  )
  totalOre = richnessTables[oreType][richness]
  createPatch(oreType, richness, totalOre, position, ring: 0)

remainingRing0 = ring0Count - guaranteedTypes.count
for i in 0..<remainingRing0:
  oreType = weightedRandom(rarityWeights)
  richness = weightedRandom(ringRichnessDistribution[0])
  position = randomValidPosition(
    ring: 0,
    distanceRange: 4...6,   // outer starter perimeter
    minSpacing: 3,
    fallbackMinSpacing: 2
  )
  totalOre = richnessTables[oreType][richness]
  createPatch(oreType, richness, totalOre, position, ring: 0)

// Rings 1-3: standard generation
for each ring in [1, 2, 3]:
  patchCount = ringPatchCount(ring, difficulty)
  for i in 0..<patchCount:
    oreType   = weightedRandom(rarityWeights)
    richness  = weightedRandom(ringRichnessDistribution[ring])
    position  = randomValidPosition(ring, minSpacing: 3, fallbackMinSpacing: 2)
    totalOre  = richnessTables[oreType][richness]
    createPatch(oreType, richness, totalOre, position, ring)
```

**Placement constraints:**
- Default minimum 3 tiles spacing between any two patches (Chebyshev distance)
- Generation fallback may relax spacing to 2 tiles only when no valid position exists at spacing 3
- Cannot be placed on base building footprint tiles
- Cannot be placed on pre-placed structure tiles
- Ring 0 must guarantee at least 1 patch each of iron, copper, and coal on all difficulties
- Ring 0 guaranteed trio (iron/copper/coal) must be in distance 2...4 from base building anchor
- Remaining Ring 0 patches must be in distance 4...6 from base building anchor

### 4.3 Reveal Mechanics

Patches in unrevealed rings are **not visible** to the player — they don't appear on the map, cannot be selected, and miners cannot be placed adjacent to them. When a ring is revealed (via tech research), all patches in that ring become visible simultaneously.

The reveal is a discrete event: `SimEvent.ringRevealed(ring: Int)`. The renderer animates newly revealed patches fading in.

### 4.4 Fog of War (Simplified)

Ring-based visibility is a simplified fog of war. Unrevealed rings appear as darkened/grayed terrain. No per-tile fog — the entire ring reveals at once. This keeps the system simple while preserving the discovery feel.

---

## 5. Depletion & Renewal

### 5.1 Depletion Mechanics

A miner extracts **1 ore per second** (0.05 ore per tick at 20 Hz) from its adjacent patch. Depletion is tracked as an integer decrement on the patch's `remainingOre`.

```
Per tick (if miner is active and powered):
  minerExtractionRemainder += (1.0 * powerEfficiency * techBonuses) / 20.0
  while minerExtractionRemainder >= 1.0 and patch.remainingOre > 0:
    minerExtractionRemainder -= 1.0
    patch.remainingOre -= 1
  if patch.remainingOre == 0 and patch.exhaustedAtTick == nil:
    patch.exhaustedAtTick = currentTick
    patch.renewalProcessed = false
```

**Fractional accumulation:** Since the base rate is 1/sec and ticks are 20 Hz, the miner accumulates 0.05 ore per tick. When the fractional accumulator reaches ≥ 1.0, one integer ore is extracted and the accumulator carries the remainder. This matches the existing `addFractional` pattern in `EconomyState`.

### 5.2 Depletion Timeline (Normal Richness)

At base mining rate (1 ore/sec, no bonuses):

| Ore Type | Total Ore (Normal) | Time to Deplete | Approx Surge Waves (Normal, 90s base gap) |
|----------|-------------------|-----------------|-------------------------------------------|
| Iron | 500 | 8 min 20 sec | ~5-6 surge waves |
| Copper | 400 | 6 min 40 sec | ~4-5 surge waves |
| Coal | 300 | 5 min 00 sec | ~3-4 surge waves |

### 5.3 Exhaustion

When `remainingOre` reaches 0:
1. Patch enters `exhausted` visual stage
2. The attached miner **idles** — stops producing, stops consuming power
3. `SimEvent.patchExhausted(patchID, position)` emitted
4. The miner remains placed but non-functional; the player must **demolish** it (standard refund rules per factory_economy.md §6.4) and rebuild at a new patch
5. The exhausted patch remains on the map as terrain (visible but inert, not removable)

### 5.4 Renewal System

Depleted patches are replaced during **inter-wave gaps** (the period between surge waves in the continuous threat model). This prevents total resource starvation in long runs while maintaining expansion pressure.

**Renewal rules:**
- **Trigger:** At the start of each inter-wave gap (when a surge wave is cleared), the system enqueues every exhausted patch where `renewalProcessed == false`
- **Count:** One renewal patch spawn request is created per newly processed exhaustion (1:1 replacement)
- **Timing:** Renewals spawn at the start of the inter-wave gap. Trickle pressure continues normally during this period.
- **Ore type:** Renewal patches match the exhausted patch's ore type (iron replaces iron, etc.)
- **Richness:** Determined by the current highest-revealed ring's richness distribution
- **Location:** Weighted toward map edges with a minimum distance from existing active patches (see §5.5)
- **Hard mode skip policy:** On Hard, each queued request uses a deterministic 25% skip roll (`hash(runSeed, waveIndex, sourcePatchID, skipCount) % 100 < 25`)
- **Hard mode anti-starvation:** A request with `skipCount >= 2` must spawn the next time cap space is available (no skip roll)

### 5.5 Renewal Placement

```
candidatePositions = allValidTiles(withinRevealedRings)
  .filter { minDistance(from: existingActivePatches) >= 4 }
  .filter { minDistance(from: baseCore) >= 8 }

weights = candidatePositions.map { distanceFromCenter(position) }
// Higher distance = higher weight — biases toward edges

renewalPosition = weightedRandom(candidatePositions, weights)
```

This creates a gentle outward pull: renewal patches tend to appear further from the base than the patch they replaced, but occasionally spawn at moderate distances.

### 5.6 Renewal Cap

To prevent unbounded patch accumulation, renewals are capped:
- **Maximum active (non-exhausted) patches:** 20 (across all rings)
- If active patches are at the cap, typed renewal requests remain queued and spawn when active count drops below the cap
- This prevents the late game from having too many patches to defend

---

## 6. Miner–Patch Relationship

### 6.1 Adjacency Requirement

A miner must be placed on a tile **cardinally adjacent** (N/S/E/W) to an ore patch. Diagonal adjacency does not count.

```
Valid miner placements for patch at (5, 5):
  (4, 5) West   ✓
  (6, 5) East   ✓
  (5, 4) North  ✓
  (5, 6) South  ✓
  (4, 4) NW     ✗
  (6, 6) SE     ✗
```

### 6.2 One Miner Per Patch

Each patch supports **exactly one** miner. Placing a second miner adjacent to an already-mined patch is rejected by placement validation.

**Validation order:**
1. Target tile is unoccupied
2. Target tile is not an ore patch
3. At least one cardinally adjacent tile contains an unreserved ore patch
4. The adjacent patch does not already have a miner assigned

### 6.3 Miner–Patch Binding

When a miner is placed adjacent to a patch, a binding is created:
- `miner.boundPatchID = patch.id`
- `patch.boundMinerID = miner.structureID`

This binding is broken when:
- The miner is demolished by the player (patch remains, available for a new miner)
- The miner is destroyed by enemies (patch remains, available for a new miner)
- The patch is exhausted (miner idles, binding persists until player demolishes)

### 6.4 Miner Output Behavior

The miner's output behavior integrates with the existing logistics system (building_specifications.md §4.1):
- Miner has one **output port** (direction configurable via rotation)
- Extracted ore enters the miner's output buffer (capacity: 8 units)
- If a conveyor is connected, ore pushes into the conveyor system
- If no conveyor, ore falls back to the global inventory (current placeholder behavior, maintained for backward compatibility during logistics rollout)
- If the output buffer is full, the miner **stalls** — extraction pauses until buffer space opens (backpressure)

---

## 7. Difficulty Scaling

### 7.1 Starting Patch Count

The number of Ring 0 (initially visible) patches scales with difficulty:

| Difficulty | Ring 0 Patches | Guaranteed Types | Notes |
|------------|---------------|-----------------|-------|
| Easy | 7 | 3 iron, 2 copper, 2 coal | Comfortable surplus for learning |
| Normal | 5 | 2 iron, 2 copper, 1 coal | Balanced; player must prioritize |
| Hard | 3 | 1 iron, 1 copper, 1 coal | Bare minimum; immediate pressure |

### 7.2 Outer Ring Scaling

Rings 1–3 patch counts are **not** difficulty-scaled. The difficulty lever is how long the player must survive on Ring 0 alone before researching expansion.

### 7.3 Additional Difficulty Modifiers

| Parameter | Easy | Normal | Hard |
|-----------|------|--------|------|
| Ring 0 patch count | 7 | 5 | 3 |
| Renewal rate | 1.0× (immediate) | 1.0× | 0.75× (25% chance to skip) |
| Richness in Ring 0 | Biased normal/rich | Standard distribution | Biased poor/normal |
| Renewal skip policy | N/A | N/A | Deterministic skip roll with max 2 consecutive skips per request |

---

## 8. Tech Tree Integration

### 8.1 Geology Survey Branch

Three new tech nodes branch from `logistics_1`, forming the resource expansion path. This creates a meaningful choice: invest in logistics efficiency (conveyor_mk2, storage_bins) or resource access (geology surveys).

```
root
 └── logistics_1
      ├── conveyor_mk2 ──→ logistics_2
      ├── storage_bins  ──→ logistics_2
      └── geology_survey_1 ──→ geology_survey_2 ──→ geology_survey_3
```

### 8.2 Node Definitions

| Node ID | Tier | Prerequisites | Cost | Effect |
|---------|------|--------------|------|--------|
| `geology_survey_1` | 2 | `logistics_1` | 12 gear | Reveals Ring 1 patches |
| `geology_survey_2` | 3 | `geology_survey_1` | 18 plate_steel | Reveals Ring 2 patches |
| `geology_survey_3` | 4 | `geology_survey_2` | 14 circuit | Reveals Ring 3 patches |

### 8.3 Cost Rationale

- **geology_survey_1** costs gear (processed item, Tier 2 depth). Player needs smelting infrastructure to afford this. Expected unlock: wave 4–6.
- **geology_survey_2** costs plate_steel (requires advanced smelting). Represents mid-game investment. Expected unlock: wave 8–12.
- **geology_survey_3** costs circuits (requires electronics). Late-game unlock for the richest deposits. Expected unlock: wave 14+.

### 8.4 Passive Bonuses (Future Consideration)

The geology survey nodes could also provide passive bonuses in addition to reveals:
- Survey I: +10% mining speed
- Survey II: +5% ore per extraction (rounding up)
- Survey III: Renewal patches spawn 1 tier richer

These are **recommendations for balance tuning**, not locked requirements. The primary effect is always ring reveal.

---

## 9. Visual Feedback

### 9.1 Patch Visual Stages

Patches communicate remaining ore through **visual stages only** — no exact numbers are shown to the player. This creates an intuitive, glanceable system.

| Stage | Remaining Ore | Visual Description |
|-------|--------------|-------------------|
| **Full** | 75–100% | Bright, saturated patch color; full geometry height |
| **Partial** | 40–74% | Slightly desaturated; geometry shrinks ~20% height |
| **Low** | 1–39% | Desaturated, dim; geometry shrinks ~50% height; subtle pulse |
| **Exhausted** | 0% | Gray, flat; minimal geometry; no pulse |

### 9.2 Color by Ore Type

Patches are color-coded by ore type for instant identification at isometric distance:

| Ore Type | Patch Color | Hex (approx.) |
|----------|------------|---------------|
| Iron | Rust orange | `#B87333` |
| Copper | Teal green | `#2E8B7A` |
| Coal | Dark charcoal | `#3A3A3A` |

These colors are chosen to be distinguishable from each other and from the player structure palette (building_specifications.md uses cool blues/greens for structures).

### 9.3 Reveal Animation

When a ring is revealed via tech research:
- Patches in the newly revealed ring fade in over 1.5 seconds
- A subtle radial pulse effect emanates from the base core outward to the ring boundary
- Revealed patches start at full visual stage

### 9.4 Renewal Animation

When a renewal patch spawns during a build window:
- The patch "grows" from the ground over 1.0 second (scale 0 → 1)
- A brief particle burst marks the spawn location
- The HUD emits a notification: "New [ore type] deposit discovered"

### 9.5 Unrevealed Ring Rendering

Tiles in unrevealed rings render as **darkened terrain** with a subtle fog overlay. The ring boundary is not explicitly drawn — the fog edge implies it. This avoids HUD clutter while signaling that unexplored territory exists.

### 9.6 Production Art Material Requirements

When transitioning from whitebox to production art, ore patch assets need the following materials. These conventions align with the full asset pipeline documented in `docs/prd/asset_pipeline.md` §6.

**Textures per ore patch asset:**

| Texture | Color Space | Format | Resolution | Notes |
|---|---|---|---|---|
| Base color | sRGB | ASTC 6×6 | 256×256 max | Primary hue from ore colors below |
| Normal map | Linear | ASTC 4×4 | 256×256 max | Tangent-space, surface detail (cracks, crystalline facets) |
| ORM packed | Linear | ASTC 6×6 | 256×256 max | R=Occlusion, G=Roughness, B=Metallic (per `asset_pipeline.md` §6.2) |

**Base color hues by ore type** (matching the whitebox color palette from §9.2):
- Iron: rust orange (`#B87333`) as primary hue
- Copper: teal green (`#2E8B7A`) as primary hue
- Coal: dark charcoal (`#3A3A3A`) as primary hue

**Resolution rationale:** Ore patches are 1×1 tile footprint, appearing at 50–80px on screen at the isometric camera distance of 28. 256×256 is the maximum useful resolution; higher wastes memory with zero visual payoff.

**Visual state transitions (4 stages) without extra textures:**
- **Desaturation:** Driven by vertex color or shader uniform — the `richnessFraction` (remainingOre / totalOre) controls a lerp from full saturation (1.0) to grayscale (0.0). No additional textures needed per depletion stage.
- **Height scale:** Driven by shader uniform — `richnessFraction` controls Y-scale from full height (1.0) to flat (0.15), matching the visual stages defined in §9.1.

This approach means each ore type needs only **3 textures** (base color, normal, ORM) rather than 12 (3 textures × 4 stages). The shader handles all stage transitions dynamically.

---

## 10. Simulation Integration

### 10.1 New Types

```swift
// --- OrePatch types ---

public typealias PatchID = Int

public enum RichnessTier: String, Codable, Hashable, Sendable {
    case poor, normal, rich
}

public enum PatchVisualStage: String, Codable, Hashable, Sendable {
    case full       // 75-100%
    case partial    // 40-74%
    case low        // 1-39%
    case exhausted  // 0%
}

public struct OrePatch: Codable, Hashable, Identifiable, Sendable {
    public let id: PatchID
    public let oreType: String          // ItemID
    public let richness: RichnessTier
    public let totalOre: Int
    public var remainingOre: Int
    public let position: GridPosition
    public let revealRing: Int
    public var isRevealed: Bool
    public var boundMinerID: EntityID?
    public var exhaustedAtTick: UInt64?
    public var renewalProcessed: Bool

    public var isExhausted: Bool { remainingOre <= 0 }

    public var visualStage: PatchVisualStage {
        let ratio = Double(remainingOre) / Double(totalOre)
        switch ratio {
        case 0:            return .exhausted
        case ..<0.40:      return .low
        case ..<0.75:      return .partial
        default:           return .full
        }
    }
}

public struct RenewalRequest: Codable, Hashable, Sendable {
    public let sourcePatchID: PatchID
    public let oreType: String
    public let exhaustedAtTick: UInt64
    public var skipCount: Int
}

// --- Rarity & generation config ---

public struct OreTypeConfig: Codable, Hashable, Sendable {
    public let oreType: String          // ItemID
    public let rarityWeight: Double     // relative spawn frequency
    public let richness: [RichnessTier: Int]  // tier → total ore amount
}

public struct MapGenConfig: Codable, Hashable, Sendable {
    public let difficulty: Difficulty
    public let ringDefinitions: [RingDefinition]
    public let oreTypes: [OreTypeConfig]
    public let minPatchSpacing: Int     // Chebyshev distance
    public let maxActivePatches: Int    // renewal cap
}

public struct RingDefinition: Codable, Hashable, Sendable {
    public let ring: Int
    public let minDistance: Int          // from base core
    public let maxDistance: Int
    public let patchCount: ClosedRange<Int>
    public let richnessDistribution: [RichnessTier: Double]  // weights
}

public enum Difficulty: String, Codable, Hashable, Sendable {
    case easy, normal, hard
}
```

### 10.2 WorldState Extensions

```swift
extension WorldState {
    public var runSeed: UInt64               // deterministic run seed used for mapgen/replay
    public var orePatches: [OrePatch]         // all patches on the map
    public var nextPatchID: PatchID           // deterministic ID allocator
    public var revealedRings: Set<Int>        // which rings are visible (always includes 0)
    public var renewalQueue: [RenewalRequest] // pending renewals waiting for cap space
}
```

### 10.3 New Command Payloads

| Command | Parameters | Validation |
|---------|-----------|------------|
| `placeStructure` | build: `{ structure, position, targetPatchID? }` | If `structure == .miner`, `targetPatchID` is required and must reference an adjacent unreserved revealed patch; for non-miners, `targetPatchID` must be nil |
| `removeStructure` | entityID | Structure exists; if miner, unbind patch on removal |

`BuildRequest` extension for miner targeting:
```swift
public struct BuildRequest: Codable, Hashable, Sendable {
    public var structure: StructureType
    public var position: GridPosition
    public var targetPatchID: PatchID? // required only for .miner
}
```

### 10.4 New Events

| Event | Payload | Consumers |
|-------|---------|-----------|
| `patchExhausted` | patchID, position, oreType | HUD warning, visual stage update |
| `ringRevealed` | ring: Int, patchCount: Int | Reveal animation, HUD notification |
| `patchRenewed` | patchID, position, oreType, richness | Spawn animation, HUD notification |
| `minerIdled` | minerID, reason: .patchExhausted | HUD warning icon on miner |

### 10.5 System Execution

Ore patch extraction integrates into the existing **EconomySystem** (runs second in the system order). The patch-specific logic replaces the current placeholder miner code.

```
EconomySystem.update(state, context):
  // Phase 1: Miner extraction (NEW — replaces placeholder)
  for each miner with boundPatch:
    if miner is powered AND patch is not exhausted:
      accumulate fractional extraction
      if accumulated >= 1.0:
        patch.remainingOre -= 1
        push ore to miner output buffer (or global fallback)
      if patch.remainingOre == 0 and patch.exhaustedAtTick == nil:
        patch.exhaustedAtTick = state.tick
        patch.renewalProcessed = false
        emit patchExhausted event
    else if patch is exhausted:
      emit minerIdled event (once)

  // Phase 2: Recipe processing (existing)
  ...

  // Phase 3: Logistics / conveyor movement (existing)
  ...
```

**Renewal logic** runs in the **WaveSystem** (or a new MapSystem) at the start of each inter-wave gap (when `SimEvent.waveCleared` is emitted):
```
onInterWaveGapStart:
  for patch in orePatches
    .filter({ $0.isExhausted && !$0.renewalProcessed })
    .sorted(by: { $0.id < $1.id }):
    renewalQueue.append(
      RenewalRequest(sourcePatchID: patch.id, oreType: patch.oreType, exhaustedAtTick: patch.exhaustedAtTick ?? tick, skipCount: 0)
    )
    patch.renewalProcessed = true

  while !renewalQueue.isEmpty and activePatches < maxActivePatches:
    request = renewalQueue.removeFirst()

    if difficulty == .hard and request.skipCount < 2:
      roll = deterministicPercent(
        runSeed: state.runSeed,
        waveIndex: state.threat.waveIndex,
        patchID: request.sourcePatchID,
        skipCount: request.skipCount
      )
      if roll < 25:
        request.skipCount += 1
        renewalQueue.append(request)
        continue

    // Easy/Normal always spawn, Hard spawns on roll >= 25 or forced after 2 skips
    spawnRenewalPatch(matchType: request.oreType, richness, weightedEdgePosition)
```

### 10.6 Snapshot Compatibility

`OrePatch` array is added to `WorldState`. Existing snapshots without ore patches load with an empty array and fall back to the current global miner behavior. This maintains backward compatibility during migration.

---

## 11. Balance Framework

### 11.1 Economy Integration

The ore patch system replaces the current unlimited global ore generation. Key balance implications:

| Metric | Before (placeholder) | After (ore patches) |
|--------|---------------------|---------------------|
| Iron availability | Unlimited (minerCount × rate) | Finite per patch (300–800 per) |
| Expansion incentive | None | Strong (depletion + richer outer rings) |
| Tech tree relevance | Optional | Required for resource access |
| Difficulty lever | Wave scaling only | Wave scaling + resource scarcity |

### 11.2 Production Chain Demand Analysis

From factory_economy.md, steady-state consumption at mid-game (2 turrets firing):

| Resource | Consumption (per sec) | Patches Needed (Normal) | Depletion Time |
|----------|-----------------------|------------------------|----------------|
| Iron ore | ~2.0 (smelting + steel) | 2 miners | ~4 min per patch |
| Copper ore | ~1.0 (smelting + circuits) | 1 miner | ~6.5 min per patch |
| Coal | ~0.5 (steel + alloys) | 1 miner | ~10 min per patch |

On Normal difficulty with 5 starting patches (2 iron, 2 copper, 1 coal), the player can sustain basic production for approximately **4–6 minutes** before the first depletion event. This should occur around **wave 8–10**, creating pressure to have Geology Survey I researched by then.

### 11.3 Expansion Pacing

| Phase | Waves | Expected State |
|-------|-------|---------------|
| Early (bootstrap) | 1–4 | Mining Ring 0 patches. Building first Lab. |
| Early-mid (first pressure) | 5–7 | First depletion events. Researching Geology Survey I. |
| Mid (expansion) | 8–12 | Ring 1 revealed. Expanding miners outward. Geology Survey II in progress. |
| Mid-late (sustained) | 13–18 | Ring 2 revealed. Renewals supplementing depleted patches. Rich deposits fueling advanced production. |
| Late (endgame) | 19+ | Ring 3 revealed. All richness tiers accessible. Renewal loop sustaining indefinite play. |

### 11.4 Key Balance Ratios

| Ratio | Target | Reasoning |
|-------|--------|-----------|
| Starter patches : immediate demand | 1.5:1 | Slight surplus so the player isn't instantly starved |
| Depletion event timing | ~wave 8 (first) | Late enough to establish production, early enough to create urgency |
| Geology Survey I unlock | Wave 4–6 | Must be available before first depletion |
| Renewal rate vs. consumption | ~0.8:1 | Renewals don't fully replace consumption; player must use efficiency tech |
| Rich patch value : poor patch value | ~2.5:1 | Meaningful reward for expansion without trivializing logistics |

### 11.5 Difficulty Balance

| Difficulty | First Depletion | Geology Survey I Needed By | Run Pressure |
|------------|----------------|---------------------------|-------------|
| Easy | ~Wave 10–12 | Wave 10 (comfortable) | Low — player can experiment |
| Normal | ~Wave 8–10 | Wave 7 (moderate) | Medium — must plan ahead |
| Hard | ~Wave 5–6 | Wave 4 (urgent) | High — immediate prioritization |

---

## 12. Implementation Sequencing

### Phase 1: Data Layer (no simulation changes)

1. Define `OrePatch`, `PatchID`, `RenewalRequest`, `RichnessTier`, `OreTypeConfig` types in `SimulationTypes.swift`
2. Create `ore_patches.json` content file with richness tables and rarity weights
3. Add `ContentValidator` checks for ore patch config integrity
4. Add `orePatches` and `revealedRings` to `WorldState`
5. Ensure snapshot serialization includes ore patch state

### Phase 2: Map Generation

1. Implement `MapGenerator` that produces patch layouts from `MapGenConfig`
2. Ring-based placement with spacing constraints
3. Difficulty-scaled Ring 0 generation with 1:1:1 ore guarantees and starter perimeter around base building
4. Deterministic seeded RNG for replay compatibility
5. Replace `WorldState.bootstrap()` to start from base building + generated Ring 0 patches in a small perimeter

### Phase 3: Miner–Patch Binding

1. Add `boundPatchID` to miner entity, `boundMinerID` to `OrePatch`
2. Update `PlacementValidation` to enforce adjacency and 1:1 binding
3. Extend `BuildRequest` with optional `targetPatchID`; require it only for miner placement
4. Update demolish command to unbind patch on miner removal

### Phase 4: Depletion & Extraction

1. Replace placeholder miner code in `EconomySystem` with patch-based extraction
2. Implement fractional accumulation with integer decrement
3. Emit `patchExhausted` and `minerIdled` events
4. Miner idles when patch exhausted (stops production, stops power draw)

### Phase 5: Reveal & Renewal

1. Add geology survey tech nodes to `tech_nodes.json`
2. Implement ring reveal on tech completion (new effect type in `TechSystem`)
3. Implement renewal spawning in build window transition (including deterministic Hard skip policy + anti-starvation)
4. Renewal placement algorithm with edge-weighting
5. Emit `ringRevealed` and `patchRenewed` events

### Phase 6: Visual Integration

1. Add ore patch rendering to whitebox renderer (colored 1x1 tiles with height stages)
2. Implement visual stage transitions based on depletion percentage
3. Fog overlay for unrevealed rings
4. Reveal and renewal animations
5. HUD integration: depletion warnings, renewal notifications

---

## Appendix A: Ore Rarity & Distribution Tables

### A.1 Complete Richness Table

| Ore Type | Rarity | Poor | Normal | Rich | Depletion @1/sec (Normal) |
|----------|--------|------|--------|------|--------------------------|
| `ore_iron` | 1.0 (common) | 300 | 500 | 800 | 8m 20s |
| `ore_copper` | 0.6 (uncommon) | 200 | 400 | 650 | 6m 40s |
| `ore_coal` | 0.4 (scarce) | 150 | 300 | 500 | 5m 00s |

### A.2 Ring Patch Counts (Normal Difficulty)

| Ring | Min Patches | Max Patches | Dominant Richness |
|------|------------|------------|-------------------|
| 0 | 5 | 5 | Poor/Normal |
| 1 | 6 | 8 | Normal |
| 2 | 8 | 10 | Normal/Rich |
| 3 | 6 | 8 | Rich |
| **Total** | **25** | **31** | — |

### A.3 Starting Patch Guarantees by Difficulty

| Difficulty | Total | Iron | Copper | Coal |
|------------|-------|------|--------|------|
| Easy | 7 | 3 | 2 | 2 |
| Normal | 5 | 2 | 2 | 1 |
| Hard | 3 | 1 | 1 | 1 |

---

## Appendix B: Implementation Priority Matrix

| Item | Priority | Blocks |
|------|----------|--------|
| OrePatch types + WorldState integration | P0 | Everything |
| Map generation (Ring 0 only) | P0 | Miner binding |
| Miner–patch binding + placement validation | P0 | Extraction |
| Patch-based extraction replacing placeholder | P0 | Depletion |
| Depletion tracking + exhaustion events | P0 | Renewal, visual stages |
| Geology survey tech nodes | P1 | Ring reveal |
| Ring reveal system | P1 | Rings 1-3 access |
| Renewal spawning | P1 | Long-run sustainability |
| Difficulty scaling | P1 | Game modes |
| Whitebox patch rendering | P2 | Visual feedback |
| Visual stages + animations | P2 | Polish |
| Fog overlay for unrevealed rings | P2 | Visual clarity |
| HUD warnings + notifications | P2 | Player communication |

---

## Appendix C: Files Requiring Modification

### New Files

| File | Purpose |
|------|---------|
| `Content/bootstrap/ore_patches.json` | Richness tables, rarity weights, ring definitions |
| `Sources/GameSimulation/MapGenerator.swift` | Patch placement algorithm |

### Modified Files

| File | Changes |
|------|---------|
| `Sources/GameSimulation/SimulationTypes.swift` | Add OrePatch, RichnessTier, PatchVisualStage, OreTypeConfig, MapGenConfig, Difficulty; extend WorldState |
| `Sources/GameSimulation/Systems.swift` | Replace placeholder miner extraction in EconomySystem; add renewal logic |
| `Sources/GameSimulation/PlacementValidation.swift` | Enforce miner adjacency, 1:1 binding, patch tile blocking |
| `Sources/GameSimulation/EntityStore.swift` | Patch storage and query methods |
| `Sources/GameContent/ContentValidator.swift` | Validate ore_patches.json references and richness completeness |
| `Content/bootstrap/tech_nodes.json` | Add geology_survey_1/2/3 nodes branching from logistics_1 |
| `Sources/GameRendering/WhiteboxRenderer.swift` | Ore patch tile rendering, visual stages, fog overlay |
| `Sources/GameUI/ProductionUI.swift` | Miner placement targeting patch, depletion warnings |

---

## Changelog

| Date | Version | Changes |
|------|---------|---------|
| 2026-02-16 | 1.0-draft | Initial draft — collaborative design session |
| 2026-02-16 | 1.0-draft | Added §9.6 Production Art Material Requirements. Cross-referenced asset_pipeline.md for texture conventions and ORM packing. |
