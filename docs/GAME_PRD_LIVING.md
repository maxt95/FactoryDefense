# Factory Defense - Living PRD

Last updated: 2026-02-16
Owner: Product + Engineering
Status: Active living document

## Purpose
This is the canonical, always-current product requirements document for Factory Defense.
Use this file to capture what the game is, what is in scope for v1, what is locked, and what has changed.
It is intentionally high level; linked PRDs provide detailed design and implementation specifics.

## Canonical Alignment Rule
- This file is the high-level source of truth. **Where individual PRDs conflict with each other, the locked decisions in this file take precedence.**
- `docs/prd/factory_economy.md` defines economy/combat balance and priorities. **Note:** its bootstrap assumptions (6 starter structures, 80 starting ammo, 20s grace period, build/wave phase model) are superseded by the locked decisions below and by `run_bootstrap_session_init.md` and `wave_threat_system.md`.
- `docs/prd/wave_threat_system.md` defines the authoritative v1 threat model (grace period, continuous trickle pressure, timed surge waves, wall-mounted turret model, wall ammo network, and enemy behavior priorities).
- `docs/prd/building_specifications.md` defines the conveyor-routed building/port/buffer model and supersedes older abstract logistics assumptions. **Note:** its turret mount section (standalone building with ammo port) is superseded by the wall-mounted turret model in `wave_threat_system.md`.
- `docs/prd/combat_rendering_vfx.md` defines projectile physics, enemy pathfinding, instanced GPU rendering, and VFX particle system architecture.
- `docs/prd/tech_tree_runtime.md` defines the tech tree runtime: Lab building, research flow, node effects, gating rules, and simulation integration. Includes 19 core tech nodes + 3 geology survey nodes (22 total).
- `docs/prd/ore_patches_resource_nodes.md` defines ore patch generation, depletion, renewal, reveal rings, and miner–patch binding. Authoritative for Ring 0 composition guarantees and richness distribution.
- `docs/prd/run_bootstrap_session_init.md` defines run lifecycle, bootstrap sequence, difficulty parameterization, map layout, and grace period. Authoritative for the HQ-only bootstrap model.
- `docs/prd/build_interaction_flow.md` defines build/rotate/demolish interaction model, inspect/build modes, conveyor drag-draw, and command flow from UI to simulation.
- `docs/WHITEBOX_ASSET_STRATEGY.md` defines the whitebox rendering path for early playable visuals.
- `docs/prd/asset_pipeline.md` defines the full DCC-to-runtime asset pipeline: interchange formats, texture strategy, LOD generation, memory/streaming budgets, and distribution packaging.

## Product Pillars
- Factory throughput directly powers survival.
- Combat outcomes are constrained by real production and logistics.
- Isometric strategy readability is prioritized over visual noise.
- Native Apple quality: macOS, iOS, iPadOS, Metal-first rendering, responsive UX.

## Core Fantasy
Build and optimize a factory that manufactures the exact resources consumed by defenses while surviving escalating enemy pressure.

## Target Platforms
- macOS
- iOS (iPhone)
- iPadOS

## Audience
- Midcore strategy players

## Locked Product Decisions
| Area | Decision |
|---|---|
| Mode | Single-player first, architecture ready for future co-op |
| Camera | Locked isometric |
| Session shape | Endless survival escalation in v1; extraction/meta conversion is deferred |
| Bootstrap | HQ-only start; player places all structures during the grace period using HQ storage resources |
| HQ | 2×2 entity, 500 HP, 24-slot storage with 4 bidirectional ports (output for resources, input for repair_kit delivery); run ends when HQ health reaches 0 |
| Grace period | Difficulty-scaled (Easy 180s / Normal 120s / Hard 60s); no enemies during this window |
| Grace skip | Disabled in v1 (no early-end command/button) |
| Waves | Continuous threat model: grace period → trickle pressure → timed surge waves; no separate raid subsystem |
| Map orientation | Fixed in v1: factory-west, spawn-east |
| Defense topology | Turrets mount on wall segments (1:1); wall networks carry ammo to turrets via shared pools; wall line defines defensive territory |
| Ore patches | Finite deposits with depletion; Ring 0 guarantees iron + copper + coal; outer rings revealed via geology survey tech |
| Progression | Resource + research tech tree unlocks (Lab building, item-cost research, gating and passive bonuses) |
| Visual target | Stylized 3D with cinematic fidelity |
| Terrain | Mostly flat grid with ramps |
| Input | Touch + keyboard/mouse first-class |

