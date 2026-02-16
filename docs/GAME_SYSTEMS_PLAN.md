# Factory Defense - Systems Build Plan

Last updated: 2026-02-16
Owner: Product + Engineering
Status: Active execution plan (aligned to living PRD + economy/building PRDs)

## Summary
This plan tracks implementation status against the canonical v1 product direction:
- Deterministic simulation-first architecture at 20 Hz.
- Factory/combat coupling where production truth drives survival.
- Conveyor-routed logistics with per-building buffers and backpressure.
- Isometric Apple-native presentation with whitebox-first rendering path.

## Status Legend
- `[x]` complete and aligned with current PRD direction
- `[~]` partially complete / scaffold exists but not PRD-complete
- `[ ]` not started or materially incomplete

## Current Alignment Snapshot
### Foundation and architecture
- `[x]` Modular package layout and app targets exist.
- `[x]` Deterministic command loop, world state, events, snapshots, and replay scaffolding exist.
- `[x]` Content JSON schemas and validation pipeline exist for core data packs.

### Gameplay truth
- `[x]` Ammo truth exists (`no ammo -> no shot`) with per-turret ammo/range/fire-rate/damage differentiation.
- `[~]` Economy loop is recipe-driven with per-structure timing/progress for smelter/assembler/ammo-module/miner, plus first-pass structure buffers/conveyor backpressure and miner->ore-patch extraction/depletion; full ore lifecycle (reveal/renewal) and full port/filter model remain follow-up.
- `[x]` Build cost enforcement is simulation-authoritative.
- `[~]` Run bootstrap/session init is partially aligned: HQ-only bootstrap, difficulty+seed params, phase lifecycle events, extraction UI removal, deterministic Ring 0 patch generation, miner adjacency/binding + patch depletion events, and end-of-run summary flow are in; reveal/renewal rings remain follow-up.
- `[~]` Ore patch adjacency/depletion is now implemented for Ring 0 runtime; structure-targeting threat pressure remains incomplete.

### Rendering truth
- `[~]` Render graph scaffolding exists, but whitebox geometry draw path is still incomplete.

## Milestone Plan
### Milestone 0 - P0 Gameplay Truth (Completed)
Goal: make the simulation obey core v1 rules from `docs/GAME_PRD_LIVING.md` and `docs/prd/factory_economy.md`.

- [x] Enforce build costs in simulation command handling (not UI-only).
- [x] Wire per-turret definitions into combat (`ammo type`, `range`, `fire rate`, `damage`).
- [x] Move production execution to recipe-driven behavior from content data.
- [x] Implement missing production chains (`gear`, `wall_kit`, `turret_core`, `ammo_plasma`).
- [x] Add acceptance tests for cost enforcement + turret ammo truth across turret variants.

Exit criteria:
- Placing non-bootstrap structures consumes required resources.
- Distinct turret types consume the correct ammo and respect stat differences.
- Production output matches recipe expectations (including missing chains now active).

### Milestone 1 - P1 Factory and Threat Reality (Current Top Priority)
Goal: complete the first fully legible factory-defense vertical slice.

- [x] Add ore patch/resource node entities and miner adjacency requirements (Ring 0 generation + miner binding/adjacency + placement validation implemented).
- [~] Add ore depletion tracking and related simulation events/telemetry (depletion + `patchExhausted`/`minerIdled` events implemented; telemetry/dashboard surfacing remains).
- [x] Implement per-structure recipe timing/progress (smelter/assembler/ammo module + miner extraction timing implemented).
- [ ] Implement wave composition from `waves.json` for authored waves.
- [ ] Add procedural wave generation policy for post-authored endless waves.
- [ ] Add enemy structure-targeting behaviors (raider/breacher/artillery priorities).
- [~] Add storage capacity limits and output-blocked behavior.
- [ ] Add remove/refund command flow.

Exit criteria:
- Early waves are data-authored and reproducible from content.
- Factory bottlenecks (ore, timing, storage, power) materially change combat outcomes.
- Enemies can break production lines, causing recoverable or fatal cascades.

### Milestone 2 - P1/P2 Logistics Model Completion
Goal: align runtime logistics with `docs/prd/building_specifications.md`.

- [~] Add building port definitions and runtime input/output buffers.
- [~] Add directed conveyor runtime with progress, transfer, and backpressure.
- [ ] Add splitter and merger runtime behavior.
- [ ] Add storage as shared-pool logistics hub with multi-port behavior.
- [ ] Add recipe pinning and building rotation command support.
- [~] Update combat ammo draw order (local turret buffer first, logical pool fallback).

Exit criteria:
- Item movement is visible and physically constrained by conveyor network design.
- Backpressure/starvation/output-blocked states are reproducible and surfaced.
- Turret sustainability can be improved by direct-feed logistics topology.

### Milestone 3 - Whitebox Visual Readability
Goal: render simulation state clearly in-game before production art.

