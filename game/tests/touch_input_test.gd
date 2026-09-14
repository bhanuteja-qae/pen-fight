extends SceneTree
class_name TouchInputTest
## Touch-input end-to-end test (review item: the council's weakest coverage spot).
##
## The other suites cover the turn STATE MACHINE (turn_state_test), the physics
## probes, the overlay and the auto-flick routing. None of them delivers a real
## touch event: the whole AimInput pointer layer — grab-zone hit test, the
## viewport->world mapping, multi-touch ownership, the drag->flick translation
## and the turn gate — was untested, so a regression there stayed invisible
## until a human played on a phone.
##
## This test drives the REAL scene (res://scenes/main.tscn) with REAL
## InputEventScreenTouch / InputEventScreenDrag events pushed through the
## viewport, and asserts on the REAL game state (TurnState.state() + PenBody
## velocity). Nothing is mocked: the only thing the test does that a finger does
## not is decide where the finger lands.
##
## What it proves, in order:
##   0. gesture_reaches_aiminput - the injection path itself works (see below)
##   1. short_drag_cancels       - a <30px drag emits no shot (anti-misflick)
##   2. press_off_pen_ignored    - a press on empty floor never starts a gesture
##   3. multitouch_ownership     - a second finger can neither hijack nor cancel
##                                 the gesture the first finger owns
##   4. touch_drag_flick         - touch -> AimInput -> TurnState -> PenBody:
##                                 exact impulse recorded, pen actually launched
##   5. gate_blocks_followup     - once the turn has moved on, another full
##                                 gesture is ignored (input lock, real path)
##
## Two traps this test is built to avoid — both were hit while writing it:
##
## * INPUT INJECTION. Input.parse_input_event() queues into the Input singleton,
##   whose buffered flush never reaches _unhandled_input under --headless
##   --script (measured: gestures injected that way never set AimInput._dragging).
##   Every "no shot happened" case then passes VACUOUSLY. We push into the
##   viewport instead (root.push_input(ev, true) = viewport-local coords), which
##   runs the whole chain: _input -> gui -> _unhandled_input. Case 0 exists to
##   fail loudly if that ever stops being true, and the positive cases assert the
##   gesture actually started before asserting what it did not do.
##
## * CAMERA-TRANSFORM RACE. ScreenTouch/ScreenDrag positions are VIEWPORT-local,
##   so the test must convert world -> viewport. Caching that conversion for a
##   whole case is wrong: the camera is physics-interpolated, so the canvas
##   transform can change between reading it and the event being delivered, which
##   skews the drag (observed once as power 1.0 for an 80px pull, direction
##   rotated ~24 degrees). Every injection therefore converts a WORLD point at
##   the moment it injects (_touch_world / _drag_world), never a cached screen
##   point — and the world->viewport mapping stays under test rather than assumed.
##
## Run (cwd = game/):
##   DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 ~/godot/Godot_v4.7.2-stable_linux.x86_64 \
##     --headless --path . --script res://tests/touch_input_test.gd
## (exit 0 = all cases pass, 1 = fail)

const DRAG_FULL_POWER_PX: float = 160.0   # AimInput.max_drag_pixels
const CANCEL_UNDER_PX: float = 30.0       # AimInput.min_drag_pixels
const MAX_IMPULSE: float = 1600.0         # PenBody.MAX_IMPULSE
const VEL_TOLERANCE: float = 0.25         # damping/one-frame integration slack

var _main: Node = null
var _failures: Array[String] = []
var _cases_run: int = 0


func _init() -> void:
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_finish(false, "could not load res://scenes/main.tscn")
		return
	_main = packed.instantiate()
	root.add_child(_main)
	_run_all()


# ---------------------------------------------------------------- test driver

func _run_all() -> void:
	if not await _await_aim(240):
		_finish(false, "never reached phase AIM within 4s — cannot test input")
		return

	await _case_gesture_reaches_aiminput()
	await _case_short_drag_cancels()
	await _case_press_off_pen_ignored()
	await _case_multitouch_ownership()
	await _case_touch_drag_flick()
	await _case_gate_blocks_followup()

	if _failures.is_empty():
		_finish(true, "touch_input_test: ALL PASS (%d cases)" % _cases_run)
	else:
		_finish(false, "touch_input_test: %d of %d cases FAILED — %s"
			% [_failures.size(), _cases_run, "; ".join(_failures)])


