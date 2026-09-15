# CONTRACTS — pen-profiles prototype

**Wayfinder ticket:** *Prototype four readable pen profiles and fair hot-seat rules* (issue #8)
**Pinned before Wave 1. Any interface change requires orchestrator approval.**
Repo `~/pen-fight` @ `main` · Godot 4.7.2 headless · offline only · no production behavior changes.

## Ground rules (all agents)

- **Own exactly the files listed for your wave. Never edit a file you do not own.** Do NOT edit
  `game/scripts/*` (production physics), `game/scenes/*`, `game/tests/*`, `project.godot`, or another
  ticket's prototype dir.
- Read first: `AGENTS.md`, `CONTEXT.md`, `docs/design/core-loop.md`, `docs/design/feature-priorities.md`,
  and the ticket body (GitHub issue #8).
- Serialize every Godot invocation behind `flock /tmp/pf-godot.lock -c '...'`.
- **Do NOT commit, do NOT push, do NOT run the full test suite.** Print raw gate output at the end.
- Physics levers are applied **only** via `RigidBody2D` runtime properties (`mass`, `linear_damp`,
  `angular_damp`) on a locally constructed pen. No production edits, no size changes (one footprint in V1).
- All randomness through `RandomNumberGenerator` with explicit seeds. Every run must be re-runnable.

## Deliverables & ownership

### Wave 1 — owner: OpenCode (deepseek-v4.1-flash)

1. **NEW** `game/prototypes/pen_profiles/profile_sweep.gd` — headless sweep runner.

   ```gdscript
   class SweepConfig:
       var profile_name: String   # "cobalt_control" | "graphite_anchor" | "ivory_glide" | "amber_spin"
       var mass: float            # 1.0 = current baseline
       var linear_damp: float     # baseline value from the shipped pen body
       var angular_damp: float
       var seed: int
       var shots: int
   static func run(config: SweepConfig) -> Dictionary   # per-shot rows + aggregate
   static func write_json(result: Dictionary, path: String) -> void
   ```

   Fixed metric keys per shot: `travel_px`, `peak_speed`, `settle_time_s`, `contact_impulse`,
   `angular_travel_deg`, `dispersion_deg`, `self_oob` (bool). Aggregate adds `self_oob_rate`,
   `dispersion_deg_p50`, `travel_px_p50`.
   Determinism: identical `SweepConfig` → byte-identical JSON.
2. **NEW** `game/prototypes/pen_profiles/noise_floor.gd` — runs ONE baseline config K=20 times
   (same seed set), prints per-metric mean/stddev, writes JSON. This is the signal-vs-noise yardstick.
3. **NEW** `game/prototypes/pen_profiles/README.md` — how to run + the measured noise floor table.

### Wave 2 — owner: OpenCode (deepseek-v4.1-flash)

4. **NEW** `game/prototypes/pen_profiles/results/*.json` — one file per sweep run (mass lever ×
   ≥4 values; linear damping × ≥4; angular damping × ≥4; Cobalt baseline reference).
5. **NEW** `docs/prototypes/pen-profiles/SWEEPS.md` — tables + explicit **noise-vs-signal calls**
   (a parameter range is "measured" only if the effect exceeds the Wave-1 noise floor).

### Wave 3 — owner: OpenCode (deepseek-v4.1-flash)

6. **NEW** `docs/prototypes/pen-profiles/DECISION.md` — readable, non-dominant identities; final
   ranges; Classic equal-physics default vs optional Pen Powers; profile locking; disclosure;
   mirror play; counter-pick fairness. Evidence table + open risks.
7. **NEW** `docs/prototypes/pen-profiles/RESOLUTION-COMMENT.md` — the issue-comment draft (orchestrator posts it).

## Gates (paste raw output of each)

```bash
cd ~/pen-fight/game
flock /tmp/pf-godot.lock -c 'DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --editor --quit --import .'
flock /tmp/pf-godot.lock -c 'DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 300 ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://prototypes/pen_profiles/noise_floor.gd'
flock /tmp/pf-godot.lock -c 'DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 600 ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://prototypes/pen_profiles/profile_sweep.gd'
```

Budget rule: if a run would exceed its timeout, reduce `shots`, never seeds.

## Non-goals

No production physics edits, no pen size changes, no UI work, no network, no build/export work.
