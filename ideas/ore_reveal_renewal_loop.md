# PRD: Ore Ring Reveal and Renewal Loop

Status: Proposed v1 closure item  
Owner: Product + Simulation + UI  
Last updated: 2026-02-19

## Why This Is Needed Now
Current runtime already supports deterministic Ring 0 generation, miner-to-patch binding, finite depletion, and depletion events (`patchExhausted`, `minerIdled`). What is still missing is the full ore lifecycle promised in the living PRD: ring reveal progression and renewal spawning.

Without this, successful runs can still collapse into a resource dead-end once Ring 0 depletes, especially when the player survives pressure but cannot economically recover.

## Current-State Ground Truth
- Ring 0 patches are generated at bootstrap in `WorldState.bootstrap(...)`.
- Depletion is active in `EconomySystem.produceRawResources(...)` and emits events.
- `WaveSystem` already has clean inter-wave transitions (`waveCleared`, `waveEnded`) which are ideal hooks for renewal.
- PRD constraints are already locked in `docs/GAME_PRD_LIVING.md`:
  - Rings 0-3, geology-based reveal progression.
  - Renewal biased toward map edges.
  - Determinism is release-critical.

## Goals
- Complete the ore lifecycle promised in v1: reveal + depletion + renewal.
- Preserve expansion pressure without forcing unwinnable economic collapse.
- Keep the system deterministic and replay-stable.
- Surface ring status clearly in HUD and world overlays.

## Non-Goals
- No free-form fog-of-war exploration system.
- No new ore types for this slice.
- No random event economy (meteor crashes, loot crates, etc.).

## Design Grounding From Existing Games
| Game | Proven Pattern | Adaptation For Factory Defense |
|---|---|---|
| Factorio | Finite local resources force outward expansion and logistics re-architecture. | Ring reveals pace expansion and force conveyor/wall redesign as pressure grows. |
| Mindustry | Continuous pressure plus constrained resources creates tactical timing decisions. | Renewal during inter-wave windows creates rebuild opportunities without pausing combat model. |
| They Are Billions | Territory expansion under threat is a central survival skill test. | Ring unlocks create explicit expansion beats with risk/reward timing. |

## Player Experience Targets
- Early game: Ring 0 is enough to bootstrap, but depletion warning creates urgency.
- Mid game: player unlocks geology survey and commits to a new mining frontier.
- Late game: renewal keeps runs alive, but edge-biased spawns increase routing complexity and defense surface area.

## Core Design

### 1. Ring Progression Model
- Ring 0 is visible from tick 0.
- Rings 1-3 start hidden.
- Each ring transitions through states:
  - `locked`
  - `surveying`
  - `revealed`
- Ring unlock trigger is tied to geology tech nodes (`geology_survey_1/2/3`).

### 2. Survey Flow
- When a geology node completes, the target ring enters `surveying` with a deterministic timer.
- At timer completion:
  - all patches in that ring become visible/valid miner targets.
  - `ringRevealed` event is emitted.
- Survey timer values come from difficulty config so Hard keeps higher tempo.

### 3. Renewal Flow
- When a patch becomes exhausted, it enters a renewal queue.
- Queue is processed only during inter-wave gap windows (on or after `waveEnded`).
- Renewal spawn count per window is capped by difficulty settings.
- Spawn position selection is deterministic and constrained:
  - prefer revealed outer rings.
  - bias toward edge cells.
  - reject occupied/restricted cells.
  - respect min spacing from existing patches.

### 4. Spawn Validity Rules
A renewal candidate is valid only if:
- Tile is not in structure occupancy.
- Tile is not restricted by HQ moat/safety rules.
- Tile is not already an ore patch.
- Tile is not in the immediate wall breach hotspot radius (configurable safety radius).
- Min patch spacing is satisfied (Chebyshev).

### 5. Determinism Rules
- No wall-clock randomness.
- All reveal and renewal selections derive from:
  - `run.seed`
  - `ringIndex`
  - `waveIndex`
  - deterministic candidate order
- Replay command stream must generate identical patch timelines.

## Content and Data Contract Changes

### A. New `ore_rings.json`
Defines ring radii, density, richness weights, and renewal bias.

```json
{
  "rings": [
    { "index": 0, "minDistance": 0, "maxDistance": 6, "patchCount": { "easy": 7, "normal": 5, "hard": 3 } },
    { "index": 1, "minDistance": 7, "maxDistance": 14, "patchCount": { "easy": 8, "normal": 7, "hard": 6 } },
    { "index": 2, "minDistance": 15, "maxDistance": 22, "patchCount": { "easy": 10, "normal": 9, "hard": 8 } },
    { "index": 3, "minDistance": 23, "maxDistance": 32, "patchCount": { "easy": 8, "normal": 7, "hard": 6 } }
  ],
  "renewal": {
    "edgeBias": 0.75,
    "minSpacing": 3,
    "maxSpawnsPerGap": { "easy": 3, "normal": 2, "hard": 2 }
  }
}
```