## Case 0 — the injection path itself: a press on the pen must start a gesture
## in AimInput, the drag must translate into the slingshot direction + power,
## and a release inside the cancel radius must emit nothing. Every case below
## depends on this, so it is reported first and separately.
func _case_gesture_reaches_aiminput() -> void:
	_cases_run += 1
	var pen := _active_pen()
	if pen == null:
		_fail("gesture_reaches_aiminput", "no active pen")
		return
	var press_world: Vector2 = pen.global_position

	_touch_world(0, true, press_world)
	await _settle_frames(2)
	var info: Dictionary = _drag_info()
	if info.is_empty():
		_fail("gesture_reaches_aiminput",
			"press on the pen did not start a gesture — injected events are not reaching AimInput (pen=%s canvas=%s)"
			% [str(press_world), str(root.get_canvas_transform())])
		return
	# the press maps back to the pen's own world position: grab_offset ~0
	if absf(float(info.get("grab_offset", 1.0))) > 0.05:
		_fail("gesture_reaches_aiminput",
			"viewport->world mapping off: grab_offset=%.3f for a centre grab (expected 0)"
			% float(info.get("grab_offset", 9.9)))

	# pull straight back (+Y in world) by 80px -> power 0.5, launch dir -Y
	var pull_world: Vector2 = press_world + Vector2(0, 80)
	_drag_world(0, pull_world)
	await _settle_frames(2)
	info = _drag_info()
	var want_power: float = 80.0 / DRAG_FULL_POWER_PX
	if absf(float(info.get("power", 0.0)) - want_power) > 0.01:
		_fail("gesture_reaches_aiminput", "power %.3f != %.3f after an 80px pull (info=%s)"
			% [float(info.get("power", 0.0)), want_power, str(info)])
	var dir: Vector2 = info.get("direction", Vector2.ZERO)
	if dir.distance_to(Vector2(0, -1)) > 0.01:
		_fail("gesture_reaches_aiminput",
			"slingshot direction %s != (0,-1) for a +Y pull" % str(dir))

	# release inside the cancel radius of the press -> gesture cancels, no shot
	_drag_world(0, press_world + Vector2(0, CANCEL_UNDER_PX * 0.3))
	_touch_world(0, false, press_world + Vector2(0, CANCEL_UNDER_PX * 0.3))
	await _settle_frames(4)
	if _phase() != _aim_phase():
		_fail("gesture_reaches_aiminput",
			"release inside the cancel radius produced a flick (phase=%s)" % _phase())


## Case 1 — a drag shorter than min_drag_pixels must cancel: no shot, no motion.
func _case_short_drag_cancels() -> void:
	_cases_run += 1
	var pen := _active_pen()
	if pen == null:
		_fail("short_drag_cancels", "no active pen")
		return
	var press_world: Vector2 = pen.global_position
	var release_world: Vector2 = press_world + Vector2(0, CANCEL_UNDER_PX * 0.5)

	_touch_world(0, true, press_world)
	await _settle_frames(2)
	if not _gesture_started("short_drag_cancels"):
		return
	_drag_world(0, release_world)
	_touch_world(0, false, release_world)
	await _settle_frames(4)

	if _phase() != _aim_phase():
		_fail("short_drag_cancels", "a %.0fpx drag was treated as a flick (phase=%s)"
			% [CANCEL_UNDER_PX * 0.5, _phase()])
	elif pen.linear_velocity.length() > 1.0:
		_fail("short_drag_cancels", "pen moved (|v|=%.1f) on a cancelled gesture"
			% pen.linear_velocity.length())


