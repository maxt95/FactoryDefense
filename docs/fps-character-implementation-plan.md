# FPS Character Implementation Plan

## Context

The game currently has a top-down "base view" only. The goal is to add a playable first-person character that lets the player walk around their factory at ground level. The player can toggle between the existing base view (for building/managing) and an FPS view (for exploring/inspecting).

The core architectural challenge: the simulation runs at 20 Hz on an integer grid, but FPS movement needs smooth 60 fps sub-cell positioning. The solution is **client-side prediction** — the rendering layer predicts movement at 60 fps and reconciles with the authoritative 20 Hz simulation each tick.

### Key Existing Infrastructure to Reuse
- `IsometricCamera` + `simd_float4x4.lookAt()` / `.perspective()` in `Math.swift` — ready-made 3D camera math
- `pbr.metal` shader — already does proper 3D vertex transforms with per-instance MVP
- `WhiteboxMeshRenderer` — instanced 3D mesh pipeline, just needs a real perspective matrix
- `MeshID.gridTile` — flat ground tile mesh already exists in the asset catalog
- `SimulationSystem` protocol — easy to add a new `PlayerMovementSystem`
- `EntityStore` — can add `spawnPlayer()` with new `.player` category
- `InputAbstraction` — extensible gesture/event system

---

## Phase 0: Simulation Foundation (GameSimulation)

Add player concept to the simulation without breaking existing systems or snapshots.

### 0A. Extend core types
**File**: `Sources/GameSimulation/SimulationTypes.swift`
- Add `.player` to `EntityCategory`
- Add optional `subCellX: Float?`, `subCellY: Float?`, `facingRadians: Float?` to `Entity` (nil for non-player entities — preserves snapshot compat)
- Add computed `worldPosition: SIMD3<Float>` on Entity

### 0B. Add `PlayerState` struct
**File**: `Sources/GameSimulation/SimulationTypes.swift`
```swift
public struct PlayerState: Codable, Hashable, Sendable {
    public var entityID: EntityID?
    public var gridPosition: GridPosition
    public var subCellX: Float   // [0..1) fractional X within cell
    public var subCellY: Float   // [0..1) fractional Y within cell
    public var facingRadians: Float  // yaw in radians
    public var pitchRadians: Float   // look pitch in radians
    public var moveSpeed: Float      // cells per second
    public var isInFPSMode: Bool

    public var worldX: Float { Float(gridPosition.x) + subCellX }
    public var worldZ: Float { Float(gridPosition.y) + subCellY }
    public var worldY: Float { Float(gridPosition.z) + 1.6 }  // eye height
}
```
Add `player: PlayerState` field to `WorldState`. Initialize in `bootstrap()` at HQ position.

### 0C. Add player movement commands
**File**: `Sources/GameSimulation/SimulationTypes.swift`
- Add `case playerMove(dx: Float, dz: Float, facingRadians: Float, pitchRadians: Float)` to `CommandPayload`
- Add `case toggleFPSMode` to `CommandPayload`
- Update Codable conformance (CodingKeys, Kind, encode/decode, sortToken)

### 0D. Add `EntityStore.spawnPlayer()`
**File**: `Sources/GameSimulation/EntityStore.swift`
- New method spawning a `.player` entity with sub-cell fields

### 0E. Add `PlayerMovementSystem`
**File**: `Sources/GameSimulation/Systems.swift`

New system implementing `SimulationSystem` protocol:
- Processes `playerMove` commands: applies clamped movement delta, collision against blocked/structure cells (axis-aligned sliding), updates `PlayerState` and entity position
- Processes `toggleFPSMode` commands
- Insert between `CommandSystem` and `EconomySystem` in execution order

```swift
public struct PlayerMovementSystem: SimulationSystem {
    public func update(state: inout WorldState, context: SystemContext) {
        for command in context.commands {
            switch command.payload {
            case .playerMove(let dx, let dz, let facingRadians, let pitchRadians):
                // Clamp delta to moveSpeed * tickDuration
                // Test target cell walkability (board.contains, board.isBlocked)
                // Axis-aligned sliding on collision
                // Update PlayerState grid position + sub-cell offsets
                // Sync entity position
            case .toggleFPSMode:
                state.player.isInFPSMode.toggle()
            default: continue
            }
        }
    }
}
```

**File**: `Sources/GameSimulation/SimulationEngine.swift`
- Add `PlayerMovementSystem()` to default systems array (after CommandSystem, before EconomySystem)

---

