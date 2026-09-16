extends SceneTree
## Regression: a full-power flick into an ADJACENT pen must HIT it.
##
## Bug (user report, 2026-09-15): with two pens resting adjacent, taking a turn
## and dragging into the neighbouring pen produced no hit at all — the flicked
## pen ran straight through it and off the table. Headless probes on the real
## scene reproduced it deterministically at the project's then-60 Hz tick rate:
## a full-power flick covers 26.7 px per physics tick while the contact window
## between two 10 px-thick capsules is roughly 20 px wide, so the discrete
## narrowphase either skipped the overlap entirely (tunnel: 0 px transferred)
## or sampled it past the closest approach (dead mush: ~0 px/s transfer).
##
## Fix: `physics/common/physics_ticks_per_second` raised to 240 -> 6.7 px per
## step, several samples inside every approach window. This suite pins the
## behaviour with thresholds that separate a real hit from both failure modes:
##
##   1. parallel_gap10_p10  parallel pens, surfaces touching, power 1.0
##   2. parallel_gap12_p10  parallel, 2 px surface gap, power 1.0
##   3. parallel_gap16_p10  parallel, 6 px surface gap, power 1.0
##   4. parallel_gap20_p10  parallel, 10 px surface gap, power 1.0
##   5. parallel_gap12_p05  case 2 at half power (power-scaling pair with 2.)
##   6. endon_p10           tip-to-tip, power 1.0
##   7. miss_away_p10       flick AWAY — the neighbour must stay put
##   8. power_scaling_p10_vs_p05  derived: peak transfer must scale with power
##
## Every case instantiates a fresh main.tscn, so no state leaks between cases.
##
## Run (cwd = game/):
##   godot --headless --path . --script res://tests/adjacent_pen_hit_test.gd

const MAIN_SCENE := "res://scenes/main.tscn"
## Simulated seconds observed after the flick (frame count scales with the
## tick rate; the observation window is fixed in simulated time).
const SIM_SECONDS := 0.5
## Verdict thresholds. Measured at 240 Hz: real hits moved the neighbour
## 121-245 px at 390-790 px/s; the 60 Hz failure modes measured <= 3.5 px at
## <= 61 px/s. The bands are far apart, so the thresholds sit well inside the
## healthy region while still failing both historical bug shapes.
const HIT_MIN_MOVED := 80.0
const HIT_MIN_SPEED := 180.0
## The miss case: the neighbour must not move beyond solver jitter.
const MISS_MAX_MOVED := 2.0
const MISS_MAX_SPEED := 60.0
## A 1.0 flick must transfer meaningfully more than a 0.5 flick.
const POWER_SCALE_MIN_RATIO := 1.3

var _packed: PackedScene = null
var _failures: Array[String] = []
var _peak_speed: Dictionary = {}
var _cases_run := 0
var _verdicts := 0
var _verdict_taken := false
var _current_case := ""


func _init() -> void:
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	_packed = load(MAIN_SCENE)
	if _packed == null:
		_finish(false, "adjacent_pen_hit_test: could not load res://scenes/main.tscn")
		return
	print("adjacent_pen_hit_test @ %d Hz physics (%d frames per case)" % [
		Engine.physics_ticks_per_second, _sim_frames()])
	await _case_parallel("parallel_gap10_p10", 10.0, 1.0)
	await _case_parallel("parallel_gap12_p10", 12.0, 1.0)
	await _case_parallel("parallel_gap16_p10", 16.0, 1.0)
	await _case_parallel("parallel_gap20_p10", 20.0, 1.0)
	await _case_parallel("parallel_gap12_p05", 12.0, 0.5)
	await _case_endon("endon_p10", 1.0)
	await _case_miss_away("miss_away_p10", 1.0)
	_check_power_scaling()
	_finish(_failures.is_empty(), _summary())


# ------------------------------------------------------------------- cases

## Parallel pens (both barrels horizontal), red above blue; red flicks
## straight down into the neighbour. gap = centre-to-centre distance in px
## (10 = surfaces exactly touching, sum of the two 5 px-radius capsules).
func _case_parallel(case_name: String, gap: float, power: float) -> void:
	_enter(case_name)
	var result: Dictionary = await _flick_and_measure(
		Vector2(0.0, -gap), 0.0, 0.0, Vector2(0.0, 1.0), power)
	if result.is_empty():
		return
	var moved: float = result["moved"]
	var peak: float = result["peak"]
	_peak_speed[case_name] = peak
	if moved >= HIT_MIN_MOVED and peak >= HIT_MIN_SPEED:
		print("%s: neighbour moved %.1f px, peak %.1f px/s — PASS" % [
			case_name, moved, peak])
		_leave()
	else:
		_fail("neighbour did not react: moved=%.1f px, peak=%.1f px/s (need >= %.0f px and >= %.0f px/s)" % [
			moved, peak, HIT_MIN_MOVED, HIT_MIN_SPEED])