## Core Loop
1. Place initial structures during the grace period using starting resources from HQ storage.
2. Mine finite ore patches, process factory chains, and route items via conveyors.
3. Expand wall lines with mounted turrets while protecting logistics and supply lines.
4. Survive continuous trickle pressure plus timed wave surges using physically produced ammo delivered through wall networks.
5. Repair breaches and recover production when structures are damaged or destroyed.
6. Research tech to unlock advanced buildings, recipes, and ore ring reveals; reinvest in production, defense, and expansion as pressure escalates.

## Session Structure
- Boot phase: HQ placed at map center with difficulty-scaled starting resources in its storage buffer; Ring 0 ore patches (iron + copper + coal guaranteed) visible; difficulty-scaled grace period with no enemy spawns (Easy 180s / Normal 120s / Hard 60s).
- Orientation: fixed for v1 (factory-west / spawn-east) for deterministic readability and consistent tuning.
- Continuous pressure: trickle scouts begin immediately after grace period ends and persist for the rest of the run.
- Wave surges: timed attacks with inter-wave gap compression over time (base gap: Easy 120s / Normal 90s / Hard 60s, shrinking by 2s per wave to a floor).
- Endless escalation: hand-authored waves 1–8 transition to procedural budget-based composition (quadratic scaling: `budget(w) = 10 + 4w + floor(0.5w²)`).
- End condition: run ends when HQ entity health reaches 0. No win condition in v1.

## V1 Gameplay Truths
- The HQ is the only structure at tick 0; the player builds the entire factory and defense line from scratch during the grace period.
- HQ is a 2×2 entity with 500 HP and 24-slot storage; starting resources (difficulty-scaled) are placed in HQ storage. The run ends when HQ health reaches 0.
- Turrets mount on wall segments (1:1). Ammo reaches turrets through per-wall-network shared pools injected via conveyors. No ammo in the pool means no shots. Turrets are destroyed when their wall segment is destroyed.
- Structure placement is economy-constrained: build costs are paid from produced resources stored in building buffers or the HQ.
- Miners require ore patches (1:1 binding, cardinal adjacency). Ore extraction depletes patches; Ring 0 guarantees at least one patch each of iron, copper, and coal with varied richness.
- Production is recipe-driven and time-based per structure (not instant tick conversion).
- Logistics is conveyor-routed with per-building buffers, finite capacity, and backpressure.
- Power uses global supply/demand with uniform brownout scaling of production throughput.
- There are no build/wave phase gates in v1; building remains available during active threat. The threat model is continuous: grace period → trickle → surge waves.
- Enemies follow a shared flow field toward the HQ. They attack the nearest structure blocking their path. Enemy types have behavioral modifiers (raiders seek structures, breachers target walls, overseers buff nearby enemies). Artillery_bug is deferred to post-v1.
- Enemy damage is archetype-specific (swarmling=5, drone_scout=8, raider=12, breacher=15, overseer=10). Breachers deal 2× damage to walls. V1 enemy roster: 5 types.
- Waves are hand-authored for waves 1–8, with procedural quadratic-budget escalation for wave 9+.
- Research consumes real produced items and competes directly with build costs and ammo production. The Lab is a 2×2, 5-power building. Tech gates unlock buildings, recipes, upgrades, and passive bonuses.

## Canonical V1 Systems Model
### Simulation
- Deterministic fixed-step simulation at 20 Hz.
- Eight systems execute in stable order per tick: Command > Economy/Production > Conveyor > Tech > Wave > EnemyMovement > Combat > Projectile.
- Replay/snapshot determinism is a release-quality requirement.

