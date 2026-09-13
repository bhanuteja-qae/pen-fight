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

signal flick_ready(direction: Vector2, power: float, contact_offset: float)

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
## The active pen body. The grab zone is this pen's capsule (barrel + tip/cap
## caps with a finger margin), NOT a small circle — the drag starts from
## touching the pen at any point along its length (real pen-fight grab).
var active_pen: PenBody = null
## Extra radius beyond the pen barrel a press may start inside (finger width).
@export var grab_margin_px: float = 26.0

var _dragging: bool = false
var _press_pos: Vector2 = Vector2.ZERO

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
func set_active_pen(pen: PenBody) -> void:
	active_pen = pen

## True when `pos` is on or near the active pen: within grab_margin_px of the
## pen's capsule (barrel segment + rounded end caps). The barrel axis is the
## pen's local +X rotated by its world rotation; the capsule radius is added
## to the finger margin so pressing the pen anywhere along its length starts
## the flick (not just near a small centre zone).
func _press_on_pen(pos: Vector2) -> bool:
	if active_pen == null:
		return true  # no pen resolved: accept any press (defensive)
	var axis: Vector2 = Vector2.RIGHT.rotated(active_pen.global_rotation)
	var center: Vector2 = active_pen.global_position
	var half: float = active_pen.get_half_len()
	var d: Vector2 = pos - center
	var along: float = d.dot(axis)
	# Clamp to the barrel segment, then distance to that clamped point must be
	# within the capsule radius + finger margin.
	var clamped: float = clampf(along, -half, half)
	var nearest: Vector2 = center + axis * clamped
	var reach: float = active_pen.get_radius() + grab_margin_px
	return pos.distance_to(nearest) <= reach

## Signed grab offset along the barrel in [-1, 1]: -1 = tip, 0 = centre,
## +1 = cap end. Passed to PenBody.apply_flick so an off-centre grab with a
## drag direction skew to the barrel spins the pen (real pen-fight corner
## flick). Clamped so presses past the end still report the end (grab at the
## very tip/cap counts as corner contact).
func _contact_offset(pos: Vector2) -> float:
	if active_pen == null:
		return 0.0
	var axis: Vector2 = Vector2.RIGHT.rotated(active_pen.global_rotation)
	var d: Vector2 = pos - active_pen.global_position
	var along: float = d.dot(axis)
	return clampf(along / active_pen.get_half_len(), -1.0, 1.0)

func _press_in_zone(pos: Vector2) -> bool:
	return _press_on_pen(pos)

func _release(release_pos: Vector2) -> void:
	var drag: Vector2 = release_pos - _press_pos
	var dist: float = drag.length()
	if dist < min_drag_pixels:
		return  # short drag = cancel gesture, emit nothing
	var direction: Vector2 = (-drag).normalized()  # pull back -> flick forward
	var power: float = clampf(dist / max_drag_pixels, 0.0, 1.0)
	# Where the flick was actually grabbed on the pen (-1..1 along the barrel).
	var contact_offset: float = _contact_offset(_press_pos)
	flick_ready.emit(direction, power, contact_offset)
