# PRD: HQ Directives (Mid-Run Objectives)

Status: Proposed gameplay depth feature for mid-run pacing  
Owner: Product + Simulation + UI  
Last updated: 2026-02-19

## Why This Is Needed Now
Runs currently have strong early pressure ramp and strong late escalation, but mid-run can flatten into pure throughput maintenance with limited short-horizon goals.

Optional HQ directives add tactical objectives that create decision spikes without introducing meta progression or violating deterministic simulation.

## Current-State Ground Truth
- Run loop already tracks wave index, economy production, and combat outcomes in deterministic systems.
- `RunSummarySnapshot` captures end-of-run metrics but there is no in-run objective layer.
- Existing telemetry and events can support directive progress tracking with minimal architecture risk.

## Goals
- Add optional, time-bounded objectives that shape short-term strategy.
- Reward completion with meaningful but bounded in-run boosts.
- Keep deterministic behavior and replay stability.
- Improve mid-run variety without adding narrative or campaign overhead.

## Non-Goals
- No persistent account progression.
- No random quest dialogue tree.
- No punitive failure states (missing a directive should not snowball the player).

## Design Grounding From Existing Games
| Game | Proven Pattern | Adaptation For Factory Defense |
|---|---|---|
| Against the Storm | Optional orders create strategic pivots and reward planning under pressure. | Offer optional directives that reward specific factory/defense behaviors. |
| Riftbreaker | Mid-mission objectives break monotony and redirect player attention. | Trigger wave-index-based directives to create controlled pacing spikes. |
| They Are Billions | Side goals can justify risk-taking and map expansion. | Reward directives with finite tactical boosts that help survival, not permanent scaling. |

## Player Experience Targets
- Around waves 3-8, player receives occasional HQ tasks that encourage adaptation.
- Player can ignore directives with no penalty.
- Completing a directive feels immediately useful but not mandatory.

## Core Design

### 1. Directive Lifecycle
Directive states:
- `pendingOffer`
- `active`
- `completed`
- `expired`
- `dismissed`

Rules:
- Max one active directive at a time in v1.
- Offer windows are tied to wave milestones (for example: wave 2, 4, 6, 8).
- Directive expires after a deterministic time limit or wave deadline.
- Offer flow is explicit but lightweight:
  - Offer appears in `pendingOffer`.
  - Player can `accept` or `dismiss`.
  - If no action for configured timeout, it auto-dismisses (no penalty).

### 2. Objective Families
- Production burst: produce X item before wave Y.
- Logistics stability: keep output-blocked structures under threshold for duration.
- Defense readiness: maintain minimum wall network ammo reserve through a surge.
- Infrastructure target: build and keep alive N structures of a type for duration.
- Recovery objective: restore HQ health by delivering repair kits after damage event.

### 3. Reward Families
Rewards are one-shot, finite, and non-compounding:
- HQ supply cache (`plate_iron`, `gear`, `ammo_light`, etc.).
- Wall network ammo injection (capped quantity).
- Short research speed boost (time-limited, additive cap).
- Emergency currency grant (bounded).

No reward can permanently alter baseline economy formulas.

### 4. Fairness and Feasibility Filters
Before offering a directive, validate:
- Required tech/buildings are already unlocked or realistically buildable.
- Required ore rings are revealed if objective depends on them.
- Objective does not conflict with current run phase constraints.

If invalid, roll next candidate deterministically.

### 5. Anti-Exploit Rules
- Progress counters are monotonic per directive instance.
- Reversible actions cannot farm completion (for example: build/demolish loops).
- Reward can trigger once per directive ID per run.

## Data Contract Changes

### A. New `directives.json`

```json
{
  "directives": [
    {
      "id": "ammo_buffer_wave4",
      "activation": { "type": "waveReached", "wave": 2 },
      "objective": {
        "type": "itemStockAtDeadline",
        "itemID": "ammo_light",
        "quantity": 120,
        "deadlineWave": 4
      },
      "reward": {
        "type": "hqSupplyCache",
        "items": [
          { "itemID": "plate_steel", "quantity": 10 },
          { "itemID": "gear", "quantity": 8 }
        ]
      },
      "weight": 10
    }
  ]
}
```