## Tip-to-tip: red behind blue on the barrel axis, flicks forward.
func _case_endon(case_name: String, power: float) -> void:
	_enter(case_name)
	var result: Dictionary = await _flick_and_measure(
		Vector2(-180.0, 0.0), 0.0, 0.0, Vector2(1.0, 0.0), power)
	if result.is_empty():
		return
	var moved: float = result["moved"]
	var peak: float = result["peak"]
	if moved >= HIT_MIN_MOVED and peak >= HIT_MIN_SPEED:
		print("%s: neighbour moved %.1f px, peak %.1f px/s — PASS" % [
			case_name, moved, peak])
		_leave()
	else:
		_fail("neighbour did not react: moved=%.1f px, peak=%.1f px/s (need >= %.0f px and >= %.0f px/s)" % [
			moved, peak, HIT_MIN_MOVED, HIT_MIN_SPEED])


## Flick AWAY from the neighbour (same parallel setup, opposite direction):
## the neighbour must stay asleep — guards against a "make everything collide"
## cheat fix.
func _case_miss_away(case_name: String, power: float) -> void:
	_enter(case_name)
	var result: Dictionary = await _flick_and_measure(
		Vector2(0.0, -12.0), 0.0, 0.0, Vector2(0.0, -1.0), power)
	if result.is_empty():
		return
	var moved: float = result["moved"]
	var peak: float = result["peak"]
	if moved <= MISS_MAX_MOVED and peak <= MISS_MAX_SPEED:
		print("%s: neighbour undisturbed (moved %.1f px, peak %.1f px/s) — PASS" % [
			case_name, moved, peak])
		_leave()
	else:
		_fail("neighbour moved on a miss: moved=%.1f px, peak=%.1f px/s" % [moved, peak])


## Derived case: the 1.0 and 0.5 parallel cases must show power scaling.
func _check_power_scaling() -> void:
	_enter("power_scaling_p10_vs_p05")
	var hi: float = _peak_speed.get("parallel_gap12_p10", -1.0)
	var lo: float = _peak_speed.get("parallel_gap12_p05", -1.0)
	if hi < 0.0 or lo < 0.0:
		_fail("prerequisite hit cases did not run")
		return
	if lo <= 0.0:
		_fail("half-power flick transferred nothing (peak=%.1f px/s)" % lo)
		return
	if hi / lo < POWER_SCALE_MIN_RATIO:
		_fail("peak transfer does not scale with power: %.1f px/s @1.0 vs %.1f px/s @0.5 (ratio < %.1f)" % [
			hi, lo, POWER_SCALE_MIN_RATIO])
		return
	print("power_scaling_p10_vs_p05: %.1f px/s @1.0 vs %.1f px/s @0.5 — PASS" % [hi, lo])
	_leave()


# ------------------------------------------------------------ measurement rig

## Instantiate a fresh scene, place the pens, flick red, and observe blue for
## SIM_SECONDS of simulated time. Returns {moved, peak} for blue, or {} if the
## scene could not be prepared.
func _flick_and_measure(red_pos: Vector2, red_rot: float, blue_rot: float,
		dir: Vector2, power: float) -> Dictionary:
	var main: Node = _packed.instantiate()
	root.add_child(main)
	await process_frame
	var red: RigidBody2D = main.get_node_or_null("PenRed")
	var blue: RigidBody2D = main.get_node_or_null("PenBlue")
	if red == null or blue == null:
		_fail("scene is missing PenRed/PenBlue")
		main.free()
		await process_frame
		return {}
	blue.global_position = Vector2.ZERO
	blue.rotation = blue_rot
	red.global_position = red_pos
	red.rotation = red_rot
	red.linear_velocity = Vector2.ZERO
	red.angular_velocity = 0.0
	blue.linear_velocity = Vector2.ZERO
	blue.angular_velocity = 0.0
	await _settle(2)
	red.apply_flick(dir, power, 0.0)
	var blue_start: Vector2 = blue.global_position
	var peak := 0.0
	for i in _sim_frames():
		await physics_frame
		peak = maxf(peak, blue.linear_velocity.length())
	var moved := blue.global_position.distance_to(blue_start)
	main.free()
	await process_frame
	return {"moved": moved, "peak": peak}


func _sim_frames() -> int:
	return int(round(SIM_SECONDS * float(Engine.physics_ticks_per_second)))


func _settle(frames: int) -> void:
	for i in range(frames):
		await physics_frame


# ------------------------------------------------------- case-verdict harness

func _enter(case_name: String) -> void:
	_current_case = case_name
	_cases_run += 1
	_verdict_taken = false


func _leave() -> void:
	if not _verdict_taken:
		_verdict_taken = true
		_verdicts += 1


func _fail(why: String) -> void:
	if not _verdict_taken:
		_verdict_taken = true
		_verdicts += 1
	_failures.append("%s: %s" % [_current_case, why])
	push_error("adjacent_pen_hit_test FAIL %s — %s" % [_current_case, why])


func _summary() -> String:
	if _failures.is_empty():
		return "adjacent_pen_hit_test: ALL PASS (%d cases)" % _cases_run
	return "adjacent_pen_hit_test: %d of %d cases FAILED — %s" % [
		_failures.size(), _cases_run, "; ".join(_failures)]


func _finish(ok: bool, msg: String) -> void:
	var silent: int = _cases_run - _verdicts
	if silent > 0:
		ok = false
		msg += "  [HARNESS] %d case(s) aborted without a verdict (last: %s)" % [_cases_run - _verdicts, _current_case]
	print(msg)
	quit(0 if ok else 1)
