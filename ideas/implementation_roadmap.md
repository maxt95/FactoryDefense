# Ideas Roadmap: Priority and Sequencing

Last updated: 2026-02-19  
Scope: Implementation order for current idea PRDs in `/ideas`

## Recommendation Summary
Implement in this order:
1. `ore_reveal_renewal_loop.md`
2. `bottleneck_alerts_flow_inspector.md`
3. `wave_telegraph_intel.md`
4. `hq_directives_objectives.md`

This order front-loads foundational economy correctness, then player readability, then tactical clarity, then optional pacing depth.

## Priority Matrix
| Idea | Player Impact | Engineering Risk | Dependencies | Why This Position |
|---|---|---|---|---|
| Ore Ring Reveal + Renewal | Very high | Medium-high | Tech node gating + content schema updates | Closes a locked v1 gap and prevents economy dead-end failures. |
| Bottleneck Alerts + Flow Inspector | High | Medium | None (uses existing runtime signals) | Immediately improves decision quality and supports future balancing. |
| Wave Telegraphs + Threat Intel | Medium-high | Medium | Wave telemetry + HUD bandwidth | Best after alert foundations so UI stays coherent and non-noisy. |
| HQ Directives | Medium | Medium-high | Stable telemetry + readability baseline | Most flexible feature; easiest to tune once core loops are clear. |

## Dependency Graph
- Ore lifecycle unlocks stronger mid/late economy trajectories.
- Bottleneck system provides diagnostics needed to tune ore renewal and telegraph impact.
- Telegraph feature should reuse bottleneck/HUD conventions to avoid fragmented warning UX.
- HQ directives should consume the same telemetry and objective-state surfaces for tuning.

## Execution Slices

### Slice A: Economy Continuity (Ore Lifecycle)
- Deliverables:
  - Ring reveal state machine.
  - Renewal queue and deterministic spawn.
  - HUD ring state and survey timer.
- Exit gate:
  - Replay-stable ring/reveal lifecycle in wave 1-12 simulations.

### Slice B: Root-Cause Clarity (Bottlenecks)
- Deliverables:
  - Signal taxonomy + aggregation.
  - Alert strip and inspector status lines.
  - Telemetry counters for active bottlenecks.
- Exit gate:
  - Top critical bottleneck is visible within 2s of onset and non-occluding.

### Slice C: Pre-Surge Agency (Telegraphs)
- Deliverables:
  - Telegraph timing/state in `WaveSystem`.
  - Composition tags and ingress sectors.
  - Threat intel HUD panel and map arcs.
- Exit gate:
  - Deterministic telegraph payload for authored and procedural waves.

### Slice D: Mid-Run Variety (Directives)
- Deliverables:
  - Directive schema and deterministic selector.
  - Runtime evaluator + bounded rewards.
  - Optional HUD card + accept/dismiss commands.
- Exit gate:
  - Directive completion rates in target band without reward inflation.

## Suggested Validation Cadence
After each slice:
- Run `swift test`.
- Refresh golden replay where schema/state changed.
- Capture at least one telemetry scenario run and compare to pre-slice baseline.

## De-scope Levers
If delivery pressure increases, cut in this order:
1. HQ directives stretch templates.
2. Telegraph authored custom notes (keep derived tags only).
3. Bottleneck overlay heatmap (keep HUD + inspector only).
4. Ore visual polish (keep simulation correctness first).

## Done Definition For This Roadmap
- Core v1 ore lifecycle gap is closed.
- Players can identify and react to bottlenecks during combat.
- Surge prep has actionable pre-wave intel.
- Mid-run directive layer is optional, deterministic, and balance-safe.