## Case 2 — a press on empty floor (far from the pen capsule) starts nothing.
func _case_press_off_pen_ignored() -> void:
	_cases_run += 1
	var pen := _active_pen()
	if pen == null:
		_fail("press_off_pen_ignored", "no active pen")
		return
	# mirror the pen through the table centre: always well clear of the capsule
	var away_world: Vector2 = -pen.global_position
	if away_world.distance_to(pen.global_position) < 150.0:
		_fail("press_off_pen_ignored", "could not find a point clear of the pen to press")
		return

	_touch_world(0, true, away_world)
	await _settle_frames(2)
	if not _drag_info().is_empty():
		_fail("press_off_pen_ignored", "a press on empty floor STARTED a gesture")
		_touch_world(0, false, away_world)
		await _settle_frames(2)
		return
	_drag_world(0, away_world + Vector2(0, 120))
	_touch_world(0, false, away_world + Vector2(0, 120))
	await _settle_frames(4)

	if _phase() != _aim_phase():
		_fail("press_off_pen_ignored", "an off-pen press produced a flick (phase=%s)" % _phase())
	elif pen.linear_velocity.length() > 1.0:
		_fail("press_off_pen_ignored", "pen moved (|v|=%.1f) from an off-pen press"
			% pen.linear_velocity.length())


## Case 3 — multi-touch: finger 1 may not hijack or cancel finger 0's gesture.
func _case_multitouch_ownership() -> void:
	_cases_run += 1
	var pen := _active_pen()
	if pen == null:
		_fail("multitouch_ownership", "no active pen")
		return
	var press_world: Vector2 = pen.global_position
	_touch_world(0, true, press_world)
	await _settle_frames(2)
	if not _gesture_started("multitouch_ownership"):
		return
	var owner_pos_before: Vector2 = _drag_info().get("current_pos", Vector2.ZERO)

	# second finger lands elsewhere and drags a long way: must be ignored
	var other_world: Vector2 = -pen.global_position
	_touch_world(1, true, other_world)
	_drag_world(1, other_world + Vector2(0, 150))
	_touch_world(1, false, other_world + Vector2(0, 150))
	await _settle_frames(3)
	if _drag_info().get("current_pos", Vector2.ZERO) != owner_pos_before:
		_fail("multitouch_ownership",
			"an intruding finger moved the owning gesture's drag position")
	if _phase() != _aim_phase():
		_fail("multitouch_ownership", "a non-owning finger launched a flick (phase=%s)" % _phase())
		_touch_world(0, false, press_world)  # clean up the abandoned gesture
		await _settle_frames(2)
		return

	# the owner is still dragging: its own short release must cancel cleanly
	var owner_release: Vector2 = press_world + Vector2(0, CANCEL_UNDER_PX * 0.4)
	_drag_world(0, owner_release)
	_touch_world(0, false, owner_release)
	await _settle_frames(4)
	if _phase() != _aim_phase():
		_fail("multitouch_ownership", "owner release was mis-handled (phase=%s)" % _phase())


## Case 4 — THE end-to-end case: touch drag -> AimInput -> TurnState -> PenBody.
func _case_touch_drag_flick() -> void:
	_cases_run += 1
	var pen := _active_pen()
	var target := _other_pen(pen)
	if pen == null or target == null:
		_fail("touch_drag_flick", "could not resolve pens")
		return

	var launch_dir: Vector2 = (target.global_position - pen.global_position).normalized()
	var drag_px: float = 100.0
	var want_power: float = drag_px / DRAG_FULL_POWER_PX
	var press_world: Vector2 = pen.global_position
	# slingshot: pull BACK, away from the target (release = press - dir * drag)
	var release_world: Vector2 = press_world - launch_dir * drag_px

	_touch_world(0, true, press_world)
	await _settle_frames(2)
	if not _gesture_started("touch_drag_flick"):
		return
	_drag_world(0, (press_world + release_world) * 0.5)
	_drag_world(0, release_world)
	_touch_world(0, false, release_world)
	await _settle_frames(6)

	var st: Dictionary = _state()
	var impulse: Vector2 = st.get("last_impulse", Vector2.ZERO)
	if impulse.length() < 0.0001:
		_fail("touch_drag_flick",
			"no impulse reached TurnState (phase=%s) — the touch path is broken end-to-end" % _phase())
		return
	var want_impulse: Vector2 = launch_dir * want_power
	if impulse.distance_to(want_impulse) > 0.03:
		_fail("touch_drag_flick", "impulse %s != expected dir*power %s (power=%.3f)"
			% [str(impulse), str(want_impulse), want_power])
	if _phase() == _aim_phase():
		_fail("touch_drag_flick", "phase stayed AIM after a valid flick")

	var v: Vector2 = pen.linear_velocity
	var want_v: float = want_power * MAX_IMPULSE
	if v.length() < want_v * (1.0 - VEL_TOLERANCE):
		_fail("touch_drag_flick", "pen not launched: |v|=%.1f, expected ~%.1f"
			% [v.length(), want_v])
	elif v.normalized().dot(launch_dir) < 0.98:
		_fail("touch_drag_flick", "launch direction %s != aimed %s"
			% [str(v.normalized()), str(launch_dir)])


