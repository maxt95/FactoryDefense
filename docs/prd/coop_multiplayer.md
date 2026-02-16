# Co-op Multiplayer PRD

> Authoritative specification for 2-player online co-op: shared-base gameplay, network architecture, session lifecycle, wave scaling, and simulation integration. Companion to `wave_threat_system.md` (threat model), `run_bootstrap_session_init.md` (session init), `factory_economy.md` (economy), and `building_specifications.md` (logistics).

---

## 1. Design Pillars

1. **Shared fate** — One HQ, one economy, one outcome. Both players win or lose together.
2. **Organic specialization** — The factory-west / defense-east map orientation naturally creates two complementary roles without enforcing them.
3. **Cooperation over competition** — Both players build anywhere, spend from the same pool, and interact with all structures. No territorial gatekeeping.
4. **Architecture-first** — Deterministic lockstep leverages the existing command pattern, snapshot serialization, and `PlayerID` infrastructure.
5. **Apple-native networking** — `Network.framework` for transport, Bonjour for local discovery, invite codes for internet play.

---

## 2. Scope

| In Scope | Out of Scope (v1 co-op) |
|---|---|
| 2-player online co-op | 3–4 player support |
| Shared single base (one HQ) | Separate bases / competitive mode |
| Cross-device: iPhone, iPad, Mac | Same-device split-screen |
| Invite code matchmaking | Game Center auto-matchmaking |
| Deterministic lockstep networking | Rollback netcode |
| Ping communication system | Voice chat / free text chat |
| Co-op wave scaling | Per-player difficulty |

---

## 3. Co-op Gameplay Vision

### 3.1 The Experience

Two players share one HQ, one economy, and one fate. There is always more to do than one person can handle — having a partner means dividing attention across production and defense simultaneously.

**Grace period**: Both players scramble to place the initial factory layout. One focuses west, setting up miners and smelters on ore patches. The other focuses east, placing wall segments and turret mounts. They see each other's cursors, ping locations, and watch the shared inventory tick down as both spend.

**Active play**: When trickle enemies begin, roles sharpen organically. One watches the perimeter and manages turret placement. The other optimizes logistics and fixes production bottlenecks. A breach happens — the defense player is already placing emergency walls while the factory player queues more wall_kit production. Neither role is formally assigned; players gravitate based on what needs doing and can swap at any time.

### 3.2 Natural Role Specialization

The game's two-domain structure organically creates two roles:

**Factory Manager**:
- Places and optimizes production buildings (miners, smelters, assemblers, ammo modules)
- Manages conveyor routing and logistics bottlenecks
- Monitors power supply/demand and builds power plants
- Ensures ammo production keeps pace with turret consumption
- Spots starved/blocked structures and re-routes supply

**Defense Coordinator**:
- Places and extends wall perimeters
- Mounts turrets on wall segments and manages turret type distribution
- Watches spawn edges and breach warnings
- Places emergency walls during breaches
- Triggers waves when defenses are ready
- Monitors wall network ammo pools

### 3.3 Why Co-op Is Better Than Solo

- **Attention bandwidth**: Solo requires constant context-switching between factory and defense. Co-op lets each player focus on one domain.
- **Reaction speed**: When a breach happens during a wave, both players respond simultaneously — wall repair AND ammo rerouting.
- **Information sharing**: Two players watching different parts of the map spot problems faster (depleted ore, starved turrets, flanking enemies).
- **Shared resource tension**: "Do we build another turret or a second smelter?" creates natural negotiation that single-player cannot match.
- **Higher difficulty ceiling**: Harder wave scaling is sustainable because throughput and reaction time both scale with two players.

---

## 4. Shared Economy Model

### 4.1 Fully Shared — No Per-Player Resources

Both players operate on one unified economy:

- **One `EconomyState`**: `inventories`, `powerAvailable`, `powerDemand`, `currency` — all shared.
- **One `EntityStore`**: All structures belong to the base, not to individual players.
- **One HQ**: Single shared loss condition.

This matches the existing `EconomyState` structure, which already uses a single global inventory model. No structural changes are needed to the economy model itself.

### 4.2 Structure Placement

Both players can place structures anywhere on the map at any time. No build zones, no ownership restrictions, no "your side / my side" enforcement. Build costs are deducted from the shared `EconomyState.inventories`.

### 4.3 Placement Conflict Resolution

