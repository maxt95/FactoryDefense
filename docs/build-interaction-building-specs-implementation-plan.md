# Implementation Plan: Build Interaction Flow + Building Specifications (Full PRD Parity, Clean Break)

## Brief Summary
- Objective: fully implement `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/docs/prd/build_interaction_flow.md` and `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/docs/prd/building_specifications.md` across simulation, content, rendering, and UI.
- Strategy: clean-break refactor with no legacy snapshot compatibility; rebuild logistics/runtime interfaces to strict PRD semantics.
- Platform scope: macOS, iOS, iPadOS, and CLI gameplay root all reach behavior parity via a shared gameplay interaction module.
- Baseline gate: current `swift test` is green (72 tests) on February 16, 2026.

## Implementation Status (2026-02-16)
- Completed in this delivery:
  - Public API/type expansion in simulation (`Rotation`, `CardinalDirection`, `BuildRequest.rotation`, new command payloads, `structureRemoved`, richer placement rejection metadata).
  - `StructureType` expansion (`splitter`, `merger`) across simulation/UI/rendering exhaustiveness paths.
  - CommandSystem support for `removeStructure`, `placeConveyor`, `rotateBuilding`, `pinRecipe`.
  - Immediate demolish semantics with 50% floor refund, HQ removal rejection, path-safety rejection, deterministic wall/turret coupled cleanup.
  - Snapshot schema break (`schemaVersion = 2`) and explicit legacy snapshot rejection.
  - Content schema additions (`BuildingDef`, `PortDef`, `ItemFilter`) and authoritative `Content/bootstrap/buildings.json`.
  - Building validation for canonical constraints (including storage/power-plant 1x1 and storage power draw 0).
  - Directional conveyor transfer across all four facings with belt-node-aware handoff.
  - Splitter output alternation and merger alternating input pull runtime state.
  - Storage shared-pool runtime (`storageSharedPoolByEntity`) using content-defined bidirectional ports.
  - Content-driven port transfer validation from `buildings.json` (input/output side resolution by rotation + per-port item filters).
  - Removed logistics transport fallback to global inventory; produced items remain in routed buffers/pools until physically consumed.
  - `GameRuntimeController` command helper expansion (`placeConveyor`, `rotateBuilding`, `pinRecipe`, `removeStructure`) and rotation-aware place APIs for shared platform wiring.
  - Golden replay fingerprint regeneration and new command/snapshot/removal tests.
- Still in progress / remaining for parity:
  - Shared cross-platform gameplay interaction module + drag-draw parity + canonical rejection UX timing.

## Locked Decisions
1. Scope: full PRD parity for both target PRDs.
2. Refactor style: clean break (no compatibility fallback behavior in runtime logic).
3. Platform parity: all targets required in same delivery.
4. Demolish timing: immediate removal + immediate refund on confirm.
5. UI architecture: shared gameplay module with thin per-platform wrappers.
6. Snapshot/replay compatibility: break old snapshot JSON; introduce a new schema version and regenerate goldens.

## Public API / Interface / Type Changes
1. In `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Sources/GameSimulation/SimulationTypes.swift`, add `Rotation` (`north/east/south/west`) and `CardinalDirection`.
2. In `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Sources/GameSimulation/SimulationTypes.swift`, change `BuildRequest` to `{ structure, position, rotation, targetPatchID }`.
3. In `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Sources/GameSimulation/SimulationTypes.swift`, extend `StructureType` with `.splitter` and `.merger`.
4. In `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Sources/GameSimulation/SimulationTypes.swift`, extend `CommandPayload` with `.removeStructure(entityID:)`, `.placeConveyor(position:direction:)`, `.rotateBuilding(entityID:)`, `.pinRecipe(entityID:recipeID:)`.
5. In `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Sources/GameSimulation/SimulationTypes.swift`, extend `EventKind` + `SimEvent` usage with `structureRemoved` and richer `placementRejected` reason encoding.
6. In `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Sources/GameContent/ContentTypes.swift`, add `BuildingDef`, `PortDef`, `ItemFilter`, and direction-aware port schema.
7. In `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Sources/GameContent/ContentLoader.swift` and `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Sources/GameContent/ContentValidator.swift`, load/validate `buildings.json` and enforce PRD canonical stats/footprints/power.
8. In `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Sources/GameSimulation/SimulationTypes.swift`, replace coarse logistics state with directional port buffers plus conveyor node state and recipe pinning state.
9. In `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Sources/GamePlatform/InputAbstraction.swift`, add rotate, cancel build, confirm demolish, and drag-draw gestures.
10. In `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Sources/GamePlatform/SnapshotStore.swift` + snapshot model, add schema version marker and reject legacy pre-refactor snapshots explicitly.

## Implementation Phases
1. Phase 1: Content and schema foundation.
- Add `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Content/bootstrap/buildings.json` as authoritative building definitions.
- Align canonical values to PRDs, including 1x1 footprint for storage/power plant and storage power draw 0.
- Wire loader and validator; fail fast on missing ports, invalid filters, or PRD-stat drift.
- Add content validation tests for building defs, port filters, and per-structure constraints.

2. Phase 2: Simulation model refactor (clean break core).
- Replace `EconomyState` logistics dictionaries with direction-aware per-port input/output buffers and internal/shared storage pools.
- Add rotation to entity runtime placement metadata.
- Add splitter/merger runtime state.
- Remove east-only conveyor assumptions and adopt direction-driven handoff.
- Update world snapshot encoding with new state model.