## Case 5 — the turn gate (input lock) must swallow a full gesture.
func _case_gate_blocks_followup() -> void:
	_cases_run += 1
	var before: Dictionary = _state()
	var before_impulse: Vector2 = before.get("last_impulse", Vector2.ZERO)
	var pen := _active_pen()
	if pen == null:
		return  # round already over: nothing to attempt, and that is a pass
	var press_world: Vector2 = pen.global_position

	_touch_world(0, true, press_world)
	_drag_world(0, press_world + Vector2(0, 150))
	_touch_world(0, false, press_world + Vector2(0, 150))
	await _settle_frames(5)

	var after: Dictionary = _state()
	if _phase() == _aim_phase():
		# AIM again is legitimate only if the round resolved and restarted;
		# a new gesture then belongs to the new AIM, not to this case
		return
	var after_impulse: Vector2 = after.get("last_impulse", Vector2.ZERO)
	if after_impulse.distance_to(before_impulse) > 0.03:
		_fail("gate_blocks_followup",
			"a gesture outside AIM changed last_impulse %s -> %s"
			% [str(before_impulse), str(after_impulse)])


# ------------------------------------------------------------------- helpers

## Inject a ScreenTouch for a WORLD point. The world->viewport conversion is
## done HERE, at injection time: caching it across frames races the
## physics-interpolated camera transform (see the header note).
func _touch_world(index: int, pressed: bool, world_pos: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = _screen_of(world_pos)
	root.push_input(ev, true)


## Inject a ScreenDrag for a WORLD point (see _touch_world).
func _drag_world(index: int, world_pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = _screen_of(world_pos)
	root.push_input(ev, true)


## Wait n physics frames; input injected the previous frame is delivered by now.
func _settle_frames(n: int) -> void:
	for i in range(n):
		await physics_frame


## Wait until TurnState reports AIM with a resolvable pen.
func _await_aim(max_frames: int) -> bool:
	for i in range(max_frames):
		await physics_frame
		if _phase() == _aim_phase() and _active_pen() != null:
			return true
	return false


## World -> viewport position using the same canvas transform AimInput inverts.
func _screen_of(world_pos: Vector2) -> Vector2:
	return root.get_canvas_transform() * world_pos


## Live AimInput gesture state ({} when idle) — lets a case prove a gesture
## actually started, so a "nothing happened" assertion cannot pass vacuously.
func _drag_info() -> Dictionary:
	var aim: Variant = _main.get("aim_input")
	if aim == null:
		return {}
	return aim.get_drag_info()


## Guard for the positive cases: the press must have started a gesture.
func _gesture_started(case_name: String) -> bool:
	if _drag_info().is_empty():
		_fail(case_name, "press did not start a gesture — input path broken, case not exercised")
		return false
	return true


func _state() -> Dictionary:
	var ts: Variant = _main.get("turn_state")
	if ts == null:
		return {}
	return ts.state()


func _phase() -> String:
	return str(_state().get("phase", ""))


func _aim_phase() -> String:
	return str(TurnState.PHASE_AIM)


func _pen_for(player: String) -> PenBody:
	match player:
		"red":
			return _main.get("pen_red") as PenBody
		"blue":
			return _main.get("pen_blue") as PenBody
		_:
			return null


func _active_pen() -> PenBody:
	return _pen_for(str(_state().get("current_player", "")))


func _other_pen(pen: PenBody) -> PenBody:
	if pen == null:
		return null
	return _pen_for("blue") if pen == _pen_for("red") else _pen_for("red")


func _fail(case_name: String, why: String) -> void:
	_failures.append("%s: %s" % [case_name, why])
	push_error("touch_input_test FAIL %s — %s" % [case_name, why])


func _finish(ok: bool, msg: String) -> void:
	print(msg)
	quit(0 if ok else 1)
