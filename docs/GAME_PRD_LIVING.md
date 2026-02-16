# Factory Defense - Living PRD

Last updated: 2026-02-16
Owner: Product + Engineering
Status: Active living document

## Purpose
This is the canonical, always-current product requirements document for Factory Defense.
Use this file to capture what the game is, what is in scope for v1, what is locked, and what has changed.
It is intentionally high level; linked PRDs provide detailed design and implementation specifics.

## Canonical Alignment Rule
- This file is the high-level source of truth.
- `docs/prd/factory_economy.md` defines economy/combat balance and priorities.
- `docs/prd/building_specifications.md` defines the conveyor-routed building/port/buffer model and supersedes older abstract logistics assumptions.
- `docs/prd/combat_rendering_vfx.md` defines projectile physics, enemy pathfinding, instanced GPU rendering, and VFX particle system architecture.
- `docs/prd/tech_tree_runtime.md` defines the tech tree runtime: Lab building, research flow, node effects, gating rules, and simulation integration.
- `docs/prd/ore_patches_resource_nodes.md` defines ore patch generation, depletion, renewal, reveal rings, and miner–patch binding.
- `docs/WHITEBOX_ASSET_STRATEGY.md` defines the whitebox rendering path for early playable visuals.

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
| Session shape | Endless survival with milestone rewards + optional extraction |
| Waves | Timed wave cycles |
| Raids | Bounded RNG raids with cooldown windows |
| Progression | Resource + money tech tree unlocks |
| Visual target | Stylized 3D with cinematic fidelity |
| Terrain | Mostly flat grid with ramps |
| Input | Touch + keyboard/mouse first-class |

## Core Loop
1. Gather raw resources.
2. Process resources through factory chains.
3. Expand walls, turret mounts, and base footprint.
4. Survive waves and raids using physically produced ammo/power.
5. Bank milestone rewards and choose extract vs continue risk.
6. Spend rewards on permanent/unlock progression.

## Session Structure
- Boot phase: starter land, basic production chain, early defense.
- Build windows: low pressure optimization period.
- Wave windows: structured enemy attacks.
- Raid windows: bounded random threat spikes.
- Milestones: periodic safe bank checkpoints.
- End conditions: defeat or voluntary extraction.

## V1 Gameplay Truths
- Turrets consume real produced ammo; no ammo means no shots.
- Structure placement is economy-constrained: build costs are paid from produced resources (except starter bootstrap structures).
- Miners require ore patches, and ore extraction/depletion is part of run pressure.
- Production is recipe-driven and time-based per structure (not instant tick conversion).
- Logistics is conveyor-routed with per-building buffers, finite capacity, and backpressure.
- Power uses global supply/demand with uniform brownout scaling of production throughput.
- Enemies can threaten both base and critical structures, enabling power/factory failure cascades.
- Waves are timed and data-authored early, with procedural escalation later in endless survival.

## Canonical V1 Systems Model
### Simulation
- Deterministic fixed-step simulation at 20 Hz.
- Stable system execution order for commands, economy/production, threats, movement, combat, and projectiles.
- Replay/snapshot determinism is a release-quality requirement.

### Economy, Production, and Logistics
- Content JSON is authoritative for items, recipes, waves, turret definitions, and tech data.
- Buildings run allowed recipes with priority + optional recipe pinning override.
- Items physically move via directed conveyors, splitters, mergers, and storage hubs.
- Per-building input/output buffers are the primary inventory truth; global inventory is a computed aggregate for HUD and shared ammo fallback.

### Combat and Threat
- Turret behavior is type-specific (ammo type, range, fire rate, damage).
- Combat outcomes are directly coupled to factory throughput and ammo chain health.
- Threat model includes wave cadence, bounded raids, weak-side pressure, and structure-targeting enemy behaviors (not base-only pressure).

### Power
- Power plants generate global supply; production structures consume global demand.
- Efficiency is `min(1.0, supply / demand)`, scaling factory throughput.
- Turrets do not directly require power to fire in v1; power impacts defense through ammo production sustainability.

### UX
- Build/rotate/place/remove interactions are first-class on touch and keyboard/mouse.
- HUD must always surface resources, ammo, power headroom, wave timing, raid warnings, and milestone state.
- Non-occluding critical warnings include low ammo, base critical, raid imminent, and power shortage.

### Rendering and Visual Readability
- Locked isometric camera and readability-first battlefield presentation.
- Whitebox phase uses procedural 3D geometry and instanced rendering to make simulation state visibly legible before production art.
- Native Apple quality targets remain macOS, iOS, and iPadOS with responsive layouts and quality tiers.

## Technical Requirements (v1)
- Swift + MetalKit + full Xcode support.
- Deterministic fixed-step simulation (20 Hz).
- Render interpolation for smooth frame presentation.
- Data-driven content (JSON) with validation checks.
- Responsive behavior across aspect ratios and safe areas.
- Quality presets + dynamic resolution across device tiers.

## UX Requirements (v1)
- Playable with touch and keyboard/mouse.
- Build/rotate/place/remove must be first-class on all platforms.
- HUD must surface: resources, ammo stock, power headroom, wave timer, raid warning, milestones.
- Combat-critical notifications must avoid occluding core play area.

## Out of Scope (v1)
- Multiplayer networking transport/session implementation.
- Story campaign.
- Non-isometric camera modes.

## Success Criteria
- Deterministic replay stability for identical command streams.
- Ammo truth is enforced at runtime (no ammo -> no shots).
- Build cost validation is enforced in simulation (not UI-only).
- Recipe timing and per-structure progression produce expected throughput envelopes.
- Ore patch adjacency/depletion and logistics bottlenecks materially affect defense output.
- Stable 60fps target in representative mid-tier scenes per platform preset.
- No safe-area/aspect-ratio blocking issues on iPhone, iPad split screen, macOS resize.

## Linked Execution Docs
- Systems implementation plan: `docs/GAME_SYSTEMS_PLAN.md`
- Factory & Economy PRD: `docs/prd/factory_economy.md`
- Building Specifications PRD: `docs/prd/building_specifications.md`
- Combat, Rendering & VFX PRD: `docs/prd/combat_rendering_vfx.md`
- Tech Tree Runtime PRD: `docs/prd/tech_tree_runtime.md`
- Ore Patches & Resource Nodes PRD: `docs/prd/ore_patches_resource_nodes.md`
- Whitebox Asset Strategy: `docs/WHITEBOX_ASSET_STRATEGY.md`

## Change Control
When updating this file:
1. Keep locked decisions stable unless explicitly re-approved.
2. Add a dated entry in the changelog below.
3. If requirements change, also update linked implementation plans/tasks.

## Open Questions
- Extraction economy: exact conversion of run results into meta progression.
- Raid telegraphing: minimum warning window and UX treatment by difficulty.
- Long-run scaling: when to introduce elite/flying/siege enemy variants.
- Wave/build interaction: should build actions be unrestricted during active waves or gated by cost/time penalties?

## Changelog
- 2026-02-15: Added Factory & Economy PRD link.
- 2026-02-15: Added Tech Tree Runtime PRD link.
- 2026-02-16: Initialized living PRD from approved high-level product direction and implemented architecture baseline.
- 2026-02-16: Aligned high-level living PRD with economy/building/whitebox PRDs; set conveyor + per-building buffer model as canonical v1 logistics direction.
- 2026-02-16: Landed first-pass logistics runtime in simulation (structure input/output buffers, directed conveyor transfer/backpressure, local turret-ammo-first consumption with global fallback).