### B. Extend `difficulty.json`
Add survey timings and renewal cadence knobs.

```json
{
  "normal": {
    "surveySecondsByRing": [0, 18, 24, 30],
    "renewalCooldownSeconds": 20,
    "renewalBatchCap": 2
  }
}
```

### C. Tech node alignment
Ensure `tech_nodes.json` includes geology survey nodes referenced by living PRD and `tech_tree_runtime.md`.

## Runtime Architecture Changes

### 1. `WorldState` additions (`Sources/GameSimulation/SimulationTypes.swift`)
- `oreLifecycle` state container:
  - `ringStates: [Int: RingVisibilityState]`
  - `activeSurveyByRing: [Int: UInt64]` (endsAtTick)
  - `renewalQueue: [Int]` (patch IDs)
  - `lastRenewalTick`

### 2. Event additions
Add new `EventKind` values:
- `ringSurveyStarted`
- `ringRevealed`
- `oreRenewalSpawned`

### 3. New simulation system
Add `OreLifecycleSystem` and place it after `WaveSystem` so it can react to wave boundary events and still update before combat/next economic consumption.

Responsibilities:
- Start surveys on tech unlock.
- Complete surveys when timers expire.
- Drain renewal queue under wave-gap rules.
- Emit lifecycle events.

### 4. Bootstrap integration
`WorldState.bootstrap(...)` initializes ring lifecycle state and preloads patch definitions for all rings while exposing only Ring 0.

### 5. UI integration
- `HUDModels.swift`: ring status + survey timer projection.
- `FixedHUDBar.swift`: compact ring strip (R0-R3 state).
- `WhiteboxRenderer.swift`: ring boundary and reveal pulse.

## Implementation Plan

### Phase 1: Data and validation
- Add `ore_rings.json` and content types in `GameContent`.
- Extend loader/validator for ring bounds, spacing, and renewal constraints.
- Add test vectors for invalid ring overlap and impossible configs.

### Phase 2: Simulation lifecycle
- Extend `WorldState` and snapshots with ore lifecycle state.
- Implement `OreLifecycleSystem` with deterministic survey + renewal processing.
- Emit new lifecycle events.

### Phase 3: UX and telemetry
- Add ring status to HUD.
- Add minimal map feedback for survey/reveal.
- Extend telemetry export with lifecycle counters.

### Phase 4: Balance pass
- Tune survey/renewal knobs per difficulty with repeatable scenario seeds.
- Validate that Hard remains constrained without hard-locking economy.

## Test Strategy
- Unit tests:
  - ring unlock starts survey at correct tick.
  - reveal occurs exactly at `surveyEndTick`.
  - renewal never spawns on occupied/restricted tiles.
- Determinism tests:
  - identical seed + commands => identical reveal ticks and renewal positions.
- Snapshot tests:
  - schema version bump with backward-compat guard.
- Integration tests:
  - run through wave 10 with forced depletion and ensure renewal queue drains.

## Telemetry Plan
Add counters to track whether the mechanic is solving real pain points:
- `depletedPatchesTotal`
- `renewalSpawnsTotal`
- `surveyCompletionsByRing`
- `minerIdleTicksNoOre`
- `timeToFirstMinerOnNewRing`

Target outcomes after tuning:
- Lower share of losses caused by prolonged no-ore starvation.
- Higher share of losses caused by tactical/combat mistakes rather than economic hard lock.

## Risks and Mitigations
- Risk: renewal trivializes ore management.
  - Mitigation: strict per-gap cap + edge bias + cooldown.
- Risk: ring reveal UI noise during combat.
  - Mitigation: short, low-occlusion notifications and optional map pulse toggle.
- Risk: snapshot/replay breakage due to new state.
  - Mitigation: explicit schema version bump and golden replay refresh.

## Acceptance Criteria
- Ring 1-3 reveal via geology unlock path is fully functional.
- Renewal happens only in allowed windows and never violates placement constraints.
- Identical run seed + command stream yields identical patch lifecycle.
- HUD communicates ring state and survey progress without obscuring core play.

## Stretch Follow-Ups (Post v1 closure)
- Ring-specific ore composition events (for late-game variety).
- Optional scouting pings that preview where next renewal is likely.
- Co-op ring assignment UX for 2-player expansion coordination.