3. Phase 3: Command system and placement/removal semantics.
- Update `CommandSystem` to process rotation-aware placement and new command cases.
- Implement `removeStructure` validation: entity exists, not HQ, no last-path seal, wall/turret coupling handled deterministically.
- Implement refund policy: floor(50%) by item, immediate same-tick credit.
- Ensure wall-network recomputation and mounted turret cleanup on remove.
- Emit `structurePlaced` and `structureRemoved` events with deterministic ordering.

4. Phase 4: Production and conveyor system parity.
- Split current monolithic economy logic into PRD-aligned systems with deterministic phase ordering.
- Implement full port filter checks on every transfer.
- Implement splitter round-robin with blocked-output retry semantics.
- Implement merger alternating pull semantics.
- Implement storage shared-pool behavior with multiple directional ports.
- Remove global-inventory fallback transport behavior except HUD aggregation.

5. Phase 5: Shared gameplay interaction module.
- Create shared interaction layer in `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Sources/GameUI` that owns inspect/build mode transitions, selected structure, rotation state, drag-draw state, and rejection feedback state.
- Refactor `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Apps/macOS/Sources/FactoryDefensemacOSRootView.swift`, `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Apps/iOS/Sources/FactoryDefenseiOSRootView.swift`, `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Apps/iPadOS/Sources/FactoryDefenseiPadOSRootView.swift`, and `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Sources/FactoryDefense/main.swift` to use the shared module.
- Implement canonical behavior: select-to-enter build, place-to-exit (except drag-draw), cancel rules, same-entry toggle-off behavior.
- Add rotate bindings (`R`, touch rotate control), demolish entry points (long-press, delete/backspace, object inspector button), and confirmation UI.

6. Phase 6: Drag-draw and visual feedback parity.
- Implement conveyor/wall drag-draw path tracing with dominant-axis snap and per-cell validation.
- Emit N individual place commands in deterministic order in one tick.
- Stop chain on resource exhaustion; skip invalid cells without rolling back valid placements.
- Extend renderer preview model for rotation-aware ghost and port-layout visualization.
- Add rejection label/flash feedback and mode-safe preview clearing.

7. Phase 7: Snapshot/replay reset, docs, and release gates.
- Bump snapshot schema version and intentionally invalidate old snapshots.
- Regenerate `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/Tests/GameSimulationTests/GoldenReplayTests.swift` expected fingerprint.
- Update PRD and systems-plan status markers to implemented where complete.
- Run full validation gates and capture final parity checklist against both PRDs.

## Data Flow and Runtime Contract (Post-Refactor)
1. UI selects structure and rotation in shared interaction state.
2. Preview uses rotation-aware footprint + port transform + placement validator.
3. Confirm placement emits `placeStructure(BuildRequest)` with rotation.
4. `CommandSystem` validates path/cost/type rules, mutates world, emits events.
5. `ProductionSystem` crafts into output buffers based on power and recipe selection/pinning.
6. `ConveyorSystem` performs directional movement and port-filtered transfer with backpressure.
7. Combat consumes from wall-network ammo pools fed through wall-segment injection.
8. Demolish emits `removeStructure`, validates critical path, applies immediate refund, and updates dependent runtime state.

## Test Cases and Scenarios
1. Command/type coverage.
- Encode/decode tests for all new `CommandPayload` cases and `BuildRequest.rotation`.
- Deterministic sort-token tests including rotation and new command kinds.

2. Placement and removal.
- Rotation does not alter occupancy for symmetric footprints but does alter port orientation semantics.
- HQ removal rejected.
- Removal that seals last path rejected.
- Wall removal removes mounted turret and updates wall network mapping deterministically.
- Refund floor behavior verified per resource, including conveyor refund zero case.

3. Logistics parity.
- Conveyor directional transfer for all four directions.
- Splitter alternating + blocked-side retry semantics.
- Merger alternating pull with empty-input fallback.
- Storage shared-pool multi-port ingress/egress behavior.
- Backpressure propagation across mixed structures and conveyor chains.
- Port filter rejection does not drop items.

4. Interaction flow.
- Build mode entry/exit rules per PRD.
- Same menu entry toggles out of build mode.
- Rotation cycle and reset on mode exit.
- Drag-draw emits per-cell command sequence in stable order.
- Rejection feedback persists 1.5s and does not exit build mode on failed placement.
- Demolish triggers from all required inputs and requires confirmation.

5. Cross-platform parity.
- Snapshot-based interaction tests for shared module.
- Smoke UI tests per target wrapper for key bindings and gesture routing.

6. Regression and determinism.
- Full `swift test`.
- Updated golden replay fingerprint.
- Determinism twin-run test with mixed rotate/place/remove/drag command streams.
- Build checks for macOS, iOS (`CODE_SIGNING_ALLOWED=NO`), iPadOS (`CODE_SIGNING_ALLOWED=NO`).

## Acceptance Criteria
1. Every must-have behavior in both PRDs is implemented or explicitly marked deferred in PRD changelog with rationale.
2. No east-only conveyor assumptions remain in runtime transfer logic.
3. No global-inventory fallback is used for logistics transport behavior.
4. All four UI entrypoints use shared interaction flow and exhibit matching behavior.
5. Test suite and platform builds pass at end of work.
6. New snapshot schema and golden replay are committed and stable.

## Assumptions and Defaults
1. Canonical docs: `/Users/maxconrad/.codex/worktrees/d5e1/factory-defense/docs/GAME_PRD_LIVING.md` overrides conflicts; demolish timing is explicitly immediate removal/refund.
2. Existing snapshots/replays before this refactor are intentionally unsupported after schema bump.
3. No batch demolish is included in this scope.
4. Audio feedback remains out of scope.
5. Full parity includes splitter/merger and recipe pinning runtime + UI exposure in this plan.
