# Attributed rival-matrix re-measurement (issue #10)

Measured 2026-09-16 with `game/prototypes/policy_bot/rival_matrix.gd` (fixed seeds, headless, serialized under the flock gate). Raw results: `game/prototypes/policy_bot/results/rival_matrix.json`.

Why this exists: `METRICS.md` records an `oob_rate` that cannot say *which* pen left the table, so an OOB caused by the opponent's own flick reads the same as one caused by the persona's shove. This run attributes every OOB to a pen id and records who won each resolved round.

# Rival matrix measurement

This scratch probe replays the frozen match rig with four shots per series and
records every `PenBody.out_of_bounds` UID before reading `TurnState.state()`.
`oob_pen` joins both UIDs with `+` if a same-tick double-OOB occurs; in that
case `oob_was_self` is true when the shooter is one of the UIDs. The totals
count self and opponent OOB independently, so a double-OOB contributes to both
pen-attributed columns. `round_winner` is blank unless `round_over` is true.

## Roll-up matrix

| Pairing | rounds won red | rounds won blue | knockouts | self-OOB | opponent-OOB | forfeits | settle s |
|---|---:|---:|---:|---:|---:|---:|---:|
| hitter vs auto | 2 | 0 | 1 | 1 | 1 | 0 | 6.3958 |
| spin vs auto | 0 | 0 | 0 | 0 | 0 | 0 | 8.0167 |
| edge vs auto | 2 | 0 | 0 | 2 | 0 | 0 | 4.5833 |
| hitter vs spin | 1 | 1 | 1 | 1 | 1 | 0 | 4.8458 |
| hitter vs edge | 0 | 0 | 0 | 0 | 0 | 0 | 8.0167 |
| spin vs edge | 0 | 2 | 2 | 0 | 2 | 0 | 5.3792 |

## Gate command

```sh
flock /tmp/pf-godot.lock -c 'DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 240 ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://prototypes/policy_bot/.scratch/rival_matrix/rival_matrix.gd'
```

Raw output tail, verbatim:

```text
ERROR: Failed to open 'user://logs/godot2026-09-16T05.19.14.log'.
   at: copy (core/io/dir_access.cpp:429)
ERROR: Failed to open log file for writing: user://logs/godot.log
   at: rotate_file (core/io/logger.cpp:169)
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

rival_matrix: PASS — 6 seeded series, 24 shots; wrote res://prototypes/policy_bot/.scratch/rival_matrix/results/rival_matrix.json
```

## Verdicts

In this fixed sample, edge is the hardest persona to beat: it wins all four
resolved rounds in its two pairings (2 vs auto, 2 vs spin), with 2 knockouts
against spin and no edge self-OOB. Two additional edge-vs-auto wins are caused
by auto self-OOB. Spin is easiest to beat among the personas: it loses both
resolved rounds to edge and wins none in its auto pairing; hitter is 3-1 in
resolved rounds, with its hitter-vs-edge series unresolved.

## Could not measure

No stalemate or idle forfeit occurred in these 24 shots; no same-tick
double-OOB occurred; and no knockout occurred in edge-vs-auto. The probe does
not measure human readability, fairness against human play, or robustness
outside these six fixed seeds and the frozen table/physics setup.
