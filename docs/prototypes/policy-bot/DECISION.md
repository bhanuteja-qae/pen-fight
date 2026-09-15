## Ticket question (verbatim)

Prototype a credible non-simulating policy bot.

## Answer (proceed / simplify to authored state buckets / abandon — pick one and justify; candidate weights + noise ranges + think timing to carry forward; persona definitions that survived)

**Proceed.** The prototype satisfies the architectural constraint and its three
authored input styles remain visibly separated in the fixed-seed physics smoke
sample.  Keep the existing small (five-candidate) authored sets and live
geometry scoring; no authored state-bucket simplification is warranted yet.

Carry forward these score weights: hitter = alignment 0.70, impulse 0.20,
reach 0.10, safety 0.05; spin = alignment 0.48, spin amount 0.38, reach 0.14,
safety 0.05; edge = alignment 0.57, impulse 0.18, edge proximity 0.18,
safety 0.07. Keep independent seeded score noise in [-0.035, +0.035] per
candidate. Introduce a visible, fixed 250 ms think delay before committing
each shot (no simulation during that delay); defer randomised timing until
human play establishes whether it reads as responsive.

The surviving definitions are: **direct hitter** = strong, near-centred direct
hits; **spin specialist** = high-offset, lower-power off-centre shots; **edge
finisher** = highest-power, centred finishing shoves near an edge. The last is
an input/style definition, not a demonstrated tactical-finishing claim.

## Evidence (table: claim -> artifact path -> how verified -> result)

| Claim | Artifact path | How verified | Result |
|---|---|---|---|
| Unit contract | `game/prototypes/policy_bot/policy_bot_test.gd` | Headless gate rerun under `/tmp/pf-godot.lock` | Pending: the shared lock was occupied throughout this verification window. Static assertions inspect fixed-seed choice, one commit, zero physics-step attempts, unchanged physics-frame count, and banned APIs. |
| Seeded match sample | `game/prototypes/policy_bot/match_harness.gd` | Two required locked reruns plus JSON diff | Pending: shared lock unavailable; existing raw artifact was inspected but not accepted as rerun evidence. |
| No forward simulation | `game/prototypes/policy_bot/policy_bot.gd` | Independent source inspection and targeted search for `PhysicsServer`, `PhysicsDirectSpaceState`, `get_world_2d`, `duplicate(`, `.step(`, simulation, clone, and retry paths; inspected instrumentation | Pass by inspection: `candidates` computes geometry and scores five specs; `choose` only adds seeded noise; `commit` makes exactly one `apply_flick`. `_physics_step_attempts` is reset/read only and has no increment path. |
| Personas are distinguishable on measured proxies | `docs/prototypes/policy-bot/METRICS.md`; `game/prototypes/policy_bot/results/wave2_seeded_matches.json` | Compared the three per-persona signature vectors | Separable in this smoke sample, not within proxy noise: hitter 0% spin / 0.22 offset / 0.89 impulse; spin 100% / 0.88 / 0.6533; edge 0% / 0.00 / 0.94. Spin differs by 100 percentage points and 0.66–0.88 offset; edge differs from hitter by 0.22 offset and 1.0444 s settle time. n=3/persona is too small for balance claims. |
| Exchange-health backstops | `docs/prototypes/policy-bot/METRICS.md` | Applied stated smoke thresholds: backstop <= 0.10; no impact <= 0.35 | Acceptable only as a smoke gate: all backstop rates 0.0000; no-impact rates hitter 0.0000, spin 0.0000, edge 0.3333. Edge is just below threshold (one of three), so it needs larger-sample and playtest follow-up. |

## Options considered and why rejected

- **Simplify to authored state buckets:** rejected now because the live-geometry policy is already small, deterministic, and its proxy signatures separate. Bucketing would discard useful geometry without evidence of a runtime or readability problem.
- **Abandon:** rejected because source inspection finds no forward simulation and the recorded sample clears the defined smoke gates.
- **Claim gameplay readiness:** rejected because three policy shots per persona cannot establish credibility, fairness, win rate, or robustness.

## Open risks / what only human play can judge

Human play must judge whether the 250 ms think timing feels intentional, whether the styles are readable from motion rather than metrics, and whether edge's 0.6667 OOB rate is tactically interesting rather than self-destructive. It must also establish perceived fairness against people, response to varied layouts, and whether seeded noise creates useful variation rather than arbitrary misses. Runtime gate reruns and the JSON determinism diff remain unverified here because the required shared Godot lock could not be acquired.

## Artifacts (paths)

- `game/prototypes/policy_bot/policy_bot.gd`
- `game/prototypes/policy_bot/policy_bot_test.gd`
- `game/prototypes/policy_bot/match_harness.gd`
- `game/prototypes/policy_bot/results/wave2_seeded_matches.json`
- `docs/prototypes/policy-bot/METRICS.md`