### HQ and Run Lifecycle
- HQ is a 2×2 entity (500 HP, 24-slot storage, 4 bidirectional ports, 0 power draw) placed at map center during bootstrap.
- Starting resources are placed in HQ storage buffer (not a global inventory), scaled by difficulty.
- Run phases: initializing → gracePeriod → playing → gameOver. No win condition in v1.
- HQ cannot be passively repaired; only repair_kit deliveries via conveyors restore its health.

### Ore Patches and Mining
- Ore patches are 1×1 indestructible terrain features with finite ore of a single type (iron, copper, or coal).
- Patches are organized in concentric reveal rings (0–3) around the HQ; Ring 0 is always visible, outer rings require geology survey tech research.
- Ring 0 guarantees at least one patch each of iron, copper, and coal; richness varies by ring (inner rings poorer, outer rings richer).
- Miners bind 1:1 to patches via cardinal adjacency; extraction depletes the patch at 1 ore/sec (base rate).
- Depleted patches are replaced by renewal spawns during inter-wave gaps, biased toward map edges.

### Economy, Production, and Logistics
- Content JSON is authoritative for items, recipes, waves, turret definitions, and tech data.
- Buildings run allowed recipes with priority + optional recipe pinning override. Some recipes are gated behind tech research.
- Items physically move via directed conveyors, splitters, mergers, and storage hubs.
- Per-building input/output buffers are the primary inventory truth; global inventory is a computed aggregate for HUD display.

### Combat and Threat
- Turrets mount on wall segments (1:1). Each connected wall network has a shared ammo pool (capacity = segmentCount × 12). Conveyors inject ammo into wall networks at any segment. Turrets draw from their network's pool.
- Turret behavior is type-specific (ammo type, range, fire rate, damage). Four turret types: turret_mk1, turret_mk2, gattling_tower, plasma_sentinel.
- Threat model is continuous: difficulty-scaled grace period → trickle pressure → timed surge waves, with full-perimeter spawns and structure-targeting enemy behaviors.
- Enemies follow a shared flow field (BFS from HQ). They attack the nearest impassable structure blocking their path. Enemy-type modifiers: raiders seek non-wall structures, breachers deal 2× wall damage, artillery fires at range, overseers buff nearby enemies.
- Hand-authored waves 1–8 from `waves.json`; procedural waves 9+ use quadratic budget formula: `budget(w) = 10 + 4w + floor(0.5w²)`.
- When a wall segment is destroyed, turrets mounted on it are destroyed, the wall network may split, and the flow field rebuilds.

### Tech Tree
- Lab building (2×2, 5 power, 80 HP) performs research by consuming produced items and accumulating progress over time.
- 19 core tech nodes + 3 geology survey nodes across 5 tiers (root through Tier 4).
- Effects: building gates, recipe gates, upgrade gates, passive bonuses, mechanic unlocks.
- Research is command-driven (startResearch/cancelResearch) with 50% item refund on cancellation.
- Multiple Labs accelerate research: speed = 1.0 + (additionalLabCount × 0.5), scaled by power efficiency.

### Power
- Power plants generate global supply (12 per plant); production structures consume global demand.
- Efficiency is `min(1.0, supply / demand)`, scaling factory throughput and research speed.
- Turrets do not directly require power to fire in v1; power impacts defense through ammo production sustainability.

### Build Interaction
- Two interaction modes: Inspect (default) and Build (select-then-place from build menu).
- Buildings support 4-way rotation (0°/90°/180°/270°) controlling port orientation.
- Demolish returns 50% of build cost (rounded down per item). HQ cannot be demolished.
- Conveyor and wall drag-draw: fast multi-placement via drag gesture.
- Placement validation: bounds, occupancy, cost, tech gate, type-specific rules (miner adjacency, path blocking).

### UX
- Build/rotate/place/remove interactions are first-class on touch and keyboard/mouse.
- HUD must always surface resources, ammo stock, power headroom, wave timing, grace period countdown, and HQ health.
- Non-occluding critical warnings include low ammo, HQ critical, surge imminent, power shortage, and patch exhausted.

### Rendering and Visual Readability
- Locked isometric camera and readability-first battlefield presentation.
- Whitebox phase uses procedural 3D geometry and instanced rendering to make simulation state visibly legible before production art.
- Native Apple quality targets remain macOS, iOS, and iPadOS with responsive layouts and quality tiers.