### B. Difficulty scaling knobs
Add optional multipliers in `difficulty.json`:

```json
{
  "hard": {
    "directiveTargetMultiplier": 1.15,
    "directiveDurationMultiplier": 0.9,
    "directiveRewardMultiplier": 0.9
  }
}
```

## Runtime Architecture Changes

### 1. Simulation types (`SimulationTypes.swift`)
Add:
- `DirectiveObjectiveDef`
- `DirectiveRewardDef`
- `DirectiveRuntimeState`
- `DirectiveProgressState`
- `DirectiveSystemState`

Embed in `RunState` or new `ObjectiveState` attached to `WorldState`.

### 2. New event kinds
- `directiveOffered`
- `directiveStarted`
- `directiveProgressed`
- `directiveCompleted`
- `directiveExpired`
- `directiveDismissed`

### 3. Command surface additions
Extend `CommandPayload` with:
- `acceptDirective(directiveID: String)`
- `dismissDirective(directiveID: String)`

`CommandSystem` validates that command ID matches currently offered directive and resolves deterministically.

### 4. New system
Add `DirectiveSystem` with responsibilities:
- Offer selection at activation milestones.
- Progress evaluation each tick.
- Completion/expiry resolution.
- Reward application.

Suggested order: after Economy/Combat updates so progress uses final tick state.

### 5. Runtime controller integration
`GameRuntimeController.consumeSummaryEvents(...)` can accumulate directive completion stats into run summary extension.

## UI Integration

### Files
- `Sources/GameUI/HUDModels.swift`
- `Sources/GameUI/FixedHUDBar.swift`
- `Sources/FactoryDefense/main.swift`

### Components
- Compact directive card in HUD overlay:
  - title
  - progress
  - deadline
  - reward preview
- Optional collapse/minimize toggle.
- Completion toast with reward list.

UX constraints:
- No modal interruption.
- No overlap with critical warnings.

## Implementation Plan

### Phase 1: Data and deterministic selection
- Add `directives.json` schema/types/validation.
- Deterministic selection logic (seed + wave index + weighted choice).
- Feasibility filter pass.

### Phase 2: Runtime state and evaluation
- Implement `DirectiveSystem` and progress evaluators.
- Implement completion/expiry transitions and events.
- Apply one-shot rewards through existing inventory/wall network channels.

### Phase 3: HUD presentation
- Add directive card and progress projection.
- Add completion/expiry feedback.

### Phase 4: Balance and exploit hardening
- Tune thresholds/reward values.
- Add exploit tests for reversible actions and duplicate rewards.

## Test Strategy
- Unit tests for each objective evaluator.
- Deterministic selection tests across seeds and wave checkpoints.
- Reward application tests for inventory and wall-network injection.
- Expiry behavior tests.
- Replay tests to confirm objective timelines match exactly.

## Telemetry Plan
Track:
- `directivesOffered`
- `directivesAccepted`
- `directivesCompleted`
- `directivesExpired`
- `completionTimeByDirectiveID`
- `waveSurvivalDeltaAfterReward`

Success targets:
- Mid-run action diversity increases (more varied build/route decisions).
- Completion rates are neither trivial nor impossible (target band after tuning).

## Risks and Mitigations
- Risk: directives feel mandatory.
  - Mitigation: bounded rewards and explicit no-penalty failure.
- Risk: impossible directives in current run state.
  - Mitigation: strict feasibility filters before offer.
- Risk: reward inflation destabilizes balance.
  - Mitigation: reward caps and difficulty multipliers.
- Risk: extra HUD noise.
  - Mitigation: one-card limit and minimize control.

## Acceptance Criteria
- At least 8 directive templates implemented across multiple objective families.
- Selection and progression are deterministic and replay-stable.
- Failure has no direct penalty.
- Rewards are one-shot and bounded; no permanent economy breakpoints.
- HUD communicates active directive clearly without occluding play.

## Stretch Follow-Ups (Post v1 closure)
- Co-op shared directives with role-aware progress attribution.
- Directive chains (multi-step objective arcs) for long runs.
- Player preference toggles for directive frequency.
