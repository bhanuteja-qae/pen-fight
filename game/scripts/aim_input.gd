class_name AimInput
extends Node2D
## Slingshot drag-back pointer input for pen-fight (Phase 0.5).
##
## Press inside the active pen's grab zone, drag BACK (away from the target),
## release: the pen flicks FORWARD. direction = (press_pos - release_pos).
## normalized() — pull back = flick forward — and power = drag distance /
## max_drag_pixels, capped to [0, 1]. Releasing near the pen (drag shorter than
## min_drag_pixels) cancels the gesture and emits nothing. NO trajectory
## prediction (docs §3.5 item 6): the skill ceiling depends on not solving the
## aim for the player.
##
## Input mechanism: this Node2D overrides `_unhandled_input(event)` — the
## standard Godot 4.x gameplay-input pattern (fires after GUI input is handled).
## Press/release points come from `get_global_mouse_position()`, i.e. world /
## canvas space, which stays correct under canvas_items stretch and any camera.
## Grab-zone center defaults to this node's `global_position`; Main can move
## the node per turn or call `set_active_zone()` to override it without moving
## the node.

signal flick_ready(direction: Vector2, power: float)

## Hard turn-transition gate (docs §3.5 #1): when true, the pointer is fully
## ignored — no drag start, no release handling, no flick_ready emission. Main
## holds this true while the phase is anything but AIM, so a player can never
## flick on the wrong turn or during the round-over handoff.
var input_locked: bool = false

## Minimum drag distance (px). Releasing inside this radius cancels the gesture
## (emits nothing).
@export var min_drag_pixels: float = 15.0
## Drag distance (px) that produces full power (1.0). Power is capped there.
@export var max_drag_pixels: float = 160.0
## Radius (px) around the zone center a press must land inside to start a drag.
## 0 disables the check entirely (a press anywhere starts a drag).
@export var press_zone_radius: float = 100.0

var _dragging: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _zone_center_override: Vector2 = Vector2.ZERO
var _has_zone_override: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if input_locked:
		return  # turn-transition gate: no input outside the AIM phase
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var mouse_pos: Vector2 = get_global_mouse_position()
		if mb.pressed:
			# A drag only begins if the press lands in the active pen's zone.
			if _press_in_zone(mouse_pos):
				_dragging = true
				_press_pos = mouse_pos
				get_viewport().set_input_as_handled()
		elif _dragging:
			_dragging = false
			_release(mouse_pos)

## Override the grab-zone center (default: this node's global_position).
## Pass radius >= 0 to also override press_zone_radius.
func set_active_zone(center: Vector2, radius: float = -1.0) -> void:
	_zone_center_override = center
	_has_zone_override = true
	if radius >= 0.0:
		press_zone_radius = radius

func _press_in_zone(pos: Vector2) -> bool:
	if press_zone_radius <= 0.0:
		return true
	return pos.distance_to(_zone_center()) <= press_zone_radius

func _zone_center() -> Vector2:
	if _has_zone_override:
		return _zone_center_override
	return global_position

func _release(release_pos: Vector2) -> void:
	var drag: Vector2 = release_pos - _press_pos
	var dist: float = drag.length()
	if dist < min_drag_pixels:
		return  # short drag = cancel gesture, emit nothing
	var direction: Vector2 = (-drag).normalized()  # pull back -> flick forward
	var power: float = clampf(dist / max_drag_pixels, 0.0, 1.0)
	flick_ready.emit(direction, power)
