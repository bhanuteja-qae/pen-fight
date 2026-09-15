# CONTRACTS — policy-bot prototype

**Wayfinder ticket:** *Prototype a credible non-simulating policy bot* (issue #9)
**Pinned before Wave 1. Any interface change requires orchestrator approval.**
Repo `~/pen-fight` @ `main` · Godot 4.7.2 headless · offline only · no production behavior changes.

## Ground rules (all agents)

- **Own exactly the files listed for your wave. Never edit a file you do not own.** Do NOT edit
  `game/scripts/*` (production), `game/scenes/*`, `game/tests/*`, `project.godot`, or another
  ticket's prototype dir.
- Read first: `AGENTS.md`, `CONTEXT.md`, `docs/design/multiplayer-audit.md`, the ticket body
  (GitHub issue #9), and `game/scripts/auto_flick.gd` (the debug baseline you must not break).
- Serialize every Godot invocation behind `flock /tmp/pf-godot.lock -c '...'`.
- **Do NOT commit, do NOT push, do NOT run the full test suite.** Print raw gate output at the end.
- **No forward simulation.** The policy reads live geometry, scores a small authored candidate set,
  adds seeded noise, and commits ONE shot through the real physics path. It must never step/clone
  the physics world, never retry a result, never change physics after launch.
- All randomness through `RandomNumberGenerator` with explicit seeds.

## Deliverables & ownership

### Wave 1 — owner: Codex (gpt-5.6-terra)

1. **NEW** `game/prototypes/policy_bot/policy_bot.gd` — reactive geometric policy.

   ```gdscript
   class Snapshot:      # plain data, built by the caller
       var pen_pos: Vector2
       var pen_rot: float
       var opp_pos: Vector2
       var opp_rot: float
       var table_rect: Rect2
       var oob_margin: float
   class Candidate:
       var impulse: float          # human power fraction 0..1 (same scale as apply_flick)
       var contact_offset: float   # offset along the pen's long axis, px
       var spin: float             # -1..1 (maps to the existing spin arc)
       var score: float
   static func candidates(s: Snapshot, persona: String) -> Array[Candidate]   # "hitter" | "spin" | "edge"
   static func choose(s: Snapshot, persona: String, rng: RandomNumberGenerator) -> Candidate
   static func commit(candidate: Candidate, pen_body: Node) -> void   # ONE shot, real physics path
   ```

   The candidate set is small and authored (≤ 12 candidates); scoring is deterministic; persona
   differences come from scoring weights + candidate generation + seeded noise, never from physics
   advantages.
2. **NEW** `game/prototypes/policy_bot/policy_bot_test.gd` — headless test: fixed-seed determinism
   (same snapshot + seed → same `choose` result), single-commit (exactly one physics impulse per
   decision), no-simulation guard (policy module performs no physics stepping — assert by
   instrumentation/counters). Prints `policy_bot_test: ALL PASS`.

### Wave 2 — owner: Codex (gpt-5.6-terra)

3. **NEW** `game/prototypes/policy_bot/match_harness.gd` — seeded headless matches:
   persona vs AutoFlick baseline, and persona vs persona. Fixed metric keys: `backstop_rate`,
   `no_impact_rate`, `oob_rate`, `shots`, `mean_impulse`, `mean_contact_offset`, `spin_usage`,
   `settle_time_s`. JSON out to `game/prototypes/policy_bot/results/`.
4. **NEW** `docs/prototypes/policy-bot/METRICS.md` — tables + per-persona signature vectors
   (hitter / spin / edge) with the evidence needed to judge distinguishability.

### Wave 3 — owner: Codex (gpt-5.6-terra)

5. **NEW** `docs/prototypes/policy-bot/DECISION.md` — verdict: proceed / simplify to authored state
   buckets / abandon; backstop & no-impact acceptability; signature distinguishability; think-timing
   and noise ranges to carry forward. Evidence table + open risks.
6. **NEW** `docs/prototypes/policy-bot/RESOLUTION-COMMENT.md` — the issue-comment draft (orchestrator posts it).

## Gates (paste raw output of each)

```bash
cd ~/pen-fight/game
flock /tmp/pf-godot.lock -c 'DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --editor --quit --import .'
flock /tmp/pf-godot.lock -c 'DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 240 ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://prototypes/policy_bot/policy_bot_test.gd'
flock /tmp/pf-godot.lock -c 'DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 600 ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://prototypes/policy_bot/match_harness.gd'
```

Determinism gate (Wave 2/3): run the harness twice with the same seeds and `diff` the JSON — must be identical.

## Non-goals

No production edits, no ML/RL, no Monte Carlo rollouts, no network, no build/export work.
