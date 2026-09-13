class_name AimInput
extends Node2D
## Slingshot drag-back pointer input for pen-fight (Phase 0.5; Phase 1d makes
## it TOUCH-FIRST).
##
## Press inside the active pen's grab zone, drag BACK (away from the target),
## release: the pen flicks FORWARD. direction = (press_pos - release_pos).
## normalized() — pull back = flick forward — and power = drag distance /
## max_drag_pixels, capped to [0, 1]. Releasing near the pen (drag shorter than
## min_drag_pixels) cancels the gesture and emits nothing. NO trajectory
## prediction (docs §3.5 item 6): the skill ceiling depends on not solving the
## aim for the player.
##
## Input mechanism (Phase 1d): this Node2D overrides `_unhandled_input(event)`.
## TOUCH is the primary path — InputEventScreenTouch (press/release) and
## InputEventScreenDrag feed the ONE gesture state machine (`_dragging`,
## _press_pos, _current_pos, release), identical to the mouse path that remains
## as the desktop/debug fallback (InputEventMouseButton + InputEventMouseMotion,
## which also keeps the overlay's live drag position honest on desktop).
##
## When Godot synthesizes one input kind from the other — emulate_touch_from_mouse
## on desktop, or emulate_mouse_from_touch on Android (the project default) — the
## SYNTHETIC duplicate is ignored so each physical gesture enters the state
## machine exactly once. Both paths resolve to the same world space: mouse via
## get_global_mouse_position(), touch via get_canvas_transform().affine_inverse()
## * event.position (ScreenTouch/Drag positions are viewport-local; the canvas
## transform is the stretch-mode + camera mapping get_global_mouse_position()
## applies, so the two paths agree point-for-point).
##
## Live gesture state for the aim overlay: get_drag_info(), rebuilt per call
## while dragging, empty when idle.

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
## Live pointer position while dragging (mouse motion / drag events) — the
## overlay reads it via get_drag_info(). Idle: ZERO.
var _current_pos: Vector2 = Vector2.ZERO
## Multi-touch index that owns the drag; -1 when no touch owns it (mouse drag).
## Guards so a second finger can neither hijack nor cancel the active gesture.
var _touch_index: int = -1


func _unhandled_input(event: InputEvent) -> void:
	if input_locked:
		return  # turn-transition gate: no input outside the AIM phase
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)


## Desktop/debug fallback path. On touch devices Godot synthesizes mouse events
## from touches (emulate_mouse_from_touch is ON by default): the real gesture
## already entered through the ScreenTouch path, so the synthetic copy must not
## double-drive the state machine.
func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	if Input.is_emulating_mouse_from_touch():
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var mouse_pos: Vector2 = get_global_mouse_position()
	if mb.pressed:
		# A drag only begins if the press lands in the active pen's zone.
		if _press_in_zone(mouse_pos):
			_begin_gesture(mouse_pos)
	elif _dragging:
		_end_gesture(mouse_pos)


## Keeps _current_pos live on the desktop path so get_drag_info() -- and the
## aim overlay -- track the mouse exactly like the finger on touch.
func _handle_mouse_motion(_event: InputEventMouseMotion) -> void:
	if _dragging and not Input.is_emulating_mouse_from_touch():
		_current_pos = get_global_mouse_position()


## Primary (touch-first) path. On desktop debug with emulate_touch_from_mouse
## ON the touch events are synthetic copies of the mouse — ignore them there;
## the mouse path owns the gesture.
func _handle_screen_touch(ev: InputEventScreenTouch) -> void:
	if Input.is_emulating_touch_from_mouse():
		return
	var pos: Vector2 = _touch_world_pos(ev.position)
	if ev.pressed:
		if _dragging:
			return  # multi-touch: the first finger owns the gesture
		if _press_in_zone(pos):
			_touch_index = ev.index
			_begin_gesture(pos)
	elif _dragging and ev.index == _touch_index:
		_touch_index = -1
		_end_gesture(pos)


## Live finger position while the owning index drags.
func _handle_screen_drag(ev: InputEventScreenDrag) -> void:
	if Input.is_emulating_touch_from_mouse():
		return
	if _dragging and ev.index == _touch_index:
		_current_pos = _touch_world_pos(ev.position)


## ScreenTouch / ScreenDrag positions are viewport-local; get_canvas_transform()
## is the root canvas transform (canvas_items stretch mode + any Camera2D), the
## exact mapping get_global_mouse_position() applies on the mouse path — so both
## input kinds land in the same world space.
func _touch_world_pos(view_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * view_pos


## Begin the shared gesture. Consumes the press so no other _unhandled_input
## handler reacts to the same tap.
func _begin_gesture(pos: Vector2) -> void:
	_dragging = true
	_press_pos = pos
	_current_pos = pos
	get_viewport().set_input_as_handled()


## End the shared gesture: the release translates the drag into a flick or a
## cancel via _release().
func _end_gesture(pos: Vector2) -> void:
	_dragging = false
	_current_pos = pos
	_release(pos)


## Override the active pen the grab zone follows.
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


## Live gesture state for the aim overlay, rebuilt on every call while dragging:
##   dragging     - always true here (false state = empty dict, below)
##   press_pos    - world position where the gesture began (the grab point)
##   current_pos  - live finger/mouse world position
##   grab_offset  - the grab point along the barrel in [-1, 1] (tip..cap)
##   direction    - unit launch direction (= -drag); ZERO until the pull is
##                  long enough to define one (overlays skip the cone then)
##   power        - drag distance / max_drag_pixels, clamped to [0, 1]
## Returns {} (empty, zeroed) when idle — the overlay treats that as "clear".
func get_drag_info() -> Dictionary:
	if not _dragging:
		return {}
	var drag: Vector2 = _current_pos - _press_pos
	var dist: float = drag.length()
	var direction: Vector2 = Vector2.ZERO
	if dist > 0.0001:
		direction = (-drag).normalized()  # pull back -> flick forward
	var power: float = clampf(dist / max_drag_pixels, 0.0, 1.0)
	return {
		"dragging": true,
		"press_pos": _press_pos,
		"current_pos": _current_pos,
		"grab_offset": _contact_offset(_press_pos),
		"direction": direction,
		"power": power,
	}