The existing deterministic command ordering handles same-tick conflicts correctly:

1. Commands sort by `actor` first (`PlayerID(1)` before `PlayerID(2)`).
2. If both try to place at the same cell on the same tick: Player 1 succeeds, Player 2 gets `placementRejected` (occupied).
3. If both try to build but only enough resources for one: Player 1 succeeds, Player 2 gets `placementRejected` (insufficient resources).
4. Resources are never deducted for failed placements.
5. Both outcomes are deterministic — both peers compute the same result.

**UI change**: Surface rejections as "another player built here" rather than generic "occupied" when the cell was free at command-issue time.

### 4.4 Build Attribution

An optional `placedBy: PlayerID?` field on `Entity` enables color-coded structures (subtle blue tint for Player 1, subtle orange for Player 2) and end-of-run stats. This is purely informational — both players can interact with all structures regardless of who placed them.

---

## 5. Multiplayer Wave Scaling

### 5.1 Scaling Philosophy

Two players have ~2x the attention bandwidth and reaction speed, but share one economy that does not produce 2x faster. Co-op should feel like two people solving a problem that one person could not solve alone at the same difficulty tier.

### 5.2 Scaling Parameters

| Parameter | Solo | Co-op | Rationale |
|---|---|---|---|
| Wave budget multiplier | 1.0x | 1.5x | Co-op Normal ≈ Solo Hard in enemy count |
| Trickle spawn bonus | +0 | +1 per spawn event | Light constant pressure increase |
| Grace period bonus | +0s | +30s | Account for coordination overhead |
| Starting resources | 1x | 1x (no change) | Two players build one factory, not two |
| Enemy count cap | 500 | 600 | More turrets can handle more targets |

All values live in `difficulty.json` as co-op modifier fields — tunable without code changes.

### 5.3 Co-op Budget Formula

```
coop_budget(w) = floor(base_budget(w) × difficulty_multiplier × 1.5)
```

Where `base_budget(w) = 10 + 4w + floor(0.5 × w²)` for procedural waves 9+, and `difficulty_multiplier` = 0.85 / 1.0 / 1.15 for easy/normal/hard (see `wave_threat_system.md` §4.2).

### 5.4 Trickle Scaling

| Difficulty | Solo Trickle | Co-op Trickle |
|---|---|---|
| Easy | 1 | 2 |
| Normal | 1–2 | 2–3 |
| Hard | 2–3 | 3–4 |

Trickle interval remains unchanged — pressure increases through quantity, not frequency.

### 5.5 Grace Period

| Difficulty | Solo Grace | Co-op Grace |
|---|---|---|
| Easy | 180s | 210s |
| Normal | 120s | 150s |
| Hard | 60s | 90s |

### 5.6 Content Data Representation

Add co-op modifiers to `difficulty.json`:

```json
{
  "normal": {
    "gracePeriodSeconds": 120,
    "coopGracePeriodBonus": 30,
    "coopWaveBudgetMultiplier": 1.5,
    "coopTrickleSizeBonus": 1,
    "coopEnemyCap": 600,
    "...existing fields..."
  }
}
```

---

## 6. Network Architecture

### 6.1 Synchronization Model — Deterministic Lockstep with Input Delay

Both peers run identical `SimulationEngine` instances. Only `PlayerCommand` objects cross the wire.

**Why lockstep**:
1. The simulation is already deterministic — verified by `SimulationDeterminismTests`.
2. The 20 Hz tick rate naturally absorbs latency. A 2-tick input delay (100ms) handles up to 100ms one-way latency before being perceptible.
3. No rollback complexity — unnecessary for a strategy game with no twitch reactions.
4. Minimal bandwidth — ~50–100 bytes per command, under 2 KB/s total.

### 6.2 Lockstep Protocol

```
Tick N processing:
1. Local player generates commands for tick N+D (D = input delay in ticks).
2. Commands are sent to remote peer as a TickCommandPacket.
3. Tick N advances ONLY when both peers' commands for tick N have been received.
4. Empty command arrays are sent for ticks where the player does nothing.
   (The other peer must know "no commands" is intentional, not a network drop.)
```

**Input delay (D)**: Adaptive, starting at 2 ticks (100ms) and increasing to 4 ticks (200ms) if round-trip time exceeds 120ms. Imperceptible in a strategy game — 100–200ms of placement delay is not noticeable when the visual feedback (placement preview) is instant.

