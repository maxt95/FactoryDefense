# Build Interaction Flow

Version: 1.0-draft
Date: 2026-02-16
Status: Draft
Depends on: `building_specifications.md`, `run_bootstrap_session_init.md`, `factory_economy.md`

## Purpose

This document defines how the player interacts with the build system: selecting structures, placing them on the grid, rotating, demolishing, and the special conveyor drag-draw gesture. It covers input mapping for touch and keyboard/mouse, interaction states, and the command flow from UI gesture to simulation execution.

---

## 1. Interaction Modes

The game has two primary interaction modes. The player is always in one or the other.

### 1.1 Inspect Mode (Default)

The player is observing and interacting with the existing world.

| Action | Touch | Mouse/Keyboard |
|--------|-------|-----------------|
| Pan camera | Drag on empty space | Drag / WASD |
| Zoom | Pinch | Scroll wheel |
| Inspect entity | Tap structure/enemy | Click structure/enemy |
| Open build menu | Tap build button | B key or click build button |

In inspect mode:
- Tapping a placed structure opens the **Object Inspector** popup showing stats, buffers, recipe, and health.
- Tapping empty ground or an enemy shows relevant info or does nothing.
- No placement preview is shown.
- Camera pan and zoom are unrestricted.

### 1.2 Build Mode (Select-Then-Place)

The player has selected a structure from the build menu and is placing it.

| Action | Touch | Mouse/Keyboard |
|--------|-------|-----------------|
| Preview placement | Hover / drag over grid | Mouse move over grid |
| Confirm placement | Tap grid cell | Click grid cell |
| Rotate structure | Tap rotate button | R key |
| Cancel build mode | Tap ✕ / tap build menu again | Escape / right-click |
| Pan camera | Two-finger drag | WASD / middle-drag |
| Zoom | Pinch | Scroll wheel |

Build mode behavior:
- A **ghost preview** follows the cursor/finger showing the selected structure at the current grid cell.
- The ghost is tinted **green** if placement is valid, **red** if invalid (occupied, restricted, blocks path, unaffordable).
- The ghost shows the structure's port layout at the current rotation.
- After placing one structure, build mode **exits back to inspect mode**. The player must re-select from the build menu to place another.
- Exception: **drag-draw** (see §4) for conveyors and walls allows placing multiple structures in one gesture without exiting build mode.

### 1.3 Mode Transitions

```
Inspect ──[select from build menu]──→ Build
Build   ──[place structure]──────────→ Inspect
Build   ──[cancel / Escape]─────────→ Inspect
Build   ──[drag-draw conveyor/wall]─→ Inspect (after drag ends)
Inspect ──[long-press structure]────→ Demolish confirm (future, see §5)
```

---

## 2. Build Menu

### 2.1 Structure

The build menu is a persistent overlay panel (already implemented as `BuildMenuPanel`). It displays structures grouped by category:

| Category | Structures |
|----------|-----------|
| Production | Miner, Smelter, Assembler, Ammo Module |
| Logistics | Conveyor, Splitter, Merger, Storage |
| Defense | Wall, Turret Mount |
| Utility | Power Plant |

### 2.2 Affordability

- Each entry shows its cost (e.g., "4× plate_steel").
- Entries are visually distinguished by affordability state:
  - **Affordable**: normal appearance, selectable.
  - **Unaffordable**: dimmed/greyed, still selectable (enters build mode with red ghost so player can plan layout, but placement is blocked).
- Affordability is checked against the **HQ storage buffer** (or global computed inventory in T0 fallback).

### 2.3 Selection Behavior

- Tapping an entry enters build mode with that structure selected.
- Tapping the same entry again (or pressing Escape) exits build mode.
- Tapping a different entry switches the selected structure without exiting build mode.
- The currently selected entry is highlighted in the menu.

---

## 3. Rotation

### 3.1 Mechanic

Buildings support 4-way rotation: **0° (north), 90° (east), 180° (south), 270° (west)**.

Rotation determines port orientation. A smelter with an input port on its west face and output port on its east face, when rotated 90°, has input on north and output on south.

