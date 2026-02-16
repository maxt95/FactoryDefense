# Wave Threat Runtime Worklog (2026-02-16)

Owner: Engineering
Status: Landed (v1-first scope)
Scope: Wave scheduler, perimeter spawning, enemy behavior modifiers, wall-network ammo runtime, turret host-wall constraints.

## Implemented in code

### 1) Wave content schema and loading compatibility
Files:
- `Sources/GameContent/ContentTypes.swift`
- `Sources/GameContent/ContentLoader.swift`
- `Sources/GameContent/ContentValidator.swift`
- `Content/bootstrap/waves.json`
- `Content/bootstrap/enemies.json`

Changes:
- Extended `EnemyDef` with `baseDamage`, `behaviorModifier`, `wallDamageMultiplier`, `minBudgetToSpawn`.
- Added `EnemyBehaviorModifier` (`none`, `structureSeeker`, `wallBreaker`, `auraBuffer`).
- Added `WaveContentDef` and `ProceduralWaveConfigDef`.
- Kept loader compatibility for legacy `waves.json` array shape and normalized to `WaveContentDef`.
- Added validation for contiguous authored waves, v1 `artillery_bug` exclusion, and procedural config sanity.
- Updated authored waves (1-8) and removed `artillery_bug` from authored compositions.

### 2) Threat runtime and deterministic scheduling
Files:
- `Sources/GameSimulation/SimulationTypes.swift`
- `Sources/GameSimulation/Systems.swift`
- `Sources/GameSimulation/BoardTypes.swift`

Changes:
- Added `PendingEnemySpawn`, deterministic RNG state in `ThreatState`, and `ThreatTelemetry`.
- Refactored `WaveSystem` to:
  - run authored waves 1-8 from content
  - generate wave 9+ procedurally from quadratic budget + difficulty multiplier
  - keep trickle active during and between surges
  - emit `waveStarted`, `waveCleared`, and `waveEnded`
- Implemented full-perimeter spawn clusters:
  - 2-4 clusters
  - minimum separation around perimeter
  - 3-tick intra-cluster stagger
  - 0-40 tick inter-cluster activation delay
  - 2-cell outside-border spawn with entry-point marching
- Enforced concurrent enemy cap at 500 in `WaveSystem`.

### 3) Enemy movement and structure attack behaviors
File:
- `Sources/GameSimulation/Systems.swift`

Changes:
- Enemies now attack blocking structures when pathing is blocked.
- Added structure damage/destroy events: `structureDamaged`, `structureDestroyed`.
- Implemented behavior modifiers:
  - Raider: nearby reachable non-wall structure seek (radius 4)
  - Breacher: wall-priority targeting + wall damage multiplier
  - Overseer: non-stacking aura (+25% damage, +15% effective speed) in radius 4
- Added wall-destruction cascade behavior:
  - mounted turret cleanup on host-wall destroy
  - wall-network rebuild dirtied after wall loss

### 4) Wall network ammo and turret host-wall model
Files:
- `Sources/GameSimulation/SimulationTypes.swift`
- `Sources/GameSimulation/Systems.swift`
- `Sources/GameSimulation/PlacementValidation.swift`
- `Sources/GameSimulation/EntityStore.swift`

Changes:
- Added `WallNetworkState` and wall-network membership maps in `CombatState`.
- Rebuilds connected wall components and computes capacity `segmentCount * 12`.
- Routes conveyor ammo injection into wall network pools.
- Turrets consume ammo from host-wall network pools and emit `notEnoughAmmo` dry-fire events.
- Splits wall-network ammo proportionally on topology changes and emits:
  - `wallNetworkSplit`
  - `wallNetworkRebuilt`
- Enforced turret placement host-wall requirement with `invalidTurretMountPlacement`.
- Added `hostWallID` to entities and turret lifecycle coupling to wall destruction.

### 5) App compile stability update
Files:
- `Sources/FactoryDefense/main.swift`
- `Apps/macOS/Sources/FactoryDefensemacOSRootView.swift`

Changes:
- Added placement-label handling for `.invalidTurretMountPlacement` to keep UI `switch` statements exhaustive across app targets.

## Test and build validation

- `swift test` -> pass (67 tests, 0 failures)
- `xcodebuild -project FactoryDefense.xcodeproj -scheme FactoryDefense_macOS -configuration Debug -destination 'platform=macOS' build` -> success

## Deferred (post-v1)

- `artillery_bug` ranged behavior and composition participation.
- Wall ammo network v2 propagation model.
- Additional wave reward/meta hooks.
