class_name Feel
extends Node
## Phase 1a feel layer for pen-fight (docs/05-feel-polish.md §3).
##
## Owns no game rules and references no TurnState / PenBody: it is a pure
## presentation helper that Main drives. Per the build contract:
##   - `shake(trauma)`   — trauma-based screen shake (docs §3.5 #2): add 0..1
##                         trauma, decay it every frame, and offset the Camera2D
##                         by trauma² * max_offset in a random direction.
##   - `hit_stop(frames)` — near-freeze via Engine.time_scale = 0.02 for 2..6
##                          rendered frames, then restore 1.0. Frame counter in
##                          process_frame(), never a blocking sleep (and never 0.0
##                          exactly — docs §3.3 caveat: 0.0 makes the physics
##                          engine register spurious collisions on resume).
##   - `reset()`          — zero trauma, restore time_scale, clear camera offset.
##
## Main must call `process_frame(delta)` once per frame (drives both the shake
## decay and the hit-stop frame counter). The Camera2D is resolved by path from
## the scene (main.tscn keeps the node name `Camera2D` stable per contract); if
## it is missing the node is simply ignored — no crash, no shake.

const MAX_OFFSET: float = 10.0        # px of camera offset at trauma = 1.0
const MAX_ROLL_DEG: float = 3.0       # camera roll at trauma = 1.0 (docs §9 #2)
const TRAUMA_DECAY: float = 2.0       # trauma per second (docs: 1.5-2.5/s)
const HIT_STOP_TIME_SCALE: float = 0.02
const HIT_STOP_MIN_FRAMES: int = 2
const HIT_STOP_MAX_FRAMES: int = 6

## Screen-shake master switch (the "Screen shake" row in Settings). Hit-stop is
## deliberately NOT gated by this: it is a freeze, not movement, and disabling it
## would change how hits READ rather than how much the screen moves.
var enabled: bool = true

var _trauma: float = 0.0
var _hit_stop_frames_left: int = 0
var _rng := RandomNumberGenerator.new()

## Resolved in _ready before this node's first frame. `as Camera2D` keeps the
## assignment type-safe even though get_node_or_null() returns a base Node.
@onready var _camera: Camera2D = get_node_or_null("Camera2D") as Camera2D


# --- Public API -----------------------------------------------------------------

## Add 0..1 trauma (stacking, clamped). Call when a hit/impact is REACTED to,
## i.e. after the outcome is already decided — never during resolution.
func shake(trauma: float) -> void:
	if not enabled:
		return
	_trauma = clampf(_trauma + trauma, 0.0, 1.0)


## Near-freeze the engine for `frames` rendered frames (clamped to 2..6), then
## restore Engine.time_scale to 1.0. Uses a frame counter, not a blocking sleep.
func hit_stop(frames: int) -> void:
	var n: int = clampi(frames, HIT_STOP_MIN_FRAMES, HIT_STOP_MAX_FRAMES)
	if n <= 0:
		return
	_hit_stop_frames_left = n
	Engine.time_scale = HIT_STOP_TIME_SCALE


## Full teardown: zero trauma, restore real time, clear the camera offset.
## Safe to call at any time; also guarantees time_scale is never left frozen.
func reset() -> void:
	_trauma = 0.0
	_hit_stop_frames_left = 0
	Engine.time_scale = 1.0
	if _camera != null:
		_camera.offset = Vector2.ZERO
		_camera.rotation = 0.0


## Per-frame driver, called by Main._process. Decays trauma (note: during a
## hit-stop the delta is scaled by time_scale, so the shake holds through the
## freeze and only decays after time restores — intended feel).
func process_frame(delta: float) -> void:
	_tick_hit_stop()
	_tick_shake(delta)


# --- Internals ------------------------------------------------------------------

func _tick_hit_stop() -> void:
	if _hit_stop_frames_left <= 0:
		return
	_hit_stop_frames_left -= 1
	if _hit_stop_frames_left <= 0:
		Engine.time_scale = 1.0


func _tick_shake(delta: float) -> void:
	if _camera == null:
		return
	if _trauma > 0.0:
		_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
		var strength: float = _trauma * _trauma
		_camera.offset = Vector2(
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0)
		) * MAX_OFFSET * strength
		# Trauma² roll (docs §9 #2): pitch the camera up to 3° at max trauma.
		_camera.rotation = deg_to_rad(MAX_ROLL_DEG) * strength * _rng.randf_range(-1.0, 1.0)
	else:
		_camera.offset = Vector2.ZERO
		_camera.rotation = 0.0
