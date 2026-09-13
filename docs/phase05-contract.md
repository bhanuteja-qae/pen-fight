# Phase 0.5 Build Contract — pen-fight Godot skeleton

Fixed 2026-09-13 by orchestrator. Siblings code against THESE interfaces — they are
agreed-upon spec, not yet-written files. Verify everything against the live engine
during integration (orchestrator runs gates between waves; agents NEVER run the
engine concurrently — the `.godot/` import cache races).

## Layout (strip ownership — zero overlaps)

| Path | Owner | Content |
|---|---|---|
| `game/project.godot` | Agent A | Pinned project config (see below) |
| `game/scenes/main.tscn` | Agent A | Scene tree: Table, PenRed, PenBlue, ExitZone, UI layer |
| `game/scripts/main.gd` | Agent A | `class_name Main` controller: wires signals, owns no physics |
| `game/scripts/pen_body.gd` | Agent B | `class_name PenBody extends RigidBody2D` — flick, settle, OOB |
| `game/scripts/turn_state.gd` | Agent C | `class_name TurnState` — PURE GDScript state machine, no scene/Node2D deps |
| `game/scripts/aim_input.gd` | Agent C | `class_name AimInput` — pointer drag → slingshot vector |
| `game/assets/*.png` | Agent A | Generated flat capsule sprites (red/blue) + table texture |
| `game/tests/` | Agent C | `turn_state` logic test (plain GDScript, run headless) |

## Interfaces (the contract)

### PenBody (Agent B) — one node per `{{PEN_ID}}` in `{{PENS}}` = ["red", "blue"]
- `signals`: `settled(pen_uid: String)`, `flicked(pen_uid: String, impulse: Vector2)`, `out_of_bounds(pen_uid: String)`
- `func apply_flick(impulse_dir: Vector2, power: float) -> void` — sets velocity via physics state, not position teleport
- `var pen_id: String` — "red" | "blue"
- `var start_position: Vector2` — reset target
- Settle detector: velocity magnitude + angular speed below threshold for ~0.25 s quiet
  debounce → emit `settled`. Reset per flick.
- OOB: any part of capsule outside table rect (`body_shape_exited`-style geometry —
  docs §3.2: geometric "any part off" beats centre-of-mass).

### TurnState (Agent C) — pure logic, NO Node2D/scene-tree/physics deps
- Constructor args: pens list, forfeit_timeout. Internal: `current_player`, `phase`
  (`AIM`, `IN_FLIGHT`, `SETTLED`, `FORFEIT`, `GAME_OVER`)
- `func begin_turn() -> void`, `func on_flick(impulse: Vector2) -> void`
- `func on_settled(pen_uid: String) -> void` — resolve win geometry vs table rect
- `func on_out_of_bounds(pen_uid: String) -> void` — winner decided HERE, geometrically,
  BEFORE any ceremony (docs §3.2: resolve outcome first, ceremony is pure presentation)
- `func forfeit_tick(delta: float) -> void` — 4–6 s hard timeout
- `func state() -> Dictionary` — serializable snapshot for the debug overlay + tests

### Main (Agent A) — the wiring
On `AimInput.flick_ready(dir, power)` → `TurnState.on_flick` → `PenBody.apply_flick`
On `PenBody.settled` → `TurnState.on_settled` → either `begin_turn()` (next player) or game over
On `PenBody.out_of_bounds` → `TurnState.on_out_of_bounds`

### AimInput (Agent C)
- Input: pointer press in pen's zone → drag → release. Vector = release - press (slingshot:
  pull back = flick forward), normalized dir + power from drag distance.
- Signals: `flick_ready(direction: Vector2, power: float)`. Cancel gesture: release near
  the pen (short drag) does nothing.
- NO trajectory prediction (docs §3.5 item 6 — skill ceiling depends on not solving aim).

## Pinned config (Agent A, from `2d/physics_platformer/project.godot` + docs §3)
```
[application]
config/name="Pen Fight"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.7")
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="keep_height"
[physics]
common/physics_ticks_per_second=60      # docs §3.2: keep 60 Hz, turn ON interpolation
common/physics_interpolation=true
2d/default_gravity=0                     # table-top game: top-down, no gravity
[debug]
gdscript/warnings/untyped_declaration=1
[rendering]
renderer/rendering_method="gl_compatibility"
```
Plus `.gitignore` entries already covered at repo root; add `game/.godot/` ignore if absent.

## Engine & run facts (for syntax sanity only — import/run gates are orchestrator's job)
- Godot: `~/godot/Godot_v4.7.2-stable_linux.x86_64`
- Headless import (run twice, see docs §3.3): `godot --headless --editor --quit --import game/`
- Run under Xvfb: `Xvfb :99 -screen 0 1280x720x24 &` then `DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --path game/`
- Scan screenshots: `python3 tools/vision_inspect.py <frame.png> "<question>"` (deepseek vision-exp)
- GDScript reference patterns (confirmed from official demos):
  `class_name X extends RigidBody2D`, `func _integrate_forces(state: PhysicsDirectBodyState2D)`,
  `state.get_step()`, `state.get_linear_velocity()`, `state.get_contact_count()`,
  `state.get_contact_local_normal(i)`, `@onready var x := $Sprite2D as Sprite2D`,
  signals: `func _on_area_entered(area: Area2D) -> void`, `Input.is_action_pressed(&"name")`,
  `Input.get_action_strength(&"name")`

## Acceptance (this wave matters: it unblocks CI + the loop)
- `game/project.godot` loads clean (no script parse errors) after double import
- Game runs under Xvfb without crashing; frame shows a table + two capsule pens
- `python3 tools/vision_inspect.py` on the frame correctly locates the two pens
- `TurnState` logic test passes headless (Agent C self-check OK is not sufficient — orchestrator runs it)