# Conveyor Placement & Editing Improvements

Version: 1.0
Date: 2026-02-17
Status: Implemented
Depends on: `build_interaction_flow.md`, `building_specifications.md`, `factory_economy.md`

---

## Summary

Reduces conveyor placement friction from ~2 actions/tile to ~0.1 via drag-to-paint with auto-corners, quick rotate/reverse shortcuts, smart snap auto-orientation, flow brush for bulk edits, and a belt planner for long-distance routes.

## Implemented Features

### Phase 1: Quick Rotate + Smart Snap (Tier 1)

**Keyboard shortcuts** (macOS): R (rotate CW), Shift+R (rotate CCW), F (reverse) on hovered conveyor in inspect mode. F in edit-belts mode reverses entire connected run.

**Touch quick edit widget** (iOS/iPadOS): Tapping a conveyor in inspect mode shows a floating CW/CCW/Reverse/Dismiss widget above the tile.

**Smart snap** (`ConveyorSnapResolver`): Auto-orients new conveyors to connect with adjacent belts, splitters, and mergers. Supports port compatibility detection.

### Phase 2: Drag-to-Paint (Tier 2)

**Smart path** (`GameplayDragDrawPlanner.smartPath`): Tracks actual cursor cell sequence, auto-inserts corner conveyors at axis changes, supports rubber-band backtracking. Replaces `dominantAxisPath` for conveyors (walls still use dominant axis). Pipeline: dedup/rubber-band → interpolate cardinal gaps → remove zigzag spikes → assign I/O directions.

**Diagonal rejection**: `accumulateConveyorDragCell` rejects inputs where both axes changed simultaneously (cursor jumped diagonally due to fast mouse movement). Only cardinal-adjacent cells are accumulated.

**Zigzag removal** (`removeZigzags`): Post-processing step that collapses 2-cell perpendicular detours (A-B-C-D where A→D is 1 cardinal step) and 1-cell U-turn spikes. Repeats until stable.

**Per-cell I/O** (`DragPreviewCell`): Each cell in a drag path carries its own input/output directions. Corners are perpendicular I/O automatically.

**Endpoint auto-connect** (`snapPathEndpoints`): When placing a conveyor path, the first and last cells are automatically snapped to connect with adjacent existing infrastructure (conveyors, buildings, splitters, mergers). The first cell's input direction is adjusted to face a feeding neighbor; the last cell's output is adjusted to face a receiving neighbor. Only snaps when the default path direction doesn't already connect.

**Stay in build mode**: After conveyor or wall drag-draw, build mode remains active for immediate next run.

### Phase 3: Flow Brush + Reverse Run (Tier 3)

**Edit-belts mode** (E key / button): New interaction mode for bulk editing existing belt directions.

**Flow brush** (`FlowBrushState`): Drag across existing conveyors to repaint their I/O to match stroke direction. Supports rubber-band.

**Reverse run**: F key on a conveyor in edit-belts mode flood-fills connected conveyors and swaps all I/O.

### Phase 4: Belt Planner (Tier 4)

**Plan-belt mode** (P key / button): Click start, click end, see Manhattan path preview. R cycles H-first / V-first variants. Enter confirms placement.

**`BeltPlannerState`**: Manages start/end pins, variant selection, path computation.

## New Types

| Type | Module | Purpose |
|------|--------|---------|
| `DragPreviewCell` | GameUI | Per-cell preview data: position, I/O directions, isCorner, validation |
| `ConveyorSnapResolver` | GameUI | Computes auto-orientation from neighbor analysis |
| `ConveyorQuickEditWidget` | GameUI | Touch floating widget for rotate/reverse |
| `FlowBrushState` | GameUI | Tracks brush stroke cells and proposed I/O changes |
| `FlowBrushChange` | GameUI | Single cell change proposal from flow brush |
| `BeltPlannerState` | GameUI | Tracks start/end pins, selected variant, computed path |
| `BeltPlannerVariant` | GameUI | H-first / V-first enum |
| `ConveyorPlacementCell` | GamePlatform | Lightweight cell data for placeConveyorPath |
| `KeyAction` | App (macOS) | Key action events for game shortcuts |

## Extended Interaction State

```swift
public enum GameplayInteractionMode: String, CaseIterable, Identifiable, Sendable {
    case interact = "Interact"
    case build = "Build"
    case editBelts = "Edit Belts"
    case planBelt = "Plan Belt"
}
```

New fields on `GameplayInteractionState`: `quickEditTarget`, `dragPreviewCells`, `dragCellSequence`, `flowBrush`, `beltPlanner`.

## Command Reuse

All features use existing `CommandPayload` cases:
- `placeConveyor(position:direction:inputDirection:outputDirection:)` — extended with optional I/O config for atomic placement+configuration. When I/O is provided, the command handler sets `conveyorIOByEntity` immediately after spawning, avoiding entity ID prediction issues caused by deterministic command sort reordering.
- `configureConveyorIO(entityID:inputDirection:outputDirection:)` — still used for post-placement edits (quick rotate, flow brush, reverse run)
- `placeStructure(BuildRequest)`

The `placeConveyor` command was extended (not replaced) to carry optional I/O directions. Existing callers that omit I/O continue to work unchanged — conveyors fall back to rotation-based default I/O.

## Files Modified

### GameUI Module
- `GameplayInteractionState.swift` — Extended with new modes, quickEditTarget, drag cells, flow brush, belt planner
- `GameplayDragDrawPlanner.swift` — Added smartPath, assignDirections, deduplicateAndRubberBand
- `DragPreviewCell.swift` — NEW
- `ConveyorSnapResolver.swift` — NEW
- `ConveyorQuickEditWidget.swift` — NEW
- `FlowBrushState.swift` — NEW
- `BeltPlannerState.swift` — NEW

### GamePlatform Module
- `RuntimeController.swift` — Added placeConveyorPath, ConveyorPlacementCell, snapPathEndpoints (endpoint auto-connect)

### App Targets
- `Apps/macOS/Sources/FactoryDefensemacOSRootView.swift` — Key actions, hovered conveyor, smart drag, flow brush, belt planner, mode handling
- `Apps/iOS/Sources/FactoryDefenseiOSRootView.swift` — Quick edit widget, smart drag, flow brush, mode handling
- `Apps/iPadOS/Sources/FactoryDefenseiPadOSRootView.swift` — Same as iOS
- `Sources/FactoryDefense/main.swift` — Exhaustive mode switch

### Tests
- `Tests/GameUITests/ConveyorSnapResolverTests.swift` — NEW (6 tests)
- `Tests/GameUITests/SmartPathTests.swift` — NEW (17 tests: directions, corners, backtrack, duplicates, diagonal interpolation, zigzag removal, diagonal rejection)
- `Tests/GameUITests/FlowBrushStateTests.swift` — NEW (7 tests)
- `Tests/GameUITests/BeltPlannerStateTests.swift` — NEW (10 tests)
- `Tests/GameUITests/ConveyorInteractionTests.swift` — NEW (13 tests)
- `Tests/GamePlatformTests/RuntimeControllerTests.swift` — Extended with 4 endpoint snapping tests
