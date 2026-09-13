extends SceneTree
## DECISIVE two-position torque-arm test (review of main at 76aad79; Godot
## docs: apply_impulse position = "offset from the body origin in global
## coordinates", a vector not a world point).
##
## Fire the IDENTICAL flick from two table positions AND repeat each position
## twice. Separation of concerns:
##   * same-position repeat  (A1 vs A2, B1 vs B2) -> measures SYSTEM NOISE
##     (damping decay over the measure window, solver nondeterminism)
##   * cross-position compare (A vs B)            -> measures POSITION LEAKAGE
## If the noise floor is >= the cross-position delta, the arm is position-
## independent and the implementation is correct; a cross-position delta well
## above the same-position noise is a real leak.
##
## Run: godot --headless --path game --script res://tests/torque_arm_probe.gd

const DIR_X: float = 0.70710678   # cos(45)
const DIR_Y: float = 0.70710678   # sin(45)
const DIR: Vector2 = Vector2(DIR_X, DIR_Y)  # 45-deg skew drag
const POWER: float = 1.0
const CONTACT: float = 1.0        # grip at the cap end
const MEASURE_FRAMES: int = 8
const POS_A: Vector2 = Vector2(-300.0, -150.0)
const POS_B: Vector2 = Vector2(300.0, 150.0)

const N_SHOTS: int = 4            # A, A, B, B
const SHOT_NAMES: Array[String] = ["A1", "A2", "B1", "B2"]
const SHOT_POS: Array[Vector2] = [POS_A, POS_A, POS_B, POS_B]

var _pen: PenBody = null
var _shot: int = 0                # next shot index
var _frames_since: int = 0
var _results: Array[float] = []

func _init() -> void:
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	_pen = _search_pens(root, "red")
	if _pen == null:
		print("torque_probe: no red pen found")
		quit(1)
		return
	_fire_at(SHOT_POS[0])
	physics_frame.connect(_on_physics_frame)

func _on_physics_frame() -> void:
	if _shot >= N_SHOTS:
		return
	_frames_since += 1
	if _frames_since < MEASURE_FRAMES:
		return
	# Measured angular velocity at the sampling frame.
	var w: float = _pen.angular_velocity
	_results.append(w)
	print("torque_probe: %s @ %s -> w=%.4f rad/s (lin=%.1f px/s)" % [
		SHOT_NAMES[_shot], SHOT_POS[_shot], w, _pen.linear_velocity.length()])
	_shot += 1
	_frames_since = 0
	if _shot < N_SHOTS:
		_fire_at(SHOT_POS[_shot])
	else:
		_decide()

func _fire_at(pos: Vector2) -> void:
	_pen.reset()                       # zero velocities + home + interp snap
	_pen.global_position = pos         # reposition for the next sample
	_pen.reset_physics_interpolation() # snap the interp window after teleport
	_pen.apply_flick(DIR, POWER, CONTACT)

func _decide() -> void:
	var a: Array[float] = [_results[0], _results[1]]
	var b: Array[float] = [_results[2], _results[3]]
	var noise_a: float = absf(a[0] - a[1])
	var noise_b: float = absf(b[0] - b[1])
	var noise: float = maxf(noise_a, noise_b)
	var avg_a: float = (a[0] + a[1]) / 2.0
	var avg_b: float = (b[0] + b[1]) / 2.0
	var cross: float = absf(avg_a - avg_b)
	var cross_rel: float = cross / maxf(absf(avg_a), 0.0001)
	var verdict: String = "PASS: cross-position delta (%s) <= same-position noise (%s) — arm is a grab offset" % [
		"%.3f" % cross_rel, "%.3f" % (noise / maxf(absf(avg_a), 0.0001))]
	if cross_rel > 0.2 and cross_rel > (noise / maxf(absf(avg_a), 0.0001)) * 3.0:
		verdict = "FAIL: cross-position delta %.3f is %.1fx the noise floor %.3f — position leaks into the arm" % [
			cross_rel, cross_rel / (noise / maxf(absf(avg_a), 0.0001)), noise / maxf(absf(avg_a), 0.0001)]
	print("torque_probe: A avg=%.4f B avg=%.4f |cross|=%.4f (%.3f rel)  noise=%.3f rel -> %s" % [
		avg_a, avg_b, cross, cross_rel, noise / maxf(absf(avg_a), 0.0001), verdict])
	var passed: bool = not verdict.begins_with("FAIL")
	quit(0 if passed else 1)

func _search_pens(node: Node, player: String) -> PenBody:
	var body := node as PenBody
	if body != null and body.pen_id == player:
		return body
	for child in node.get_children():
		var found := _search_pens(child, player)
		if found != null:
			return found
	return null