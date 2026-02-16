# Factory Defense

Native Apple game scaffold for a factory + tower defense hybrid.

## Product Docs
- Living PRD: `/Users/maxconrad/Workspace/factory-defense/docs/GAME_PRD_LIVING.md`
- Systems Build Plan: `/Users/maxconrad/Workspace/factory-defense/docs/GAME_SYSTEMS_PLAN.md`

## Tech
- Swift 6.2
- Metal / MetalKit renderer scaffolding
- Simulation-first architecture with deterministic tick loop
- Shared modules designed for future co-op sync boundaries

## Modules
- `GameContent`: data definitions, loading, and validation
- `GameSimulation`: deterministic world state, systems, commands/events
- `GameRendering`: Metal render graph + quality/debug modes
- `GameUI`: HUD and layout models for responsive UI
- `GamePlatform`: input abstraction and save/load snapshot IO
- `FactoryDefensePrototype`: command-line smoke test for simulation loop

## Run
```bash
swift test
swift run FactoryDefensePrototype
```

## Xcode
Open `Package.swift` directly in Xcode for shared-module indexing and test execution.

Generated app targets (`FactoryDefense_iOS`, `FactoryDefense_iPadOS`, `FactoryDefense_macOS`) are configured via XcodeGen:

```bash
./scripts/generate_xcode_project.sh
open FactoryDefense.xcodeproj
```

The generated project references this package as `FactoryDefenseCore`.

Run macOS app from any directory inside a worktree:

```bash
"$(git rev-parse --show-toplevel)/scripts/run_macos_app.sh"
```
