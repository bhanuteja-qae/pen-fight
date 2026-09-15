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

## Ground truth from the repo (read; never modify)

- `game/scripts/pen_body.gd`: `apply_flick(impulse_dir: Vector2, power: float, contact_offset: float = 0.0)`
  — `power` is a **0..1 fraction**, scaled inside by `MAX_IMPULSE = 1600.0`; `contact_offset` is a
  **fraction of half-length** (-1 tip .. 0 centre .. 1 cap), not px.
- Settle thresholds: 6.0 px/s, 0.4 rad/s, 0.25 s debounce; `MOVED_LINEAR_VEL = 25.0`.
- Geometry: pen capsule radius 5.0, half-length 85.0 (180×10 on screen); table `TABLE_RECT` 1180×640;
  OOB = both capsule endpoints outside the rect grown by -(radius + 8.0).
- A pen needs a `CollisionShape2D` (CapsuleShape2D) child and a node named `Table` carrying a
  `RectangleShape2D` (1180×640) so the OOB geometry resolves — construct both in code.
- Test convention (`game/tests/*.gd`): `extends SceneTree`, `_init()` → `quit(0|1)`, success line
  `"<name>: ALL PASS"`. Physics-dependent tests drive `SceneTree.physics_frame` at 60 Hz.

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
