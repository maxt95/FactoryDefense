# PRD: Bottleneck Alerts and Flow Inspector

Status: Proposed v1 UX + telemetry closure item  
Owner: Product + Simulation + UI  
Last updated: 2026-02-19

## Why This Is Needed Now
The simulation already contains rich failure signals (`notEnoughAmmo`, `patchExhausted`, power efficiency, queue backlog, structure damage telemetry), but player-facing UX still compresses this into a single top-priority warning banner.

This causes avoidable losses because players see that something is wrong, but not what to fix first.

## Current-State Ground Truth
- `HUDViewModel.build(...)` currently outputs one `WarningBanner` from a small fixed set.
- `ThreatTelemetry` already tracks:
  - `spawnedEnemiesByWave`
  - `queuedSpawnBacklog`
  - `structureDamageEvents`
  - `dryFireEvents`
- Economy runtime already has the data needed to classify starvation vs blockage:
  - input/output buffers
  - conveyor payloads
  - power headroom
  - ore patch exhaustion

## Goals
- Surface actionable, low-noise root-cause alerts during active play.
- Let players identify whether failure is production, logistics, power, ore, or defense.
- Keep all alerts deterministic and replay-compatible.
- Feed balancing by capturing bottleneck duration and severity over time.

## Non-Goals
- No auto-repair or auto-routing.
- No full logistics planner or blueprint recommender.
- No modal UI that interrupts combat.

## Design Grounding From Existing Games
| Game | Proven Pattern | Adaptation For Factory Defense |
|---|---|---|
| Factorio | Machine-level no-input/no-power/no-output states are explicit and immediate. | Per-structure status string and icon, sourced from runtime buffers. |
| Dyson Sphere Program | Throughput issues are diagnosable through compact flow and blockage cues. | Add compact alert strip with grouped counts by bottleneck type. |
| Mindustry | Minimal but clear status cues maintain pace during combat. | Prioritized non-occluding warnings with cooldown and dedupe. |

## Player Experience Targets
- During a surge, player immediately sees if turrets are dry because ammo production is starved, not because walls are breached.
- Selecting a structure shows one clear status phrase with root cause.
- Alert spam is controlled: one critical banner + compact grouped list, not dozens of popups.

## Core Design

### 1. Signal Taxonomy
Introduce explicit signal kinds:
- `ammoDryFire`
- `inputStarved`
- `outputBlocked`
- `powerShortage`
- `minerNoOre`
- `conveyorStall`
- `wallNetworkUnderfed`
- `surgeBacklogHigh`

Each signal has:
- `scope`: global, network, structure
- `severity`: info, warn, critical
- `firstTick` and `lastTick`
- optional `entityID` or `networkID`

### 2. Severity and Priority Rules
- Critical if it directly suppresses defense output during active threat.
- Warn if it causes sustained throughput loss but not immediate defense collapse.
- Info for short-lived transitions.

Priority order for top banner:
1. `ammoDryFire`
2. `powerShortage`
3. `wallNetworkUnderfed`
4. `minerNoOre`
5. `inputStarved`
6. `outputBlocked`
7. `conveyorStall`
8. `surgeBacklogHigh`

### 3. Dedupe and Hysteresis
- Activation threshold: signal must persist `N` ticks before display.
- Recovery threshold: signal must clear for `M` ticks before removal.
- Grouping: identical signal kinds roll up into one line with count.

Example:
- `12 miners idle (no ore)`
- `4 ammo modules starved (plate_iron)`

### 4. Inspector Integration
Object inspector gains a single deterministic status line and one detail line:
- `Status: Output blocked`
- `Detail: Output buffer 8/8 for 12.4s`

### 5. HUD Behavior
- Keep existing top banner as highest-severity callout.
- Add a compact alert strip under the banner with up to 4 grouped alerts.
- Keep placement cursor and center combat space unobstructed.

## Signal Detection Rules

### A. `ammoDryFire`
Source: `notEnoughAmmo` event + `ThreatTelemetry.dryFireEvents` delta.  
Escalate to critical when wave active and dry fire rate exceeds threshold.