### 3.2 Controls

| Input | Action |
|-------|--------|
| R key | Cycle rotation clockwise: 0° → 90° → 180° → 270° → 0° |
| Rotate button (touch) | Same cycle, displayed near ghost preview |
| Q key (optional) | Cycle counter-clockwise |

### 3.3 Rotation in Build Mode

- Rotation state persists while in build mode. Pressing R multiple times before placing lets the player dial in the right orientation.
- The ghost preview updates immediately to show rotated port positions.
- Rotation resets to 0° when exiting build mode.

### 3.4 Rotation for Conveyors

Conveyors have a single input direction and single output direction. For single-tap placement, rotation sets the conveyor's flow direction:
- 0° = south → north
- 90° = west → east
- 180° = north → south
- 270° = east → west

During drag-draw (§4), direction is inferred from the drag vector and rotation is ignored.

### 3.5 Structures Where Rotation Matters

| Structure | Ports | Rotation effect |
|-----------|-------|-----------------|
| Miner | 1 output | Controls which side ore exits |
| Smelter | 1 input, 1 output | Controls input/output faces |
| Assembler | 2 inputs, 1 output | Controls which faces accept which inputs |
| Ammo Module | 2 inputs, 1 output | Controls input/output faces (per `building_specifications.md`: West + North inputs) |
| Conveyor | 1 input, 1 output | Controls flow direction |
| Splitter | 1 input, 2 outputs | Controls split direction |
| Merger | 2 inputs, 1 output | Controls merge direction |
| Storage | 4 ports (all faces) | Rotation has no visible effect |
| Wall | No ports | Rotation has no visible effect |
| Turret Mount | No ports (ammo from wall network) | Rotation has no visible effect |
| Power Plant | No ports | Rotation has no visible effect |

---

## 4. Drag-Draw (Conveyors & Walls)

Conveyors and walls are placed far more frequently than other structures. Drag-draw provides a fast placement gesture for laying lines of either.

### 4.1 Activation

Drag-draw activates when:
1. The player is in build mode with **conveyor** or **wall** selected.
2. The player begins a **drag gesture** on a valid empty grid cell (instead of a tap).

### 4.2 Behavior

1. **Drag starts**: First conveyor is placed at the starting cell.
2. **Drag continues**: As the finger/cursor crosses into new grid cells, a structure is placed in each cell along the path.
3. **Direction (conveyors only)**: Each conveyor's direction is set automatically from the movement vector between consecutive cells. Only cardinal directions (N/S/E/W) are supported — diagonal movement snaps to the dominant axis. Walls have no direction — they simply fill cells.
4. **Validation**: Each cell is validated individually. If a cell is invalid (occupied, restricted, unaffordable), it is skipped and the chain continues from the last valid cell.
5. **Drag ends**: Build mode exits. All placed conveyors are final.

### 4.3 Cost

Each structure in the chain costs its normal build price (conveyor: 1× plate_iron, wall: 1× wall_kit). The chain stops placing if the player runs out of resources mid-drag. Already-placed structures in the chain are not rolled back.

### 4.4 Preview During Drag

- The path is shown as a ghost line from the drag start to the current position.
- Valid segments are green, invalid segments are red.
- A running cost counter shows total resources to be consumed.

### 4.5 Command Encoding

Drag-draw emits a **sequence of individual `placeStructure` commands**, one per conveyor cell. These are batched and applied in simulation order within the same tick. This preserves determinism and replay compatibility — the replay log sees N individual placement commands, not a special "draw line" command.

---

## 5. Demolish / Remove

### 5.1 Mechanic

Players can remove placed structures and receive a **partial refund** of the build cost.

- **Refund rate**: 50% of each resource cost, rounded down. Minimum 0 per resource.
- Example: Smelter costs 4× plate_steel → refund is 2× plate_steel.
- Example: Conveyor costs 1× plate_iron → refund is 0 (floor of 0.5). Conveyors are effectively free to remove.

### 5.2 Restrictions

