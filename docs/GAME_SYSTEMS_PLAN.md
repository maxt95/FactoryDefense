# Factory Defense - Systems Build Plan

## Summary
Build a native Apple factory-defense game with:
- Simulation-first deterministic core
- Metal-first renderer with scalability + debug tools
- Shared modules that allow parallel development
- Single-player shipping scope with co-op-ready boundaries

## Repository Workstreams

## Workstream A - Project Foundation
- [x] Initialize modular Swift package layout (`GameSimulation`, `GameRendering`, `GameContent`, `GameUI`, `GamePlatform`).
- [x] Add deterministic prototype executable target.
- [x] Add baseline unit tests and CI-ready command set (`swift test`).
- [x] Add generated Xcode app targets (`FactoryDefense_iOS`, `FactoryDefense_iPadOS`, `FactoryDefense_macOS`).

## Workstream B - Simulation Core
- [x] Define `WorldState`, `PlayerCommand`, `SimEvent`, system protocol, and deterministic command ordering.
- [x] Implement fixed-step simulation engine (`20 Hz`).
- [x] Add snapshot/replay serialization shape.
- [x] Add interpolation bridge for render thread and frame timing capture.

## Workstream C - Factory Economy
- [x] Implement starter production loop: miners -> smelters -> ammo modules.
- [x] Implement power supply/demand efficiency scaling.
- [x] Couple ammo inventory to combat consumption.
- [x] Expand recipes, logistics networks, and machine throughput modifiers.

## Workstream D - Combat, Waves, AI
- [x] Implement timed wave cadence and bounded deterministic raid checks.
- [x] Implement milestone rewards and extraction command flow.
- [x] Add grid pathfinding scaffold with ramp/elevation support.
- [x] Add enemy behaviors, target selection layers, and baseline breach pressure tactics.

## Workstream E - Metal Renderer
- [x] Define render graph interfaces and pass nodes.
- [x] Add quality presets and debug visualization modes.
- [x] Add isometric camera math and renderer delegate shell.
- [x] Implement full pass execution (depth/shadows/opaque/transparent/post/UI).
- [x] Integrate GPU profiling checkpoints and runtime shader variants.

## Workstream F - UX and Input
- [x] Add unified input abstraction with command mapping hooks.
- [x] Add HUD view model for resources, waves, raids, and milestones.
- [x] Add responsive layout profile model for aspect/safe-area adaptation.
- [x] Implement production UI screens for build menu + tech tree interactions.

## Workstream G - Content, Balance, Feel
- [x] Add canonical content type definitions (recipes/turrets/waves/tech nodes/items/enemies).
- [x] Add validation checks: missing refs, recipe cycles, wave composition, unreachable tech nodes.
- [x] Author starter data pack and progression curves.
- [x] Add onboarding guidance and tuning dashboards.

## Workstream H - Quality and Tooling
- [x] Add determinism and economy coupling tests.
- [x] Add snapshot save/load test.
- [x] Add golden replay regression suite.
- [x] Add performance test scenes and telemetry pipeline.

## Dependency Rules
- Workstream A starts first.
- Workstream B foundations precede final C and D balancing.
- Workstream E can proceed in parallel with B after A exists.
- Workstream F depends on B/D interfaces.
- Workstream G content authoring starts when B/C/D schemas stabilize.
- Workstream H runs continuously.

## Acceptance Criteria (Current)
- `swift test` passes locally.
- Deterministic command streams produce matching world snapshots.
- Turret ammo consumption fails correctly when inventory is empty.
- Wave/raid cadence stays within bounded rules.
- Content validation catches broken references and graph issues.
- App targets compile via `xcodebuild -project FactoryDefense.xcodeproj` for:
  - `FactoryDefense_macOS` (standard local build)
  - `FactoryDefense_iOS` (`CODE_SIGNING_ALLOWED=NO` for teamless local/CI build)
  - `FactoryDefense_iPadOS` (`CODE_SIGNING_ALLOWED=NO` for teamless local/CI build)

## Remaining Optional Follow-Ups
- [ ] Configure Apple Developer Team signing for iOS/iPadOS local device deployment.
- [ ] Add CI workflow that runs `swift test` and unsigned iOS/iPadOS + macOS `xcodebuild` checks.
- [ ] Expand content balancing passes against telemetry outputs from `GamePlatform` performance scenarios.
