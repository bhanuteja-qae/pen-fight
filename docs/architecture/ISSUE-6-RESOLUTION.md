## Issue #6 — frozen match and shot contract

Decision frozen in `docs/architecture/MATCH-CONTRACT.md`.
Implementation status: **complete** — landed in `15bfca1`; evidence below.

### Contract

- `Participant`, `MatchConfig`, and `ShotCommand` are plain data. `Participant` is `{ slot, kind, display_name, controller, pen_model, pen_profile, bot_profile }`; V1 permits local-player/human with no bot profile, or rival/bot with a registered bot profile. A `MatchConfig` is validated once at match start and remains an immutable per-match snapshot.
- The two internal slots are exactly `red` and `blue`; UI resolves `Participant.display_name` and never treats a slot as identity.
- `MatchConfig` is `{ mode, ruleset, best_of, seed, participants }`: best-of is `1/3/5/7`, participants are exactly red then blue, and requested seed `0` resolves at construction to a logged, nonzero effective seed. The frozen config never exposes `0`. This seeds software randomness, not a promise of bit-deterministic Godot physics.
- Classic resolves every model to the `control` profile. Pen Powers resolves `cobalt/control`, `graphite/anchor`, `ivory/glide`, and `amber/spin`, locked for the match.
- `ShotCommand` is `{ slot, normalized direction, power 0..1, contact_offset -1..1, source }`. `contact_offset` is part of the shared physics contract. `source` (`human|bot|harness`) is attribution only, never permission or a bypass.

### One atomic submission boundary

Human input and `AutoFlick` must both build a `ShotCommand` and call `Main._submit_shot`. The boundary validates the entire command and session first: active config/session, known slot/source, finite unit direction, finite ranges, `AIM`, active slot, open gate/modal/lock state, and a resolvable active pen.

A rejection warns and is a hard no-op—no turn mutation, physics, feedback, repair, clamp, retry, or queue. One accepted command performs exactly:

```gdscript
turn_state.on_flick(cmd.direction * cmd.power)
pen.apply_flick(cmd.direction, cmd.power, cmd.contact_offset)
```

`TurnState` stays unchanged and records normalized intent (`direction * power`) with **no 1600 scaling**. `PenBody` alone applies physical `MAX_IMPULSE` scaling. The first accepted command leaves `AIM`, so duplicates reject.

The existing separate `_on_auto_flick_requested` application path is removed in `15bfca1`; the harness connects to the same `_submit_shot` boundary. `AutoFlick` remains a harness. There is no shipped production bot: `game/prototypes/policy_bot/PolicyBot` remains prototype-only until issue #10 owns promotion, at which point its adapter must use the same boundary.

### Migration and ownership

Implementation order is fixed: add/validate the three data shapes; build the current hot-seat/classic snapshot from loaded settings; keep `TurnState.new(["red", "blue"], ...)` unchanged; add `_submit_shot`; route human and `AutoFlick` through it; remove duplicated runtime orchestration; then add parity, immutability, seed, rejection, and duplicate-submission tests.

Issue #7 owns persistence and legacy-key migration. This decision does not persist `MatchConfig`, invent `last_match.cfg`, or rename `pen_red`, `pen_blue`, `matches_won_red`, or `matches_won_blue`.

Acceptance call-site scans are scoped to runtime/session orchestration. Low-level tests, physics probes, and prototype rigs intentionally call `TurnState`/`PenBody` directly and are not false failures; prototype `PolicyBot.commit()` remains excluded unless promoted by #10.

### Evidence

- Decision/audit grounding: base `5a3c78d`; `AimInput` already emits split normalized values, `TurnState` stores its vector unchanged, `PenBody` owns `MAX_IMPULSE`, and current human/AutoFlick handlers duplicate orchestration.
- Implementation diff: `15bfca1` — `Main._on_flick_ready` human adapter,
  `Main._submit_shot` validation + atomic commit, session-start `MatchConfig`
  snapshot, `AutoFlick` emitting `ShotCommand(source="harness")` at fire time,
  integration tests routed through the boundary, prototype harness adapted to
  the new payload only (still prototype scope; #10 owns any production bot
  adapter).
- Contract/unit validation: `match_contract_test: ALL PASS` (config
  validation, immutability, seed resolution, command validation) and
  `main_shot_submission_test: ALL PASS` — one accepted commit
  (`TurnState.state().last_impulse == direction * power`; the physical impulse
  scaled exactly once, inside `PenBody`, by `MAX_IMPULSE`), 15 rejection
  classes as hard no-ops (missing config, missing command, unknown slot,
  unknown source, non-unit direction, non-finite direction, power above
  range, contact below range, wrong active slot, input lock, handoff gate,
  blocking settings modal, ended match, missing active pen, duplicate
  submission), and settings changes after match start not mutating the
  active config.
- Human-vs-`AutoFlick` parity evidence: `main_shot_submission_test`
  producer-parity case — the same slot/direction/power/contact values
  committed through the human adapter and through `AutoFlick.fire_now`
  produced identical `TurnState.state().last_impulse` and identical
  `PenBody.flicked` impulses.
- Scoped runtime call-site scan: `grep "\.on_flick(\|\.apply_flick("
  game/scripts/` reports only `main.gd:439-440`, both inside `_submit_shot`;
  `game/scripts/turn_state.gd` is byte-identical to `5a3c78d` (`git diff
  5a3c78d..15bfca1 -- game/scripts/turn_state.gd` is empty).
- Integration suite (240 Hz): `auto_flick_test` PASS; `display_name_test`
  6/6; `series_record_test` 4/4; `settings_test` 7/7; `touch_input_test`
  6/6; `aim_overlay_smoke` PASS OK; 20-round soak PASS —
  `rounds_gate_test: 20-round gate sustained (rounds=20 red=8 blue=12,
  shots=54, 96.4s)`, identical to the pre-migration baseline (the migration
  is behavior-neutral on the shipped physics).
- Scope notes: player-facing names keep resolving through
  `Main._display_name` — the same resolver that fills
  `Participant.display_name` into the match snapshot.
