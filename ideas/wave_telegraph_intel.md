# PRD: Wave Telegraphs and Threat Intel

Status: Proposed v1 combat readability enhancement  
Owner: Product + Simulation + UI + Rendering  
Last updated: 2026-02-19

## Why This Is Needed Now
Current HUD provides a timer and a generic `surgeImminent` warning, but does not tell players what kind of surge is coming or where perimeter pressure will likely concentrate.

Because the game is logistics-coupled tower defense, players need a short, meaningful pre-surge planning window to reroute ammo, reinforce walls, or reposition build priorities.

## Current-State Ground Truth
- `WaveSystem` already schedules deterministic surge groups and spawn clusters.
- Surge activation is known before `waveStarted` and can be telegraphed without extra randomness.
- HUD currently exposes wave timing but not composition/intel context.
- Living PRD requires non-occluding critical notifications and continuous threat cadence.

## Goals
- Increase tactical clarity before surge starts.
- Keep pressure continuous (no build phase pause).
- Reuse deterministic surge data so replay stability is unchanged.
- Improve player reaction quality, not just reaction speed.

## Non-Goals
- No full enemy path line prediction.
- No exact spawn tile reveal.
- No pause-to-plan mode.

## Design Grounding From Existing Games
| Game | Proven Pattern | Adaptation For Factory Defense |
|---|---|---|
| They Are Billions | Wave countdown plus qualitative composition framing supports preparation. | Add concise surge composition tags (for example: breacher-heavy). |
| Riftbreaker | Directional threat hints let players reposition defenses efficiently. | Add ingress arc hints by perimeter quadrant from deterministic clusters. |
| Sanctum | Brief pre-wave intel increases agency without stopping game flow. | Keep short telegraph window during continuous simulation. |

## Player Experience Targets
- 10-15 seconds before each surge, the player sees what is coming in one readable line.
- The map briefly pings likely ingress quadrants so players can prioritize wall/ammo responses.
- The system helps decisions without removing uncertainty.

## Core Design

### 1. Telegraph Window
For surge waves only:
- Fire telegraph start at `nextWaveTick - leadTimeTicks`.
- Lead time is difficulty-scaled:
  - Easy: 15s
  - Normal: 12s
  - Hard: 9s

No change to actual wave cadence.

### 2. Composition Summary
Generate 1-2 compact tags from wave group mix:
- `swarmling-heavy`
- `raider-pressure`
- `breacher-risk`
- `overseer-support`
- `mixed-assault`

Tag generation rules are deterministic:
- Aggregate counts per archetype.
- Compute share and apply threshold rules.
- Resolve ties with deterministic precedence table.

Optional authored override in `waves.json` for hand-authored waves.

### 3. Ingress Hints
Expose likely pressure zones, not exact tiles:
- Quantize cluster entry points into perimeter sectors (N, E, S, W, optionally NE/NW/SE/SW if needed).
- Render 1-3 subtle arc pings for sectors with highest projected spawn volume.
- Fade out as wave begins.

### 4. Confidence Framing
- Authored waves: `Known threat profile` style descriptor.
- Procedural waves: `Estimated threat profile` style descriptor.

This communicates certainty level while preserving tension.

## Data Contract Changes

### A. Extend `difficulty.json`
Add telegraph lead seconds:

```json
{
  "normal": {
    "surgeTelegraphLeadSeconds": 12
  }
}
```

### B. Optional `waves.json` fields
For authored waves only:

```json
{
  "index": 5,
  "telegraphTags": ["breacher-risk", "raider-pressure"],
  "telegraphNote": "Fortification test"
}
```

Fallback behavior remains derived tags if fields are absent.

## Runtime Architecture Changes

### 1. Threat state extension (`SimulationTypes.swift`)
Add `WaveTelegraphState`:
- `active: Bool`
- `waveIndex: Int`
- `startsAtTick: UInt64`
- `endsAtTick: UInt64`
- `tags: [String]`
- `ingressSectors: [PerimeterSector]`
- `isEstimate: Bool`

Embed in `ThreatState`.

### 2. Event additions
Add `EventKind.waveTelegraphStarted` and optionally `EventKind.waveTelegraphEnded`.

### 3. Wave system integration (`Systems.swift`)
In `WaveSystem.update(...)`:
- when playing and no active wave:
  - check if within telegraph lead window.
  - compute and cache telegraph payload for next surge.
- on `waveStarted`, clear telegraph state.

### 4. Snapshot integration
Include telegraph state in snapshots for replay parity.

## UI and Rendering Integration

### Files
- `Sources/GameUI/HUDModels.swift`
- `Sources/GameUI/FixedHUDBar.swift`
- `Sources/GameRendering/WhiteboxRenderer.swift`
- `Sources/FactoryDefense/main.swift`

### Components
- Threat intel panel adjacent to existing wave timer.
- Sector ping overlays in map view (subtle color pulse).
- Optional short audio cue when telegraph begins.
- Existing `surgeImminent` warning remains as fallback; when telegraph is active it is upgraded to include telegraph payload instead of showing a parallel warning line.

Design constraints:
- Never overlap build cursor center area.
- Maintain readability on all safe-area layouts.

## Implementation Plan

### Phase 1: Simulation and content hooks
- Add telegraph fields to difficulty/content types and validators.
- Add telegraph state/events in simulation.
- Implement deterministic tag derivation and sector extraction.

### Phase 2: HUD and overlay
- Add threat intel panel + countdown.
- Add ingress sector pings.
- Hook telegraph start audio cue.

### Phase 3: telemetry and balancing
- Log player actions during telegraph window.
- Tune lead time and tag thresholds by difficulty.

### Phase 4: authored-wave polish
- Add custom tags/notes to hand-authored waves where derived labels are too generic.

## Test Strategy
- Unit tests for tag derivation and sector quantization.
- Wave timing tests: telegraph start tick is exact for each difficulty.
- Determinism tests: identical seed and command stream yields identical telegraph payloads.
- UI snapshot/readability tests for compact panel and arc overlays.

## Telemetry Plan
Track:
- `telegraphWindowsSeen`
- `playerActionsDuringTelegraph` (build/place/remove/rotate counts)
- `survivalRateAfterTelegraph`
- `accuracyOfIngressHint` (share of spawned enemies in hinted sectors)

Success target:
- More pre-surge corrective actions with better survival at same economy state.

## Risks and Mitigations
- Risk: telegraph trivializes waves.
  - Mitigation: keep short lead time and sector-level hints only.
- Risk: derived tags can mislabel edge compositions.
  - Mitigation: authored override support.
- Risk: extra UI noise.
  - Mitigation: single compact panel and soft map pings with fast decay.

## Acceptance Criteria
- Every surge emits a telegraph window per difficulty lead time settings.
- Threat intel panel shows composition + ingress hints without occlusion.
- Procedural wave telegraphs are deterministic and replay-stable.
- Player reaction metrics are captured and queryable in telemetry.

## Stretch Follow-Ups (Post v1 closure)
- Contextual recommendations (for example: "light ammo deficit likely").
- Enemy trait callouts when new archetypes are introduced post-v1.
- Co-op ping integration with telegraph sectors.