### B. `inputStarved`
Structure has active recipe pin/selection, has output capacity, but missing required input for sustained window.

### C. `outputBlocked`
Structure output buffer at capacity while production progress can no longer flush.

### D. `powerShortage`
`powerDemand > powerAvailable` sustained beyond threshold.

### E. `minerNoOre`
Miner bound patch exhausted or no valid patch binding for sustained window.

### F. `conveyorStall`
Payload progress is stagnant across a segment chain beyond threshold.

### G. `wallNetworkUnderfed`
Network has active turrets and low ammo reserve relative to projected near-term consumption.

### H. `surgeBacklogHigh`
`queuedSpawnBacklog` remains above configured threshold while wave is active.

## Runtime Architecture Changes

### 1. Simulation state additions (`SimulationTypes.swift`)
- `BottleneckSignalKind`
- `BottleneckSignalState`
- `BottleneckTelemetry`

### 2. New system
Add `BottleneckSystem` near end of tick after economy, wave, and combat updates so it observes final state for the tick.

### 3. Event surface
Optional new event kind for UI transitions:
- `bottleneckSignalChanged`

### 4. Telemetry integration
- Add bottleneck summary to runtime telemetry export.
- Track per-kind active duration and transition counts.

## UI Integration Plan

### Files
- `Sources/GameUI/HUDModels.swift`
- `Sources/GameUI/FixedHUDBar.swift`
- `Sources/GameUI/WarningBannerView.swift`
- `Sources/FactoryDefense/main.swift` (overlay host wiring)
- `Sources/GameUI/ObjectInspectorBuilder.swift` (status lines)

### Additions
- Extend `HUDSnapshot` with grouped alert entries.
- Extend `WarningBanner` mapping from single heuristic to signal-backed source.
- Add `AlertStripView` component with deterministic ordering.

## Implementation Plan

### Phase 1: Signal model and detection
- Implement signal enums/state in simulation.
- Compute signals incrementally from existing state/events.
- Add hysteresis and dedupe logic.

### Phase 2: HUD and inspector surfaces
- Replace heuristic-only warning decision with signal-driven priority logic.
- Add grouped alert strip.
- Add per-entity status line in inspector.

### Phase 3: Telemetry and balancing
- Export signal durations and counts.
- Add tuning dashboard section for top bottlenecks in current run.

### Phase 4: Polish
- Cooldown tuning to reduce flicker.
- Color/accessibility pass for high-contrast readability.

## Test Strategy
- Unit tests for each signal rule with deterministic fixtures.
- Priority arbitration tests when multiple signals are active.
- Hysteresis tests to prevent one-tick flapping.
- Replay tests to verify identical alert timelines for identical seeds/commands.
- UI tests (where available) for non-occluding layout constraints.

## Telemetry Plan
Track per run:
- `signalActiveTicksByKind`
- `signalTransitionsByKind`
- `maxConcurrentSignals`
- `timeToResolveCriticalSignal`
- `dryFireBeforeAndAfterFixActions`

Primary success metric:
- Reduced time spent in unresolved critical ammo/power bottlenecks.

Secondary metric:
- Higher wave survival at equal economy throughput due to faster corrective actions.

## Risks and Mitigations
- Risk: too many alerts create noise.
  - Mitigation: strict grouping, top-4 strip cap, hysteresis.
- Risk: expensive per-tick scans on large bases.
  - Mitigation: derive from existing runtime deltas and event counters, cache structure-level states.
- Risk: misleading overlapping causes.
  - Mitigation: primary-cause precedence with detail line showing secondary constraints.

## Acceptance Criteria
- At least 8 bottleneck categories are surfaced with deterministic behavior.
- Top banner always reflects highest-severity active signal.
- Alert strip remains non-occluding on macOS/iOS/iPadOS safe areas.
- Replay determinism remains intact with signal system enabled.

## Stretch Follow-Ups (Post v1 closure)
- Click-to-focus on representative affected entity.
- Trend mini-graphs for ammo burn vs production rate.
- Per-network throughput heatmap toggle.