### 6.3 Wire Protocol

```swift
public struct TickCommandPacket: Codable, Sendable {
    public var senderID: PlayerID
    public var targetTick: UInt64          // which tick these commands apply to
    public var commands: [PlayerCommand]    // may be empty (null input)
    public var stateHash: UInt64?          // optional, every 100 ticks
}
```

### 6.4 Desync Detection and Recovery

Every 100 ticks (5 seconds), each peer includes a hash of their `WorldState` in the next packet. On hash mismatch:

1. Game pauses.
2. Host sends full `WorldSnapshot` to guest.
3. Guest calls `engine.load(snapshot:)` to resynchronize.
4. Lockstep resumes.
5. If desync persists after recovery, session terminates with error.

The existing `WorldState: Hashable` conformance and `makeSnapshot()`/`load(snapshot:)` methods support this directly.

### 6.5 Latency Budget

| Metric | Target | Acceptable | Degraded |
|---|---|---|---|
| One-way latency | < 60ms | 60–120ms | 120–200ms |
| Round-trip time | < 120ms | 120–240ms | 240–400ms |
| Input delay | 2 ticks (100ms) | 3 ticks (150ms) | 4 ticks (200ms) |
| Tick stall timeout | N/A | N/A | 500ms (pause warning) |
| Connection lost threshold | N/A | N/A | > 1000ms (pause game) |

At > 400ms RTT, warn players about connection quality. At > 1000ms, pause and offer reconnection.

---

## 7. Session Lifecycle

### 7.1 Session Discovery — Invite Codes

Use **6-character alphanumeric invite codes** for v1:

1. Player A selects "Host Co-op Game" from the main menu.
2. A short code is generated (e.g., "FD4K2M") and displayed.
3. Player A shares the code out-of-band (text message, voice chat).
4. Player B selects "Join Co-op Game" and enters the code.
5. The code maps to Player A's session via a lightweight relay/matchmaking service.

**Why invite codes over Game Center**: Simpler to implement, no account required, cross-platform from day one. Game Center matchmaking can be layered on later.

### 7.2 Lobby Flow

```
Host: Main Menu → "Host Co-op" → Difficulty Select → Lobby (code displayed, waiting)
Guest: Main Menu → "Join Co-op" → Enter Code → Lobby (connected)

Lobby state:
- Both players see each other's display name and platform (iOS/Mac)
- Host selects difficulty and seed (or random seed)
- Both players see the difficulty selection
- "Ready" toggle for each player
- Host presses "Start" when both ready
- Both clients receive bootstrap parameters
- Both clients run WorldState.bootstrap(difficulty:seed:sessionMode:.coop)
- Deterministic bootstrap produces identical tick-0 state
- Lockstep begins
```

### 7.3 Host vs Guest Roles

**Host-authoritative for session management only** (not simulation):

| Responsibility | Host | Guest |
|---|---|---|
| Creates session, generates invite code | Yes | No |
| Selects difficulty and seed | Yes | No |
| Source of truth for snapshot recovery | Yes | No |
| Runs simulation engine | Yes | Yes (identical) |
| Issues commands | Yes | Yes |
| Controls any gameplay | No advantage | No disadvantage |