### Distribution Strategy
- V1 ships all assets in the app bundle (procedural geometry, JSON content). No external downloads required.
- Post-v1: if app size exceeds 200 MB after production art is integrated, adopt **Background Assets / Managed Background Assets** framework (Apple's successor to legacy On-Demand Resources).
- Must disclose first-launch download sizes per App Review guidelines (§2.3.12).
- Reference: `docs/prd/asset_pipeline.md` §9.

## Technical Requirements (v1)
- Swift + MetalKit + full Xcode support.
- Deterministic fixed-step simulation (20 Hz).
- Render interpolation for smooth frame presentation.
- Data-driven content (JSON) with validation checks.
- Responsive behavior across aspect ratios and safe areas.
- Quality presets + dynamic resolution across device tiers.
- Asset pipeline designed for whitebox-first, production-art-ready transition (MeshProvider protocol, glTF interchange, ASTC compression, LOD generation).

## UX Requirements (v1)
- Playable with touch and keyboard/mouse.
- Build/rotate/place/remove/demolish must be first-class on all platforms.
- Conveyor and wall drag-draw for fast multi-placement.
- HUD must surface: resources, ammo stock, power headroom, wave/grace timer, HQ health, and research progress.
- Combat-critical notifications must avoid occluding core play area.
- Tech tree UI with locked/available/researching/unlocked node states and build menu gating indicators.

## Out of Scope (v1)
- Multiplayer networking transport/session implementation.
- Story campaign.
- Non-isometric camera modes.

## Success Criteria
- Deterministic replay stability for identical command streams.
- Ammo truth is enforced at runtime (no ammo in wall network pool -> turret cannot fire).
- Build cost validation is enforced in simulation (not UI-only). Tech gating blocks placement of locked structures.
- Recipe timing and per-structure progression produce expected throughput envelopes.
- Ore patch adjacency/depletion and logistics bottlenecks materially affect defense output.
- HQ-only bootstrap produces a playable first 3 minutes across all difficulty levels.
- Wall breach destroys mounted turrets and triggers flow field rebuild + enemy rerouting.
- Stable 60fps target in representative mid-tier scenes per platform preset.
- No safe-area/aspect-ratio blocking issues on iPhone, iPad split screen, macOS resize.

## Linked Execution Docs
- Systems implementation plan: `docs/GAME_SYSTEMS_PLAN.md`
- Factory & Economy PRD: `docs/prd/factory_economy.md`
- Building Specifications PRD: `docs/prd/building_specifications.md`
- Wave & Threat System PRD: `docs/prd/wave_threat_system.md`
- Combat, Rendering & VFX PRD: `docs/prd/combat_rendering_vfx.md`
- Tech Tree Runtime PRD: `docs/prd/tech_tree_runtime.md`
- Ore Patches & Resource Nodes PRD: `docs/prd/ore_patches_resource_nodes.md`
- Run Bootstrap & Session Init PRD: `docs/prd/run_bootstrap_session_init.md`
- Build Interaction Flow PRD: `docs/prd/build_interaction_flow.md`
- Whitebox Asset Strategy: `docs/WHITEBOX_ASSET_STRATEGY.md`
- Asset Pipeline PRD: `docs/prd/asset_pipeline.md`

## Change Control
When updating this file:
1. Keep locked decisions stable unless explicitly re-approved.
2. Add a dated entry in the changelog below.
3. If requirements change, also update linked implementation plans/tasks.

## Open Questions
- Extraction economy: exact conversion of run results into meta progression.
- Long-run scaling: when to introduce elite/flying/siege enemy variants.
- Should wave-survived rewards be explicit (currency/resources) or remain pressure-only progression?
- Maximum concurrent enemy cap by platform tier and quality preset (recommended: 500 per wave_threat_system.md).

## Cross-PRD Reconciliation Status
All individual PRDs have been updated to align with the locked decisions above (completed 2026-02-16):
- `factory_economy.md`: ~~Bootstrap, phase model, balance framework, wave formula, warnings, turret model~~ **Resolved.** Updated to HQ-only bootstrap, continuous threat model, difficulty-scaled resources, quadratic wave formula, wall-mounted turrets, deterministic enemy targeting.
- `building_specifications.md`: ~~Turret Mount section~~ **Resolved.** Rewritten for wall-mounted turret model with wall network ammo pools.
- `run_bootstrap_session_init.md`: ~~Ring 0 coal, richness, ore colors~~ **Resolved.** Coal guaranteed, richness varied, colors corrected.
- `build_interaction_flow.md`: ~~Ammo Module port count~~ **Resolved.** Fixed to 2 inputs per building_specifications.
- `combat_rendering_vfx.md`: ~~Turret implementation status~~ **Resolved.** Updated to Exists (Milestone 0). Raider targeting updated to deterministic.
- `asset_pipeline.md`: **New.** Covers DCC-to-runtime pipeline, texture strategy, LOD generation, memory/streaming, and distribution. Cross-referenced from WHITEBOX_ASSET_STRATEGY.md, combat_rendering_vfx.md, and ore_patches_resource_nodes.md.

## Changelog
- 2026-02-15: Added Factory & Economy PRD link.
- 2026-02-15: Added Tech Tree Runtime PRD link.
- 2026-02-16: Initialized living PRD from approved high-level product direction and implemented architecture baseline.
- 2026-02-16: Aligned high-level living PRD with economy/building/whitebox PRDs; set conveyor + per-building buffer model as canonical v1 logistics direction.
- 2026-02-16: Landed first-pass logistics runtime in simulation (structure input/output buffers, directed conveyor transfer/backpressure, local turret-ammo-first consumption with global fallback).
- 2026-02-16: Re-aligned living PRD threat model to `wave_threat_system.md` (continuous pressure, no separate raid subsystem, no build-phase gating).
- 2026-02-16: Major cross-PRD alignment pass. Resolved ~20 conflicts across individual PRDs. Locked decisions: HQ-only bootstrap (supersedes factory_economy 6-structure start), wall-mounted turrets with wall network ammo pools (supersedes building_specifications standalone turret), difficulty-scaled grace period 60–180s (supersedes factory_economy 20s), quadratic wave budget formula (supersedes factory_economy linear), Ring 0 guarantees iron+copper+coal with varied richness. Added HQ, Ore Patches, Tech Tree, and Build Interaction subsections to systems model. Added cross-PRD reconciliation tracker. Updated system execution order to 8 systems.
- 2026-02-16: Completed cross-PRD reconciliation. Updated all 5 individual PRDs to align with living PRD locked decisions: factory_economy (continuous model, HQ-only bootstrap, quadratic formula, wall-mounted turrets, deterministic targeting), building_specifications (wall-mounted turret rewrite), run_bootstrap_session_init (coal guarantee, varied richness, ore colors), build_interaction_flow (ammo module ports), combat_rendering_vfx (M0 status, deterministic targeting).
- 2026-02-16: Added Asset Pipeline PRD. Added distribution strategy subsection, asset pipeline technical requirement, and cross-PRD reference for asset_pipeline.md. Updated combat_rendering_vfx.md with TBDR optimization notes, iOS memory termination risk, and Metal storage mode conventions. Updated ore_patches_resource_nodes.md with production art material requirements. Updated WHITEBOX_ASSET_STRATEGY.md with production art pipeline preview section and glTF-first format decision.
- 2026-02-16: Landed bootstrap/session-init reconciliation in code: `WorldState.bootstrap(difficulty:seed:)`, `hq.json` + `difficulty.json` loading/validation, HQ entity + phase-based run lifecycle events (`runStarted`, `gracePeriodEnded`, `gameOver`), deterministic Ring 0 patch generation, and extraction UI/command removal for T0.
- 2026-02-16: Locked remaining bootstrap decisions: fixed map orientation (factory-west/spawn-east), grace-period skip disabled in v1, and current `hq.json` starting-resource tables retained as baseline pending telemetry tuning.
- 2026-02-16: Rebalanced HQ starting resources across all difficulties to include processed starter components (`plate_copper`, `plate_steel`, `gear`, `circuit`, `turret_core`) and higher initial wall/ammo budgets; updated PRDs and tests to match the new baseline.