- The **HQ cannot be demolished**. It is permanent.
- Demolishing a structure that would **seal the last enemy path to the HQ** is blocked (same pathfinding check as placement, inverted).
- Structures **under active enemy attack** can still be demolished (player choice to cut losses).
- Demolish is available in both grace period and playing phases.

### 5.3 Interaction

| Input | Action |
|-------|--------|
| Long-press structure (touch) | Opens demolish confirmation |
| Click structure + Delete/Backspace (keyboard) | Opens demolish confirmation |
| Demolish button in Object Inspector | Opens demolish confirmation |

**Confirmation flow:**
1. Player initiates demolish on a structure.
2. A small confirmation popup appears at the structure showing: structure name, refund amount, "Confirm" / "Cancel" buttons.
3. "Confirm" emits a `removeStructure` command to simulation.
4. "Cancel" dismisses the popup.

> **Design note**: No batch demolish at T0. Structures are removed one at a time. Batch select-and-demolish is a future UX improvement.

### 5.4 Command

New command payload required:

```
CommandPayload.removeStructure(entityID: EntityID)
```

The `CommandSystem` processes removal:
1. Validate the entity exists and is a player-owned structure.
2. Validate removal doesn't block the last enemy path.
3. Validate entity is not the HQ.
4. Calculate refund (50% floor of each cost item).
5. Add refund resources to inventory.
6. Remove entity from `EntityStore`.
7. Emit `SimEvent.structureRemoved(entityID, refundItems)`.

---

## 6. Placement Validation Feedback

### 6.1 Ghost Preview States

The ghost preview communicates placement validity through color:

| State | Color | Meaning |
|-------|-------|---------|
| Valid | Green tint | Can place here |
| Occupied | Red tint | Another structure is here |
| Restricted | Red tint | HQ zone or ramp cell |
| Blocks path | Orange tint | Would seal enemy pathfinding |
| Unaffordable | Red tint, pulsing | Valid position but can't pay |
| Out of bounds | No ghost shown | Cursor outside grid |

### 6.2 Rejection Feedback

When the player attempts to confirm a placement that fails validation:
- The ghost flashes red briefly.
- A short text label appears near the ghost: "Occupied", "Blocks path", "Can't afford", etc.
- The label fades after 1.5 seconds.
- No sound at T0 (audio is out of scope).
- Build mode is **not** exited on rejection — the player can try a different cell.

---

## 7. Command Summary

### 7.1 New Commands Required

| Command | Payload | Description |
|---------|---------|-------------|
| `placeStructure` | `BuildRequest(structure, position, rotation)` | **Existing** — add `rotation` field |
| `removeStructure` | `entityID: EntityID` | **New** — demolish with partial refund |

### 7.2 Updated Types

**BuildRequest** — add rotation:
```
struct BuildRequest {
    var structure: StructureType
    var position: GridPosition
    var rotation: Rotation  // new: .north, .east, .south, .west
}
```

**Rotation** enum:
```
enum Rotation: Int, Codable {
    case north = 0    // 0°
    case east = 90    // 90°
    case south = 180  // 180°
    case west = 270   // 270°
}
```

### 7.3 New Events

| Event | Data | When |
|-------|------|------|
| `structurePlaced` | entityID, structureType, position, rotation | After successful placement |
| `structureRemoved` | entityID, refund items | After successful demolish |
| `placementRejected` | rejection reason | Already exists — extend with rotation context |

---

## 8. Reconciliation with Current Code

| Current Code | PRD Target | Action |
|--------------|------------|--------|
| `BuildRequest` has no rotation | Add `rotation: Rotation` field | Extend struct |
| No `removeStructure` command | Add `CommandPayload.removeStructure` | Extend enum |
| No demolish validation | Add pathfinding check for removal | Extend `PlacementValidator` |
| No interaction mode state | Add `InteractionMode` enum (inspect/build) | Add to UI state |
| Build menu selection doesn't exit on place | Exit build mode after single placement | Change UI behavior |
| No conveyor drag-draw | Add drag gesture → multi-place batch | New gesture handler |
| No rotation UI | Add R key binding + touch rotate button | Extend input handling |
| `highlightedCell` exists | Extend to carry rotation and validity detail | Enhance preview model |
| No `structurePlaced` event | Add event for placement tracking | Extend `EventKind` |
| No refund calculation | Add `StructureType.refundCosts` computed property | Add to type |