Player 1 (host) gets `PlayerID(1)`, guest gets `PlayerID(2)`. This only affects deterministic command sort order (Player 1's commands process first on ties) and UI color assignment.

### 7.4 Disconnect Handling

| Phase | Behavior |
|---|---|
| **Immediate** | Simulation pauses (lockstep cannot advance). "Partner Disconnected" overlay. |
| **Grace window (30s)** | Frozen game with countdown timer. Connected player can view map but cannot act. Disconnected client auto-reconnects. |
| **Reconnection within 30s** | Host sends `WorldSnapshot` to reconnecting peer. Peer loads via `engine.load(snapshot:)`. Lockstep resumes. |
| **Timeout (30s elapsed)** | Remaining player chooses: **Continue Solo** (wave scaling reverts to solo values, factory/turrets keep running autonomously) or **End Session** (game ends with summary). |

No AI takeover for the disconnected player. No mid-game join support in v1.

### 7.5 iOS Background Handling

When the app moves to background on iOS:
- Use `UIApplication.shared.beginBackgroundTask` for brief keep-alive (~30s).
- If the app is terminated by the system, handle as a disconnect (§7.4).
- On return to foreground within the grace window, reconnect using snapshot transfer.

---

## 8. Apple Platform Integration

### 8.1 Transport — Network.framework

Use `NWConnection` with a custom `NWProtocolFramer` for message framing:

- Native to iOS 18+ / macOS 15+.
- Supports direct peer-to-peer and internet relay.
- Built-in TLS encryption.
- Handles WiFi/cellular transitions on iOS.
- QUIC support for unreliable datagrams (cursor position updates).

### 8.2 Session Discovery

**Local network (same WiFi)**: `NWBrowser` with Bonjour — zero-configuration, cross-platform on same network.

**Internet**: Lightweight WebSocket matchmaking service:
1. Host registers session with generated invite code.
2. Guest queries service with code, receives host connection info.
3. Peers attempt direct `NWConnection` via QUIC/UDP.
4. If NAT traversal fails, traffic routes through relay.

### 8.3 Cross-Platform (iOS ↔ macOS)

The simulation is platform-agnostic — only serialized `PlayerCommand` objects cross the wire. Cross-platform co-op works inherently because both peers run identical `SimulationEngine` instances.

### 8.4 Game Center (Future Enhancement)

Not required for v1 co-op. Can be layered on later for:
- Player identity (display names, avatars)
- Auto-matchmaking with compatible players
- Co-op leaderboards (waves survived by team)
- Co-op-specific achievements

### 8.5 MultipeerConnectivity — Not Recommended

Not recommended because: limited to local proximity (no internet play), higher latency than `Network.framework`, unreliable iOS↔macOS bridging, being superseded by `Network.framework` in Apple's guidance.

---

## 9. New Commands and Events

### 9.1 New CommandPayload Cases

```swift
public enum CommandPayload: Codable, Hashable, Sendable {
    // Existing:
    case placeStructure(BuildRequest)
    case extract
    case triggerWave

    // New for co-op:
    case ping(PingRequest)        // World-space communication marker
    case readyForWave             // Player signals readiness for next wave
}
```

### 9.2 Ping System

Pings place a visible marker on the map at a grid position with an optional type. They are simulation commands — deterministic, both players see them at the same tick.

```swift
public struct PingRequest: Codable, Hashable, Sendable {
    public var position: GridPosition
    public var pingType: PingType

    public enum PingType: String, Codable, Hashable, Sendable {
        case alert      // "Danger here!"
        case request    // "Build something here"
        case defend     // "Defend this area"
        case look       // "Look at this"
    }
}
```

**Ping lifecycle**: Pings are transient — they exist for 80 ticks (4 seconds) and auto-expire.

```swift
public struct ActivePing: Codable, Hashable, Sendable {
    public var position: GridPosition
    public var pingType: PingRequest.PingType
    public var actor: PlayerID
    public var expiresAtTick: UInt64
}
```

A new `PingSystem` processes ping commands, adds to `WorldState.activePings`, and removes expired pings. Runs after `CommandSystem` in the execution order.

### 9.3 Wave Trigger Consensus

In co-op, manually triggering a wave requires both players to consent:
1. Player sends `readyForWave` command.
2. `RunState.waveReadyPlayers` tracks which players are ready.
3. When both players are marked ready, the wave triggers.
4. Ready state resets after each wave.

This prevents one player from overwhelming the other by triggering waves prematurely.

### 9.4 New SimEvent Kinds

```swift
case playerPinged       // A player placed a ping
case playerReady        // A player signaled wave readiness
case bothPlayersReady   // Both players ready — wave incoming
```

---

## 10. UI/UX for Co-op

### 10.1 Partner Cursor Visibility

Each player's cursor position is shared and rendered on the partner's screen. This is the primary nonverbal communication channel — you can see where your partner is looking and what they are about to build.

**Implementation**: Cursor position is sent as unreliable UDP datagrams (not simulation commands) via QUIC. Sent at display frame rate when the cursor moves. Packet loss is acceptable — the partner cursor simply stutters briefly.

```swift
public struct CursorUpdate: Codable, Sendable {
    public var playerID: PlayerID
    public var gridPosition: GridPosition
    public var selectedStructure: StructureType?  // build preview ghost
    public var timestamp: TimeInterval
}
```

### 10.2 Player Color Coding

| Element | Player 1 (Host) | Player 2 (Guest) |
|---|---|---|
| Cursor color | Blue | Orange |
| Placement preview ghost | Blue-tinted | Orange-tinted |
| Ping marker ring | Blue | Orange |
| Build attribution tint | Subtle blue | Subtle orange |
| HUD name label | Blue text | Orange text |

Structure color coding is subtle — a slight tint on whitebox geometry, not a full recolor. The goal is awareness, not visual noise.

### 10.3 Shared HUD

The existing HUD reads from the single `WorldState` — both players see identical values (resources, wave timer, HQ health, ammo stock). No changes needed to the core HUD.

**New HUD elements for co-op**:
- **Partner indicator**: Small label showing partner's current activity (building, viewing, idle).
- **Ping notification**: Directional edge indicator pointing toward ping location, with audio cue.
- **Ready-up indicator**: Before manually triggered waves, checkmarks for each player's ready status.
- **Connection quality**: Small icon (green/yellow/red) based on latency.

### 10.4 In-Game Communication

Priority-ordered:

1. **Ping system** (must-have): Grid-position pings with 4 types. Tap-and-hold or dedicated button. Both players see marker and hear directional audio cue.
2. **Quick-chat wheel** (nice-to-have): Predefined phrases — "Need ammo here", "Watch the north wall", "Low on resources", "Nice build!", "Wave incoming — ready?" Localized. No free text.
3. **External voice** (out of scope): Players use FaceTime, Discord, etc.

---

## 11. Simulation Changes

### 11.1 WorldState Additions

```swift
public struct WorldState: Codable, Hashable, Sendable {
    // ... existing fields ...
    public var activePings: [ActivePing]      // Transient ping markers
    public var sessionMode: SessionMode       // .solo or .coop
}

public enum SessionMode: String, Codable, Hashable, Sendable {
    case solo
    case coop
}
```

### 11.2 RunState Additions

```swift
public struct RunState: Codable, Hashable, Sendable {
    // ... existing fields ...
    public var playerSlots: [PlayerSlot]           // Player tracking
    public var waveReadyPlayers: Set<PlayerID>     // Co-op wave consensus
}

public struct PlayerSlot: Codable, Hashable, Sendable {
    public var playerID: PlayerID
    public var displayName: String
    public var isConnected: Bool
    public var structuresPlaced: Int               // For end-of-run stats
}
```

For solo mode, `playerSlots` contains one entry. For co-op, two entries. Systems that check player count (wave scaling, grace period) read `playerSlots.count`.

### 11.3 Entity Addition

```swift
public struct Entity: Codable, Hashable, Sendable {
    // ... existing fields ...
    public var placedBy: PlayerID?  // nil for HQ, enemies, projectiles
}
```

`EntityStore.spawnStructure` gains an optional `placedBy` parameter. `CommandSystem` passes `command.actor` as `placedBy` when spawning structures.

### 11.4 System Changes

| System | Change |
|---|---|
| **CommandSystem** | Pass `command.actor` as `placedBy` to `spawnStructure`. Handle new `ping` and `readyForWave` payloads. |
| **PingSystem** (new) | Process ping commands, manage `activePings`, remove expired. |
| **WaveSystem** | Check `sessionMode` for co-op scaling: 1.5x budget, +1 trickle, +30s grace. Read values from `difficulty.json` co-op fields. For `readyForWave` consensus: only trigger manual waves when `waveReadyPlayers` contains all connected players. |
| **EconomySystem** | No changes. |
| **EnemyMovementSystem** | No changes. |
| **CombatSystem** | No changes. |
| **ProjectileSystem** | No changes. |

**Updated system execution order**: Command → Ping → Economy → Wave → EnemyMovement → Combat → Projectile.

### 11.5 Bootstrap Changes

`WorldState.bootstrap()` gains `sessionMode` and `playerSlots` parameters:

```swift
public static func bootstrap(
    difficulty: Difficulty = .normal,
    seed: RunSeed = 0,
    sessionMode: SessionMode = .solo,
    playerSlots: [PlayerSlot] = [...]
) -> WorldState
```

Both peers call `bootstrap()` with identical parameters → deterministic identical tick-0 state.

---

## 12. New Module — GameNetworking

### 12.1 Module Dependency Graph

```
GameContent          (no deps)
  │
GameSimulation       (depends on GameContent)
  │         \            \                \
GameRendering  GameUI   GameNetworking    GamePlatform
(Metal)        (HUD)    (co-op transport) (input, IO)
```

`GameNetworking` imports `GameSimulation` for access to `PlayerCommand`, `WorldSnapshot`, `SimulationEngine`, and related types.

### 12.2 Key Types

**`CoopTickScheduler`** — Manages the lockstep protocol:
- Buffers local and remote commands per tick.
- Advances the simulation only when both players' commands are received.
- Tracks adaptive input delay.
- Triggers desync detection via periodic state hashing.

**`CoopTransport`** — `NWConnection` wrapper:
- Reliable channel for `TickCommandPacket` (commands, hashes).
- Unreliable channel for `CursorUpdate` (cosmetic, loss-tolerant).
- Connection state management and reconnection logic.

**`LobbyManager`** — Session setup:
- Bonjour discovery for local network.
- Invite code generation and resolution for internet.
- Lobby state machine (waiting → connected → ready → starting).

---

## 13. Implementation Sequencing

### Phase 1 — Minimum Viable Co-op (8–12 weeks)

**Goal**: Two players on the same local network can play a shared game with deterministic lockstep.

**Simulation**:
- Add `SessionMode`, `PlayerSlot`, `placedBy` to core types.
- Co-op wave scaling in `WaveSystem`.
- Co-op modifiers in `difficulty.json`.
- Update `bootstrap()` with co-op parameters.

**Networking** (new `GameNetworking` module):
- `CoopTickScheduler` — lockstep coordinator.
- `CoopTransport` — `NWConnection` wrapper (TCP for commands).
- `TickCommandPacket` serialization.
- Bonjour discovery via `NWBrowser`.
- Basic lobby (host/join, difficulty select, ready, start).

**UI**:
- Host/Join menu options and lobby screen.
- Partner cursor rendering (unreliable channel).
- Player color coding (cursor, placement preview).
- Connection status indicator.
- Pause-on-disconnect with 30s reconnection window.

**Testing**:
- Dual-engine determinism tests (verify two engines produce identical states from identical commands).
- Lockstep protocol tests (simulated latency, packet loss).
- Same-tick placement conflict tests.
- Co-op wave scaling tests.

**Not in Phase 1**: Internet play, invite codes, ping system, quick-chat, Game Center, build attribution colors.

### Phase 2 — Internet Play and Communication (4–6 weeks)

**Goal**: Players on different networks can find and join each other, with in-game communication.

- Invite code system with lightweight relay/matchmaking server.
- NAT traversal via QUIC/UDP hole punching with relay fallback.
- Adaptive input delay based on measured RTT.
- Desync detection (periodic state hashing) and snapshot recovery.
- Ping command, `PingSystem`, ping UI (markers, directional indicators, audio cue).
- `readyForWave` consensus for co-op wave triggers.
- Connection quality indicator.

### Phase 3 — Polish and Platform Integration (3–4 weeks)

**Goal**: Production-quality co-op experience with Apple platform integration.

- Build attribution color tinting on structures.
- Per-player end-of-run summary stats.
- Quick-chat wheel with predefined phrases.
- Game Center integration (optional matchmaking, leaderboards, achievements).
- iOS background handling (keep-alive, graceful disconnect).
- Spectate mode during reconnection.
- Cross-platform testing matrix (iPhone–iPhone, iPhone–iPad, iPhone–Mac, Mac–Mac).
- Performance profiling with co-op wave scaling (higher enemy counts).

---

## 14. Data Schema Changes

### 14.1 Extend: `difficulty.json`

Add co-op modifier fields to each difficulty:

```json
{
  "normal": {
    "gracePeriodSeconds": 120,
    "coopGracePeriodBonus": 30,
    "coopWaveBudgetMultiplier": 1.5,
    "coopTrickleSizeBonus": 1,
    "coopEnemyCap": 600,
    "interWaveGapBase": 90,
    "interWaveGapFloor": 50,
    "gapCompressionPerWave": 2,
    "trickleIntervalSeconds": 12,
    "trickleSize": [1, 2],
    "waveBudgetMultiplier": 1.0
  }
}
```

### 14.2 New: Session Config

The lobby communicates bootstrap parameters:

```json
{
  "sessionMode": "coop",
  "difficulty": "normal",
  "seed": 42,
  "players": [
    { "playerID": 1, "displayName": "Player 1" },
    { "playerID": 2, "displayName": "Player 2" }
  ]
}
```

---

## 15. Integration Points

### 15.1 Run Bootstrap (`run_bootstrap_session_init.md`)

- `WorldState.bootstrap()` gains `sessionMode` and `playerSlots` parameters.
- Grace period duration reads co-op bonus from content data.
- Starting resources remain unchanged for co-op.

### 15.2 Wave & Threat System (`wave_threat_system.md`)

- Wave budget multiplied by `coopWaveBudgetMultiplier` when `sessionMode == .coop`.
- Trickle spawn counts increased by `coopTrickleSizeBonus`.
- Enemy cap raised to `coopEnemyCap`.
- Manual wave trigger requires both players' consent via `readyForWave`.

### 15.3 Economy System (`factory_economy.md`)

- No changes. The shared economy model works as-is.
- Build costs deducted from global pool regardless of which player issued the command.
- Per-structure buffers, conveyor logistics, and power all operate on the shared state.

### 15.4 Building Specifications (`building_specifications.md`)

- `Entity.placedBy` added for attribution. No gameplay impact.
- All existing placement validation applies identically to both players.
- Wall network ammo pools remain shared across the entire network.

### 15.5 Combat Rendering (`combat_rendering_vfx.md`)

- Ping markers need visual rendering (colored ring at grid position with type icon).
- Partner cursor rendering (colored crosshair with optional build preview ghost).
- Player color tinting on structures (subtle, shader-driven).

---

## 16. Files Changed

### Modified

| File | Change |
|---|---|
| `Sources/GameSimulation/SimulationTypes.swift` | `SessionMode`, `PlayerSlot`, `ActivePing`, `PingRequest`. `placedBy` on `Entity`. `ping`/`readyForWave` on `CommandPayload`. Co-op fields on `RunState`. `sessionMode`/`activePings` on `WorldState`. |
| `Sources/GameSimulation/Systems.swift` | `CommandSystem`: thread `placedBy`, handle new payloads. `WaveSystem`: co-op scaling. New `PingSystem`. |
| `Sources/GameSimulation/EntityStore.swift` | `spawnStructure` gains `placedBy` parameter. |
| `Content/bootstrap/difficulty.json` | Co-op modifier fields. |
| `Package.swift` | Add `GameNetworking` target. |

### Added

| File | Purpose |
|---|---|
| `Sources/GameNetworking/CoopTransport.swift` | `NWConnection` wrapper for sending/receiving packets. |
| `Sources/GameNetworking/CoopTickScheduler.swift` | Lockstep coordinator. |
| `Sources/GameNetworking/SessionTypes.swift` | `TickCommandPacket`, `CursorUpdate`, session enums. |
| `Sources/GameNetworking/LobbyManager.swift` | Bonjour discovery, lobby state machine. |
| `Tests/GameNetworkingTests/` | Lockstep, serialization, and conflict tests. |

---

## 17. Risk Assessment

| Risk | Impact | Mitigation |
|---|---|---|
| Determinism bugs (floating-point, hash order) cause desyncs | High — game unplayable | Extensive determinism tests exist. Add dual-engine co-op tests. Periodic hash checks every 5s. |
| iOS background kills during co-op | Medium — disconnects partner | Background task keep-alive. Robust snapshot reconnection within 30s. |
| NAT traversal failure on cellular | Medium — some players can't connect | Relay fallback for all internet sessions. |
| Shared economy frustration ("partner wastes resources") | Medium — player friction | Attribution colors. Ping system for requests. Quick-chat. Design leans into cooperation. |
| Wave scaling too hard/easy | Low — tunable | All values in content data. Adjust through playtesting. |

---

## 18. Open Questions

| Question | Recommendation | Status |
|---|---|---|
| Should starting resources increase for co-op? | No for v1. Two players build one factory. Revisit if playtesting reveals tight opening. | Recommended |
| Should co-op support more than 2 players later? | Architecture supports N players (PlayerID is an integer, commands sort by actor). 3–4 player support is a balance and UX challenge, not a technical one. | Deferred |
| Should disconnected player's structures have special behavior? | No — structures are part of the shared base, not personal property. | Recommended |
| Dedicated relay server or peer-to-peer? | Peer-to-peer with relay fallback. Minimizes infrastructure cost. | Recommended |
| Should there be co-op-specific achievements? | Yes, in Phase 3 via Game Center. Examples: "Survive wave 10 in co-op", "Build 50 structures as a team." | Deferred |
