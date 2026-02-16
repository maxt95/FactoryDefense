# CLAUDE.md
your primary function unless otherwise asked to implement something is a researcher and planner. Your task is to create docs on how to implement core features of the game.

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run Commands

```bash
swift test                          # Run all tests
swift test --filter <TestName>      # Run a single test class or method
swift run FactoryDefensePrototype   # Run CLI simulation smoke test
swift run FactoryDefense            # Run macOS app
./scripts/generate_xcode_project.sh # Generate Xcode project for app targets
```

Open `Package.swift` directly in Xcode for module indexing and test execution. The generated `FactoryDefense.xcodeproj` (via XcodeGen / `project.yml`) provides iOS, iPadOS, and macOS app targets that reference the SPM package as `FactoryDefenseCore`.

## Architecture

Factory-defense hybrid game built with Swift 6.2, Metal, and SwiftUI. Simulation-first design: the deterministic tick loop runs independently of rendering.

### Module Dependency Graph

```
GameContent          (no deps — data definitions, JSON loading, validation)
  ↓
GameSimulation       (depends on GameContent — world state, systems, commands/events)
  ↓                    ↓
GameRendering        GameUI            GamePlatform
(Metal renderer)     (HUD, build menu)  (input, IO, telemetry)
```

Executables:
- **FactoryDefense** → GameSimulation + GameRendering + GameUI (macOS SwiftUI app)
- **FactoryDefensePrototype** → GameSimulation + GameContent + GamePlatform (CLI smoke test)

### Simulation Engine (GameSimulation)

- **Fixed 20 Hz tick** with deterministic command ordering. Rendering interpolates at 60 FPS via InterpolationBridge.
- **ECS-style systems** implement `SimulationSystem` protocol with `update(state:context:)`. Six systems execute in order: Command → Economy → Wave → EnemyMovement → Combat → Projectile.
- **Command pattern**: `PlayerCommand` objects are queued and applied deterministically for replay support.
- **Event system**: `SimEvent` objects emitted during simulation for observers.
- **WorldState** contains: tick counter, EntityStore (grid-based), EconomyState, ThreatState, RunState, CombatState.
- Snapshot serialization to JSON for save/load and golden replay regression tests.

### Content System (GameContent)

JSON-driven game data in `Content/bootstrap/`: enemies, items, recipes, turrets, waves, tech nodes. `ContentValidator` checks reference integrity, recipe cycles, wave composition, and tech reachability.

### Renderer (GameRendering)

Metal + MetalKit render graph with pass nodes (depth prepass, opaque, transparent, post, UI). Quality presets: mobileBalanced, tabletHigh, macCinematic. Debug visualization modes: normals, depth, overdraw, nanInf. Metal shaders live in `Sources/GameRendering/Shaders/`.

### Platform (GamePlatform)

Input abstraction (touch, mouse, keyboard, gamepad → gestures), FileSnapshotStore for JSON persistence, performance scene benchmarks, telemetry metrics.

## Test Structure

Four test targets mirror the library modules: GameContentTests, GameSimulationTests, GameRenderingTests, GamePlatformTests. Key test categories:
- **Determinism**: identical command streams produce identical snapshots
- **Golden replays**: regression tests against recorded replay files
- **Economy throughput**: production chain validation
- **Wave/combat integration**: end-to-end combat scenarios

## Key Design Decisions

- Platforms: iOS 18.0+, macOS 15.0+
- Shared modules designed for future co-op sync boundaries
- Grid-based entity placement with `GridPosition` (x, y, z for elevation)
- Production chain: miners → smelters → ammo modules/assemblers, powered by power plants
- All game balance data lives in JSON content files, not in code