---

## 9. Implementation Phases

### Phase 1: Rotation + Updated Placement (blocks T0)
- Add `Rotation` enum.
- Add `rotation` field to `BuildRequest` and entity storage.
- Wire R key and rotate button in UI.
- Update ghost preview to show rotated port layout.
- Update `CommandSystem` to store rotation on placed entities.

### Phase 2: Interaction Mode State (blocks T0)
- Add `InteractionMode` enum to UI state (inspect / build).
- Default to inspect mode.
- Build menu selection enters build mode; placement or cancel returns to inspect.
- In inspect mode, tap on structure opens Object Inspector.
- In build mode, tap on grid places structure.

### Phase 3: Demolish (blocks T0)
- Add `CommandPayload.removeStructure(entityID:)`.
- Add refund calculation: 50% floor of each cost item.
- Add pathfinding validation for removal.
- Add confirmation popup UI.
- Add long-press / Delete key input binding.
- Add `SimEvent.structureRemoved`.

### Phase 4: Conveyor Drag-Draw (enhances T0, not blocking)
- Add drag gesture detection when conveyor is selected in build mode.
- Implement cardinal-snap path tracing across grid cells.
- Emit batched `placeStructure` commands for each cell in the drag path.
- Add ghost line preview with per-cell validation coloring.
- Add running cost counter during drag.

### Phase 5: Polish (post-T0)
- Rejection feedback labels and flash animation.
- Ghost preview port visualization.
- Batch demolish (select multiple, then confirm).
- Undo last placement (Ctrl+Z / shake gesture).

---

## 10. Resolved Design Questions

1. ~~Conveyor refund at 50% floor = 0~~ **Resolved: intentional.** Conveyors are cheap and the most-placed structure. Free removal encourages layout experimentation. No gameplay benefit to rounding up.
2. ~~Rotation persistence across placements~~ **Resolved: no.** Rotation resets to 0° (north) when exiting build mode. Clean slate each time.
3. ~~Drag-draw for walls~~ **Resolved: yes.** Drag-draw works for both conveyors and walls. Walls are another frequently placed 1×1 structure and benefit from the same fast-placement gesture. Walls have no direction, so drag-draw simply fills each cell along the path.
4. ~~Touch disambiguation~~ **Resolved.** See §10.1 below.

### 10.1 Touch Gesture Rules (Canonical)

| Gesture | Inspect Mode | Build Mode (tap-place structures) | Build Mode (conveyor/wall drag-draw) |
|---------|-------------|----------------------------------|--------------------------------------|
| One-finger tap | Inspect tapped entity | Place structure at cell | Place single structure at cell |
| One-finger drag on valid empty cell | Camera pan | Camera pan | Drag-draw chain |
| One-finger drag on occupied/invalid cell | Camera pan | Camera pan | Camera pan |
| One-finger drag outside grid | Camera pan | Camera pan | Camera pan |
| Two-finger drag | Camera pan | Camera pan | Camera pan |
| Pinch | Zoom | Zoom | Zoom |

**Key rule**: In build mode with a drag-drawable structure (conveyor or wall) selected, dragging on a valid empty cell starts drag-draw. Dragging on anything else pans the camera. Two-finger drag always pans regardless of mode.

**Mouse equivalent**: Left-click = tap. Left-drag in build mode on valid cell = drag-draw. WASD / middle-drag = pan. Scroll = zoom.

## 11. Open Questions

(None remaining for T0 scope.)

---

## Changelog

- 2026-02-16: Initial draft. Defines interaction modes, rotation, demolish, conveyor drag-draw, and command flow.
- 2026-02-16: Resolved all open questions. Conveyor free-removal is intentional. Rotation resets on mode exit. Drag-draw extended to walls. Touch disambiguation rules canonicalized.
- 2026-02-16: Cross-PRD alignment: Fixed Ammo Module port count from 1 input to 2 inputs (per building_specifications.md).
