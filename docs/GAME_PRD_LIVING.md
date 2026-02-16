# Factory Defense - Living PRD

Last updated: 2026-02-16
Owner: Product + Engineering
Status: Active living document

## Purpose
This is the canonical, always-current product requirements document for Factory Defense.
Use this file to capture what the game is, what is in scope for v1, what is locked, and what has changed.

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

## Gameplay Requirements (v1)
- Turrets consume real ammo inventory produced by factory systems.
- Power shortages reduce both production and defense efficiency.
- Logistics bottlenecks measurably reduce defense throughput.
- Threat scaling considers wave index + base footprint + static defense density.
- Weak-side pressure events reduce pure turtling strategies.
- Tech progression unlocks advanced ammo, structures, and defense options.

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
- HUD must surface: resources, ammo stock, wave timer, raid warning, milestones.
- Combat-critical notifications must avoid occluding core play area.

## Out of Scope (v1)
- Multiplayer networking transport/session implementation.
- Story campaign.
- Non-isometric camera modes.

## Success Criteria
- Deterministic replay stability for identical command streams.
- Ammo truth is enforced at runtime (no ammo -> no shots).
- Stable 60fps target in representative mid-tier scenes per platform preset.
- No safe-area/aspect-ratio blocking issues on iPhone, iPad split screen, macOS resize.

## Linked Execution Docs
- Systems implementation plan: `/Users/maxconrad/Workspace/factory-defense/docs/GAME_SYSTEMS_PLAN.md`
- Factory & Economy PRD: `docs/prd/factory_economy.md`
- Building Specifications PRD: `docs/prd/building_specifications.md`

## Change Control
When updating this file:
1. Keep locked decisions stable unless explicitly re-approved.
2. Add a dated entry in the changelog below.
3. If requirements change, also update linked implementation plans/tasks.

## Open Questions
- Extraction economy: exact conversion of run results into meta progression.
- Raid telegraphing: minimum warning window and UX treatment by difficulty.
- Long-run scaling: when to introduce elite/flying/siege enemy variants.

## Changelog
- 2026-02-15: Added Factory & Economy PRD link.
- 2026-02-16: Initialized living PRD from approved high-level product direction and implemented architecture baseline.
