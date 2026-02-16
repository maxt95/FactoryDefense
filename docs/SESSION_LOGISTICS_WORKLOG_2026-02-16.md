# Logistics Runtime Worklog (2026-02-16)

Owner: Engineering
Status: In progress (iterative)
Scope: First production-grade slice of conveyor-routed logistics in deterministic simulation.

## Goals for this session
- Implement a real runtime foundation for PRD-aligned logistics.
- Keep determinism + test quality intact.
- Update docs as implementation truth changes.

## Implemented in code

### 1) Deterministic logistics state in snapshots
File: `Sources/GameSimulation/SimulationTypes.swift`
- Added `ConveyorPayload` to represent in-flight conveyor items with tick progress.
- Extended `EconomyState` with:
  - `structureInputBuffers`
  - `structureOutputBuffers`
  - `conveyorPayloadByEntity`
- These fields are `Codable/Hashable/Sendable`, so they are included in replay/snapshot determinism and persistence.

### 2) First-pass runtime buffer + conveyor behavior
File: `Sources/GameSimulation/Systems.swift` (`EconomySystem`)
- Added runtime sync/prune logic for logistics state per live structure entity.
- Added output buffering for production buildings (smelter/assembler/ammo module/miner/storage capacities by type).
- Added directed conveyor movement with deterministic transfer order and per-item progress (`conveyorTicksPerTile`, default 5).
- Added output-drain logic:
  - Building output -> adjacent conveyor (east) when free.
  - Building output -> adjacent building input when valid.
  - Fallback to global inventory only when no routed consumer exists.
- Added local input consumption for crafting (input buffers consumed before global inventory).
- Added structure-type input filtering (smelter/assembler/ammo-module/turret/storage), preventing invalid conveyor routing into production consumers.
- Preserved existing power efficiency and recipe timing behavior.

### 3) Turret ammo coupling improvement
File: `Sources/GameSimulation/Systems.swift` (`CombatSystem`)
- Turrets now consume ammo from local turret input buffer first.
- If local buffer is empty, they fall back to global inventory.
- This aligns with PRD direction: direct-feed can sustain turrets with global fallback still available.

### 4) iPad build hygiene
File: `Apps/iPadOS/Info.plist`
- Added supported interface orientations to remove iPad validation warning.

### 5) Ore patch binding + miner placement validation
Files: `Sources/GameSimulation/SimulationTypes.swift`, `Sources/GameSimulation/PlacementValidation.swift`, `Sources/GameSimulation/Systems.swift`, `Sources/GameSimulation/EntityStore.swift`
- Extended `BuildRequest` with optional `targetPatchID` for miner placement targeting.
- Added runtime binding fields:
  - `Entity.boundPatchID`
  - `OrePatch.boundMinerID` (+ `isExhausted` helper)
- Added `PlacementResult.invalidMinerPlacement` with deterministic adjacency/binding checks in `PlacementValidator`.
- `CommandSystem` now resolves miner patch binding at placement time and emits placement rejection when no valid adjacent patch exists.

### 6) Patch-based miner extraction + depletion events
File: `Sources/GameSimulation/Systems.swift` (`EconomySystem`)
- Replaced placeholder global miner ore generation with patch-based extraction from bound adjacent ore patches.
- Added deterministic binding sync/recovery each tick for miner/patch linkage.
- Miner extraction now:
  - advances per-tick progress using existing power efficiency
  - outputs ore by patch ore type
  - decrements `remainingOre` from the bound patch
  - emits `patchExhausted` and `minerIdled` on depletion
- Miners with no valid extractable patch no longer contribute power demand (idle miners draw 0 power).

### 7) App target compile fix for new placement result
Files: `Apps/macOS/Sources/FactoryDefensemacOSRootView.swift`, `Apps/iOS/Sources/FactoryDefenseiOSRootView.swift`, `Apps/iPadOS/Sources/FactoryDefenseiPadOSRootView.swift`, `Sources/FactoryDefense/main.swift`
- Added placement-label handling for `.invalidMinerPlacement` across app targets to keep `switch` statements exhaustive and surface clear player feedback.