## Phase 1: Client-Side Prediction (GameSimulation)

Enable smooth 60 fps player movement between 20 Hz simulation ticks.

### 1A. Extend interpolation
**File**: `Sources/GameSimulation/Interpolation.swift`
- Add `blendedPlayerPosition: SIMD3<Float>` to `InterpolatedWorldFrame` (lerp with angle wrapping for facing)

### 1B. Create `FPSClientPredictor`
**New file**: `Sources/GameSimulation/FPSClientPredictor.swift`

Runs at 60 fps, accumulates input, produces predicted position:
- `applyInput(forward:strafe:facing:pitch:deltaTime:moveSpeed:)` — called every render frame, moves predicted position
- `harvestMoveCommand() -> (dx, dz, facing, pitch)` — called at 20 Hz tick boundaries, returns accumulated delta since last harvest, resets accumulator
- `reconcile(authorityState:)` — called after sim tick, hard-snaps if >1 cell error, otherwise exponential decay (0.3 blend) toward authoritative position

```
Frame loop (60fps):
  1. Poll FPSInputState for axes + mouse delta
  2. predictor.applyInput(...)  → smooth predicted position
  3. Render at predictor.position

Tick boundary (20Hz):
  1. delta = predictor.harvestMoveCommand()
  2. runtime.enqueue(.playerMove(delta))
  3. simulation steps
  4. predictor.reconcile(authority: world.player)
```

---

## Phase 2: Input System (GamePlatform + App)

### 2A. Add `FPSInputState`
**New file**: `Sources/GamePlatform/FPSInputState.swift`
- Continuous key state booleans: `moveForward/Back/Left/Right`
- Thread-safe mouse delta accumulator with NSLock: `accumulateMouseDelta(dx:dy:)`, `consumeMouseDelta() -> (dx, dy)`
- Computed `forwardAxis: Float`, `strafeAxis: Float` (forward - backward, right - left)

### 2B. Extend `InputGesture`
**File**: `Sources/GamePlatform/InputAbstraction.swift`
- Add `case toggleFPSMode` and `case fpsMoveTick(forward:strafe:facing:pitch:)` gesture types
- Update `DefaultInputMapper` to produce corresponding `PlayerCommand`s

### 2C. Replace `KeyboardPannableMTKView` with `FPSCapableMTKView`
**File**: `Sources/FactoryDefense/main.swift` (lines 729-760)

The current MTKView subclass only handles `keyDown`. Replace with:
- `keyDown(with:)` + `keyUp(with:)` — set/clear booleans on `FPSInputState`
- `mouseMoved(with:)` — feed `event.deltaX/deltaY` to `FPSInputState.accumulateMouseDelta()`
- `NSTrackingArea` registration for mouse movement events
- Mouse capture: `CGAssociateMouseAndMouseCursorPosition(0)` + `NSCursor.hide()`
- Mouse release: `CGAssociateMouseAndMouseCursorPosition(1)` + `NSCursor.unhide()`
- Escape key exits FPS mode and releases mouse
- Falls back to existing pan behavior when not in FPS mode

---

## Phase 3: Camera and Rendering (GameRendering)

### 3A. Create `FPSCameraController`
**New file**: `Sources/GameRendering/FPSCameraController.swift`

Wraps the existing `simd_float4x4.lookAt()` and `.perspective()` from `Math.swift`:
```swift
public struct FPSCameraController: Sendable {
    public var fovYRadians: Float = .pi / 3.0   // ~60 deg
    public var nearZ: Float = 0.05
    public var farZ: Float = 300
    public var minPitch: Float = -.pi / 2.5
    public var maxPitch: Float = .pi / 2.5

    public func viewMatrix(eye: SIMD3<Float>, yaw: Float, pitch: Float) -> simd_float4x4 {
        let clampedPitch = clamp(pitch, minPitch, maxPitch)
        let lookDir = SIMD3<Float>(
            cos(clampedPitch) * sin(yaw),
            sin(clampedPitch),
            cos(clampedPitch) * cos(yaw)
        )
        return simd_float4x4.lookAt(eye: eye, center: eye + lookDir, up: SIMD3(0, 1, 0))
    }

    public func projectionMatrix(aspect: Float) -> simd_float4x4 {
        simd_float4x4.perspective(fovY: fovYRadians, aspect: aspect, near: nearZ, far: farZ)
    }
}
```