- [ ] Complete render infrastructure for real draw calls (pipeline state, descriptors, instance buffers).
- [ ] Implement procedural whitebox mesh primitives and asset catalog.
- [ ] Add instanced rendering by mesh groups with stable performance characteristics.
- [ ] Apply color coding for structures/enemies/projectiles and core debug overlays.

Exit criteria:
- Live simulation entities are visible as color-coded whitebox geometry.
- Readability supports tuning of factory and combat behavior.

### Milestone 4 - UX, Telemetry, and Balance Closure
Goal: ship-ready UX and balancing workflow for v1 scope.

- [ ] Surface build/wave mode distinctions and non-occluding critical warnings.
- [ ] Surface power headroom, inventory pressure, and ammo depletion trends in HUD.
- [ ] Add bottleneck detection signals (starved/blocked/underpowered/no-ore states).
- [ ] Add CI checks for `swift test` + unsigned iOS/iPadOS/macOS builds.
- [ ] Extend tuning dashboards and automated balance telemetry runs.

Exit criteria:
- UX communicates actionable bottlenecks during pressure windows.
- Balance iteration is measurable via repeatable telemetry scenarios.

## Workstream View (Updated)
### Workstream A - Project Foundation
- [x] Module layout and executable/app target setup.
- [x] Baseline test harness and local build commands.
- [~] CI automation for full platform build/test matrix.

### Workstream B - Simulation Core
- [x] Deterministic tick engine, command ordering, events, snapshots.
- [~] Snapshot schema extensions required for buffer/conveyor runtime model.

### Workstream C - Factory Economy and Logistics
- [~] Starter production loop and power scaling exist.
- [~] Recipe-timed, per-structure production model exists; output buffering/local-input consumption are wired, and miner extraction now binds to adjacent ore patches with finite depletion.
- [~] Conveyor-routed runtime exists for directed transfer + backpressure on standard conveyors; splitter/merger/storage hub behavior remains.

### Workstream D - Combat, Waves, AI
- [~] Grace period + trickle + compressed wave cadence exists (still formula-spawned; not yet authored-wave driven).
- [x] Per-turret stat and ammo differentiation.
- [ ] Authored-wave consumption from `waves.json` + endless procedural continuation.
- [ ] Structure-targeting enemy behaviors and cascade pressure.

### Workstream E - Metal Renderer
- [~] Render graph/debug scaffolding exists.
- [ ] Whitebox geometry draw path and instanced entity rendering.

### Workstream F - UX and Input
- [~] Input abstraction and baseline HUD models exist.
- [ ] Build/remove/rotate/pin interactions fully aligned with simulation rules.
- [ ] Runtime warning and bottleneck surfaces fully integrated into play view.

### Workstream G - Content, Balance, Feel
- [x] Core content files and validators exist.
- [~] Runtime systems need to consume JSON as authoritative behavior source.
- [ ] Balance automation and ammo headroom analytics.

### Workstream H - Quality and Tooling
- [x] Determinism/golden replay/perf scaffolding exists.
- [~] Milestone acceptance tests added for P0 gameplay truth; P1 criteria remain.

## Dependency Rules (Current)
- Milestone 0 must complete before deep balancing claims are considered valid.
- Milestone 1 depends on Milestone 0 simulation truth.
- Milestone 2 can run partly in parallel with Milestone 1 but must converge before final tuning.
- Milestone 3 can progress in parallel once renderer integration interfaces are stable.
- Milestone 4 runs continuously, but final closure depends on 0-3.

## Acceptance Criteria (Current Plan)
- `swift test` passes locally.
- Deterministic replay remains stable after gameplay-truth refactors.
- Build costs, ammo truth, and recipe-driven production are simulation-enforced.
- Author-time data (`recipes.json`, `turrets.json`, `hq.json`, `difficulty.json`) drives runtime behavior for core loops; `waves.json` authored consumption remains in progress.
- Whitebox rendering displays active simulation entities and supports tuning readability.
- App targets compile via `xcodebuild -project FactoryDefense.xcodeproj` for:
  - `FactoryDefense_macOS`
  - `FactoryDefense_iOS` (`CODE_SIGNING_ALLOWED=NO`)
  - `FactoryDefense_iPadOS` (`CODE_SIGNING_ALLOWED=NO`)

## Immediate Next Actions
- [ ] Expand logistics from first-pass eastward lanes to full port model (filters, orientation/rotation, storage hub semantics).
- [ ] Move WaveSystem from formula spawning to `waves.json` authored waves (1-8) with deterministic scheduling.
- [ ] Implement structure-targeting enemy behaviors to create production-line cascade pressure.
- [ ] Implement ore reveal/renewal lifecycle (geology survey unlocks, ring reveal state, renewal spawn policy) on top of current Ring 0 depletion runtime.