### 8) Directional belt-node semantics + storage shared-pool runtime
Files: `Sources/GameSimulation/SimulationTypes.swift`, `Sources/GameSimulation/Systems.swift`
- Extended `EconomyState` with:
  - `storageSharedPoolByEntity`
  - splitter/merger alternation maps (`splitterOutputToggleByEntity`, `mergerInputToggleByEntity`) with runtime cleanup/pruning.
- Updated transfer runtime to pass source positions through enqueue paths and enforce side-aware consumer acceptance:
  - `smelter`: west input only
  - `assembler` / `ammoModule`: west or north input
  - `turretMount`: rejects direct structure input.
- Added storage shared-pool transport behavior:
  - west/north ingress into a common internal pool
  - east/south egress drains from the same pool
  - deterministic requeue when egress target is blocked.
- Completed directional conveyor tests against belt-node targets and added strict invalid-port rejection coverage.

## Test coverage added
File: `Tests/GameSimulationTests/LogisticsRuntimeTests.swift`
- `testConveyorCarriesOutputToNeighborInputBuffer`
- `testConnectedConveyorBackpressureBlocksOutputDrain`
- `testTurretConsumesLocalBufferAmmoBeforeGlobalInventory`
- `testMinerPlacementBindsRequestedPatch`
- `testMinerPlacementAutoBindsAdjacentPatchWhenTargetOmitted`
- `testMinerPlacementRejectsInvalidPatchTarget`
- `testMinerExtractsFromBoundPatchAndEmitsDepletionEvents`

File: `Tests/GameSimulationTests/PlacementValidationTests.swift`
- `testMinerPlacementRequiresAdjacentUnboundPatch`
- `testMinerPlacementRejectsOccupiedPatchBindingTarget`

Also updated deterministic golden hash:
- `Tests/GameSimulationTests/GoldenReplayTests.swift`

Additional logistics tests:
- `testConveyorTransfersByRotationDirection`
- `testSplitterAlternatesOutputs`
- `testStorageSharedPoolAcceptsWestNorthAndDrainsEastSouth`
- `testAssemblerRejectsInputFromInvalidPortSide`

## Validation executed
- `swift test` -> pass (67/67)
- `xcodebuild -project FactoryDefense.xcodeproj -scheme FactoryDefense_macOS -configuration Debug build` -> success
- `xcodebuild -project FactoryDefense.xcodeproj -scheme FactoryDefense_iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build` -> success
- `xcodebuild -project FactoryDefense.xcodeproj -scheme FactoryDefense_iPadOS -configuration Debug CODE_SIGNING_ALLOWED=NO build` -> success
- `swift test --filter LogisticsRuntimeTests` -> pass (11/11)

## PRD alignment notes
Aligned with `docs/prd/building_specifications.md` in this session:
- Per-building input/output buffers: partial runtime implementation complete.
- Directed conveyor progress/transfer/backpressure: first-pass implementation complete for standard conveyors.
- Turret local ammo before global fallback: implemented.

Not yet complete vs PRD:
- Full multi-port model + directional rotation semantics.
- Full strict item filter model per declared port schema (`buildings.json`) rather than current structure-level side checks.
- Ore reveal rings + renewal spawning lifecycle.

## Key learnings
- Preserving deterministic sort/transfer order is straightforward and stable when conveyor movement is processed in a fixed positional order.
- Introducing snapshot-visible logistics state early avoids replay migration pain later.
- A compatibility fallback to global inventory allows incremental migration without destabilizing existing gameplay/tests.

## Next high-value iteration
1. Port definition runtime (input/output sides + filters) and building rotation in placement.
2. Splitter/merger runtime and storage hub pull/push semantics.
3. WaveSystem authored-wave consumption from `waves.json` with deterministic schedule.
4. Ore reveal/renewal lifecycle (geology survey unlocks + renewal spawn policy).
