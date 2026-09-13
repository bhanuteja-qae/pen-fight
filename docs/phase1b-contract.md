# Phase 1b Build Contract — turn-transition gate + deterministic auto-flick

Fixed 2026-09-13 by orchestrator. Continues Phase 1a (committed + pushed: ead1224).
Orchestrator gates between waves; agents NEVER run the engine (the `.godot/` cache races).

## Priorities (docs §3.5 ranked list)
1. **Hard turn-transition gate** (docs §3.5 #1) — the single most common hot-seat
   failure is a player flicking on the wrong turn. Full-screen tap-to-continue with
   input locked during handoff. Nearly free since the game already has a "settled"
   state (TurnState). THIS WAVE'S MAIN DELIVERABLE.
2. **Deterministic auto-flick** — a test hook that fires a scripted flick, so
   knockout outcomes are reachable + testable headless (today only the forfeit path
   is exercisable without a human dragging).

## Ownership (strict, zero overlaps)

| Path | Owner | Content |
|---|---|---|
| `game/scripts/turn_gate.gd` (NEW) | Agent G | `class_name TurnGate extends CanvasLayer` — the tap-to-continue overlay |
| `game/scripts/main.gd` | Agent G | Wire the gate: lock AimInput between turns, show overlay on settle, advance on tap |
| `game/scripts/auto_flick.gd` (NEW) | Agent F | `class_name AutoFlick extends Node` — scripted-flick test harness |
| `game/tests/auto_flick_test.gd` (NEW) | Agent F | Deterministic headless knockout test |
| `game/scripts/aim_input.gd` | **ORCHESTRATOR** | Input lock integration (do NOT edit — see contract notes) |

## Existing behavior you MUST preserve (read before editing)
- `main.gd`: wires AimInput.flick_ready -> TurnState.on_flick + active PenBody.apply_flick;
  PenBody.settled/out_of_bounds -> TurnState; forfeit_tick per frame; verdict print once.
  Phase 1a added: Feel (shake/hit_stop) + DebugOverlay. READ the current file.
- `turn_state.gd` phases: AIM, IN_FLIGHT, SETTLED, FORFEIT, GAME_OVER. `state()` returns
  a Dictionary with `phase`, `current_player`, `winner`, `loser`.
- `aim_input.gd`: `flick_ready(direction, power)` signal; `set_active_zone(center, radius)`.
  It emits flick_ready on drag release. **You do NOT modify aim_input.gd** — instead,
  Main gates the *routing*: when the transition gate is up, ignore flick_ready events
  (or check `turn_state.state().phase != AIM` before routing). Keep it simple: a bool
  `_input_locked` in Main that blocks `_on_flick_ready`.

## Agent G — TurnGate (docs §3.5 #1)

`class_name TurnGate extends CanvasLayer` (drawn above world, below debug overlay).
- API: `func show_prompt(text: String) -> void`, `func hide() -> void`, `signal tapped`.
- Visual: a dim full-screen rect (Color(0,0,0,0.45)) + centered text like
  "Red's turn — tap to continue". Input: `_unhandled_input(event)` — on any mouse
  button press, emit `tapped` and hide.
- Keep it self-contained: no refs to TurnState/PenBody types.

`main.gd` wiring (Agent G owns this file for the wave):
- Add `@onready var turn_gate: TurnGate` (added as child in `_ready`), connect
  `tapped` -> `_on_gate_tapped`.
- **Flow:** TurnState settles a round (both pens on table) -> TurnState auto-advances
  to next player's AIM already. Main shows the gate ("<Player>'s turn — tap"),
  sets `_input_locked = true`. On gate `tapped`: `_input_locked = false`, hide gate,
  sync aim zone. On GAME_OVER/FORFEIT: show "Blue wins — tap to restart" and on tap,
  reset pens (call `pen.reset()` on both) + `turn_state.begin_turn()` if you add a
  reset API — otherwise just print and stay (keep scope tight: restart can be wave 3;
  showing the final prompt is enough).
- `_on_flick_ready`: guard `if _input_locked: return` at the top.
- Do NOT change existing flick/settle/forfeit routing, verdict print, Feel calls,
  DebugOverlay wiring.

## Agent F — AutoFlick harness (deterministic knockout testing)

`class_name AutoFlick extends Node`. Purpose: let a test/CI script drive the game
headless to a real knockout (pen leaves the table) instead of only the forfeit path.
- API: `func schedule_flick(player: String, impulse: Vector2, delay_sec: float) -> void`
  (uses a Timer or `get_tree().create_timer`), `func fire_now(player: String, impulse: Vector2) -> void`
  (calls the active pen's `apply_flick` through Main or by finding the PenBody by pen_id).
- `fire_now` must route through the SAME path as a human flick so TurnState + Feel fire
  identically: prefer emitting into Main via a signal `auto_flick_requested(player, impulse)`
  that Main connects and handles exactly like `_on_flick_ready` (minus the drag math).
  If that requires a Main edit, put it in YOUR file and have Main connect it — do NOT
  edit aim_input.gd.
- Add a `var enabled: bool = false` so normal runs ignore it.

`game/tests/auto_flick_test.gd` (Agent F): a headless script (same convention as
`turn_state_test.gd` — READ that file first) that:
1. Loads `res://scenes/main.tscn`, instantiates it, adds to a SceneTree (or runs the
   whole game headless via `--script`), disables the turn gate (set a flag if needed),
2. Schedules an `AutoFlick` that fires a strong impulse toward the table edge on the
   active player, then asserts within N frames that `turn_state.state().phase` reaches
   GAME_OVER (the flicked pen went OOB) OR the round resolves with a winner.
- Since physics is non-deterministic run-to-run (docs §4.1), the test must be tolerant:
  assert that a ROUND ENDS with a winner OR the forfeit path, not a specific pen. The
  goal is "knockout is reachable" — if it never resolves, the test FAILS (that's the bug).
- Exit 0 = pass, 1 = fail (mirror turn_state_test).

## Acceptance
- Import clean (no SCRIPT ERROR) after double import.
- `turn_state_test` + `auto_flick_test` both run; at least turn_state ALL PASS.
- Game runs under Xvfb, no script errors; the gate overlay shows after a round settles
  (forfeit path testable without input: on FORFEIT the final prompt appears).
- Vision_inspect on a captured frame reads the turn-gate overlay text (proves it renders).

## Engine facts (verified 4.7.2)
- `CanvasLayer` node exists (layer property); CanvasItem `_unhandled_input(event: InputEvent)`;
  `event is InputEventMouseButton`, `event.pressed`, `event.button_index == MOUSE_BUTTON_LEFT`.
- `get_tree().create_timer(sec)` returns a SceneTreeTimer (docs §7 verification ledger flags
  the exact arg signature — use `create_timer(delay_sec)` with default args; if a
  `ignore_time_scale` arg is required by the 4.7 API, pass it).
- `OS.is_debug_build()`, `Engine.time_scale` (Feel already uses them).
- Remember GDScript inference gotcha: annotate types explicitly when RHS is a Variant
  (e.g. `var t: SceneTreeTimer = get_tree().create_timer(...)`).