**Note**: The existing `IsometricCamera` struct uses an orbit model (computes eye FROM target + distance). FPS needs the inverse (eye IS the player, target is computed from look direction). We reuse the static matrix functions but not the `IsometricCamera` struct itself.

### 3B. Add view mode to render context
**File**: `Sources/GameRendering/RenderTypes.swift`
- Add `ViewMode` enum (`.baseView`, `.fpsView`)
- Add `viewMode`, `fpsViewProjection: simd_float4x4?` to `RenderContext`

### 3C. Switch render graph per view mode
**File**: `Sources/GameRendering/RenderGraph.swift`
- Add `static func fpsMode() -> RenderGraph` — same nodes as default but WITHOUT `WhiteboxBoardNode` (the 2D compute shader draws a flat top-down grid which is meaningless in perspective)

**File**: `Sources/GameRendering/Renderer.swift`
- Add `viewMode: ViewMode` property
- In `draw(in:)`, compute FPS view-projection matrix when in FPS mode
- Swap render graph based on `viewMode`
- Pass FPS data through `RenderContext`

### 3D. Update mesh renderer for perspective projection
**File**: `Sources/GameRendering/WhiteboxMeshRenderer.swift`

- In `makeViewProjectionMatrix()` (line 221): if `context.viewMode == .fpsView`, return `context.fpsViewProjection` instead of the custom oblique matrix
- In `makeInstanceBatches()`: when FPS mode, generate ground tile instances for board cells using existing `MeshID.gridTile` mesh, tinted by terrain type (blocked=dark, restricted=tinted, normal=green/gray)
- Skip rendering player mesh when in FPS view (can't see yourself)
- For initial 96x64 board (6144 tiles), instancing all tiles is fine. Add distance-based culling for larger boards later.

### 3E. Add player mesh
**File**: `Sources/GameRendering/Mesh/WhiteboxMeshLibrary.swift`
- Add `case playerCharacter` to `MeshID`

**File**: `Sources/GameRendering/Mesh/WhiteboxAssetCatalog.swift`
- Simple capsule-like shape (stacked boxes) for the player, visible in base view

### 3F. Update scene builder for player entities
**File**: `Sources/GameRendering/WhiteboxInteraction.swift`
- Add `.player` case to `WhiteboxEntityCategory`
- Handle `.player` in `WhiteboxSceneBuilder.build(from:)` entity loop
- Map player category to `MeshID.playerCharacter` in mesh renderer

---

## Phase 4: App Layer Integration (FactoryDefense)

### 4A. Add view mode state
**File**: `Sources/FactoryDefense/main.swift`
- Add `@State private var viewMode: ViewMode = .baseView` to `FactoryDefenseGameplayView`
- Add `FPSInputState`, `FPSClientPredictor`, `FPSCameraController` instances

### 4B. Wire FPS tick loop
The FPS update integrates into the existing runtime:
- **At 60 fps** (MTKView draw callback): poll `fpsInput` for axes + mouse delta, feed `fpsPredictor.applyInput()`, update camera position
- **At 20 Hz tick boundary**: call `fpsPredictor.harvestMoveCommand()`, enqueue `playerMove` command via `runtime.enqueue(payload:)`
- **After sim tick**: call `fpsPredictor.reconcile(authority: runtime.world.player)`

### 4C. Update `MetalSurfaceView`
**File**: `Sources/FactoryDefense/main.swift`
- Pass `viewMode`, `fpsEyePosition`, `fpsYaw/Pitch` through to renderer via `updateNSView`
- Pass `FPSInputState` to the MTKView subclass for key/mouse handling

### 4D. Add toggle UI
- Button in overlay or keyboard shortcut (Tab) to switch views
- Crosshair overlay (`"+"` centered on screen) in FPS mode
- Hide build menu / adjust overlay visibility based on view mode

---

## Phase 5: FPS Interaction

### 5A. Raycast grid picking
- DDA grid-stepping raycast from camera eye along look direction
- Returns first grid cell hit within range (~20 cells)
- Replaces screen-space tap picking when in FPS mode

### 5B. FPS build/interact
- Left-click: place selected structure at raycast target cell
- Right-click: remove structure
- Reuses existing `GameRuntimeController.placeStructure()` / `.removeStructure()` — only the input mapping changes

### 5C. Crosshair + highlight
- Crosshair rendered in SwiftUI overlay
- Highlight the targeted grid cell (similar to existing placement preview)

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Sub-cell position as Optional floats on Entity | Keeps integer grid as authority, avoids changing every entity query, nil for non-player entities preserves snapshot compat |
| Client-side prediction with authority reconciliation | 20 Hz would feel laggy for FPS. Standard netcode pattern (Quake/Source/Overwatch) adapted for single-player sim loop |
| Separate render graph for FPS mode | 2D compute shader (whitebox) draws flat top-down pixels — meaningless in perspective. Skip it, use 3D mesh pass only |
| Reuse `simd_float4x4.lookAt` / `.perspective` not `IsometricCamera` struct | IsometricCamera uses orbit model (eye computed from target). FPS needs eye-as-source. The static matrix helpers are what we need. |
| PlayerMovementSystem between Command and Economy | Player position settled before any position-dependent economy logic runs |
| Ground tiles via instanced `MeshID.gridTile` | Already exists in asset catalog. 6K instances is trivial for Metal instancing. Avoids new shader/pass. |

---

## Verification Plan

1. **Simulation determinism**: Record command stream with `playerMove` commands, replay, verify identical `WorldState` snapshots
2. **Unit tests**: `PlayerMovementSystem` collision logic, `FPSCameraController` matrix correctness, `InterpolatedWorldFrame` player blending
3. **Snapshot compat**: Load old snapshots (without `PlayerState`), verify they decode with defaults
4. **Manual smoke test**: `swift run FactoryDefense`, press Tab to toggle FPS mode, WASD to move, mouse to look, verify smooth movement and correct perspective rendering

---

## Architecture Diagram

```
INPUT (60 fps)                  SIMULATION (20 Hz)            RENDERING (60 fps)

FPSCapableMTKView               SimulationEngine              FactoryRenderer
  keyDown/Up ──┐                  │                             │
  mouseMoved ──┤                Systems:                     RenderGraph
               │                  CommandSystem                 │
               ▼                  PlayerMovementSystem ◀──── [fpsView?]
         FPSInputState            EconomySystem                 │
               │                  WaveSystem              WhiteboxMeshRenderer
               ▼                  EnemyMovement           (perspective matrix)
       FPSClientPredictor         CombatSystem                  │
               │                  ProjectileSystem        Ground tiles +
     (60fps) predict                    │                 3D structure meshes
               │               (20Hz)   ▼
     harvest ──┼──────────▶ playerMove command
     (20Hz)    │                        │
               │                        ▼
     reconcile ◀──────────── authority PlayerState
               │
               ▼
       predicted position ─────────────────────────────▶ FPS camera → draw
```

---

## Files Summary

### New Files
| File | Module | Purpose |
|------|--------|---------|
| `Sources/GameSimulation/FPSClientPredictor.swift` | GameSimulation | 60fps prediction + 20Hz reconciliation |
| `Sources/GamePlatform/FPSInputState.swift` | GamePlatform | Continuous key state + mouse delta accumulator |
| `Sources/GameRendering/FPSCameraController.swift` | GameRendering | First-person camera matrix computation |

### Modified Files
| File | Changes |
|------|---------|
| `Sources/GameSimulation/SimulationTypes.swift` | EntityCategory.player, Entity sub-cell fields, PlayerState struct, CommandPayload cases, WorldState.player |
| `Sources/GameSimulation/EntityStore.swift` | spawnPlayer() method |
| `Sources/GameSimulation/Systems.swift` | PlayerMovementSystem |
| `Sources/GameSimulation/SimulationEngine.swift` | Add PlayerMovementSystem to default systems |
| `Sources/GameSimulation/Interpolation.swift` | Player position interpolation |
| `Sources/GamePlatform/InputAbstraction.swift` | New InputGesture cases, mapper updates |
| `Sources/GameRendering/RenderTypes.swift` | ViewMode enum, FPS fields on RenderContext |
| `Sources/GameRendering/RenderGraph.swift` | fpsMode() render graph |
| `Sources/GameRendering/Renderer.swift` | viewMode property, FPS matrix computation, graph switching |
| `Sources/GameRendering/WhiteboxMeshRenderer.swift` | Perspective matrix swap, ground tile instancing, player mesh skip |
| `Sources/GameRendering/WhiteboxInteraction.swift` | Player entity in scene builder |
| `Sources/GameRendering/Mesh/WhiteboxMeshLibrary.swift` | MeshID.playerCharacter |
| `Sources/GameRendering/Mesh/WhiteboxAssetCatalog.swift` | Player mesh primitive |
| `Sources/FactoryDefense/main.swift` | FPSCapableMTKView, view mode state, FPS tick integration, toggle UI, crosshair |
