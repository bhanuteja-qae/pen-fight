extends SceneTree
## Seeded, bounded real-physics sampling harness for the Wave-1 PolicyBot.
## This deliberately owns orchestration and measurement only: PolicyBot authors
## one flick, then PenBody and TurnState resolve the live outcome.

const PolicyBotScript = preload("res://prototypes/policy_bot/policy_bot.gd")
const TABLE_RECT := Rect2(-590.0, -320.0, 1180.0, 640.0)
const SERIES_SHOTS := 2
const PHYSICS_HZ := 60.0
const RESULT_PATH := "res://prototypes/policy_bot/results/wave2_seeded_matches.json"
const PAIRINGS := [
	{"red": "hitter", "blue": "auto", "seed": 91001},
	{"red": "spin", "blue": "auto", "seed": 91002},
	{"red": "edge", "blue": "auto", "seed": 91003},
	{"red": "hitter", "blue": "spin", "seed": 91004},
	{"red": "hitter", "blue": "edge", "seed": 91005},
	{"red": "spin", "blue": "edge", "seed": 91006},
]

var _failed := false
var _series_index := 0
var _series: Dictionary = {}
var _matches: Array = []
var _persona_totals: Dictionary = {}
var _rig: Node2D
var _pens: Dictionary = {}
var _turn_state: TurnState
var _policy_rng := RandomNumberGenerator.new()
var _baseline_rng := RandomNumberGenerator.new()
var _auto_flick: AutoFlick
var _shot_active := false
var _shot_frames := 0
var _shot_had_impact := false
var _shot_oob := false
var _active_shooter := ""
var _active_impulse := Vector2.ZERO
var _active_contact_offset := 0.0
var _scheduled_player := ""
var _sum_impulse := 0.0
var _series_shots := 0
var _sum_contact := 0.0
var _spin_shots := 0
var _sum_settle_time := 0.0
var _backstops := 0
var _no_impacts := 0
var _oobs := 0


func _init() -> void:
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	_persona_totals = {
		"hitter": _empty_totals(),
		"spin": _empty_totals(),
		"edge": _empty_totals(),
	}
	physics_frame.connect(_on_physics_frame)
	_start_series()


func _start_series() -> void:
	if _series_index >= PAIRINGS.size():
		_write_results()
		return
	_series = PAIRINGS[_series_index].duplicate()
	_policy_rng.seed = int(_series["seed"])
	_baseline_rng.seed = int(_series["seed"]) + 500000
	_sum_impulse = 0.0
	_series_shots = 0
	_sum_contact = 0.0
	_spin_shots = 0
	_sum_settle_time = 0.0
	_backstops = 0
	_no_impacts = 0
	_oobs = 0
	_scheduled_player = ""
	_build_rig()


func _build_rig() -> void:
	_rig = Node2D.new()
	_rig.name = "PolicyBotHarnessRig"
	root.add_child(_rig)
	var table := Node2D.new()
	table.name = "Table"
	_rig.add_child(table)
	var table_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = TABLE_RECT.size
	table_shape.shape = rect
	table.add_child(table_shape)
	_pens = {"red": _make_pen("red", Vector2(-160.0, -80.0)), "blue": _make_pen("blue", Vector2(160.0, 80.0))}
	_turn_state = TurnState.new(["red", "blue"], 5.0, TABLE_RECT)
	for pen: PenBody in _pens.values():
		pen.settled.connect(_turn_state.on_settled)
		pen.moved.connect(_turn_state.on_pen_moved)
		pen.out_of_bounds.connect(_on_pen_oob)
		pen.out_of_bounds.connect(_turn_state.on_out_of_bounds)
		pen.impact.connect(_on_pen_impact)
	_auto_flick = AutoFlick.new()
	_auto_flick.enabled = true
	_auto_flick.auto_flick_requested.connect(_on_auto_flick_requested)
	_rig.add_child(_auto_flick)
	_turn_state.begin_turn()


func _make_pen(pen_id: String, position: Vector2) -> PenBody:
	var pen := PenBody.new()
	pen.name = "Pen_%s" % pen_id
	pen.pen_id = pen_id
	pen.position = position
	pen.start_position = position
	pen.mass = 1.0
	pen.linear_damp = 2.0
	pen.angular_damp = 1.5
	pen.contact_monitor = true
	pen.max_contacts_reported = 4
	var shape_node := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 5.0
	capsule.height = 180.0
	shape_node.shape = capsule
	shape_node.rotation = PI * 0.5
	pen.add_child(shape_node)
	_rig.add_child(pen)
	return pen


func _on_physics_frame() -> void:
	if _failed or _series_index >= PAIRINGS.size():
		return
	if _shot_active:
		_shot_frames += 1
		_turn_state.resolve_pending_oob()
		_turn_state.resolve_tick(1.0 / PHYSICS_HZ)
		var phase := str(_turn_state.state().get("phase", ""))
		if phase != TurnState.PHASE_IN_FLIGHT:
			_finish_shot(phase)
			return
	_schedule_active_player()


func _schedule_active_player() -> void:
	var state: Dictionary = _turn_state.state()
	if str(state.get("phase", "")) != TurnState.PHASE_AIM:
		return
	var player := str(state.get("current_player", ""))
	if player == "" or player == _scheduled_player:
		return
	_scheduled_player = player
	var persona := str(_series[player])
	if persona == "auto":
		# AutoFlick remains the baseline emitter; its authored random input is
		# seeded here so it has the same reproducibility contract as PolicyBot.
		var shooter: PenBody = _pens[player]
		var opponent: PenBody = _pens[_other(player)]
		var direction := (opponent.global_position - shooter.global_position).normalized()
		if direction.length_squared() < 0.0001:
			direction = Vector2.RIGHT
		direction = (direction + direction.orthogonal() * _baseline_rng.randf_range(-0.35, 0.35)).normalized()
		_auto_flick.fire_now(player, direction * _baseline_rng.randf_range(0.5, 1.0), _baseline_rng.randf_range(-1.0, 1.0))
		return
	var snapshot := _snapshot_for(player)
	var candidate := PolicyBotScript.choose(snapshot, persona, _policy_rng)
	_route_flick(player, candidate.direction * candidate.impulse, candidate.contact_offset, candidate)


## Compat shim for the migrated AutoFlick payload (#6): the harness rig still
## applies directly to its own TurnState/PenBody (prototype, out of the
## production call-site scope); the command is split the same way.
func _on_auto_flick_requested(cmd: ShotCommand) -> void:
	_route_flick(cmd.slot(), cmd.direction() * cmd.power(), cmd.contact_offset())


func _route_flick(player: String, impulse: Vector2, contact_offset: float, candidate: Variant = null) -> void:
	if str(_turn_state.state().get("phase", "")) != TurnState.PHASE_AIM:
		return
	if str(_turn_state.state().get("current_player", "")) != player:
		return
	_shot_active = true
	_series_shots += 1
	_shot_frames = 0
	_shot_had_impact = false
	_shot_oob = false
	_active_shooter = player
	_active_impulse = impulse
	_active_contact_offset = contact_offset
	_sum_impulse += impulse.length()
	_sum_contact += absf(contact_offset)
	if absf(contact_offset) >= 0.5:
		_spin_shots += 1
	_turn_state.on_flick(impulse)
	if candidate != null:
		PolicyBotScript.commit(candidate as PolicyBotScript.Candidate, _pens[player])
	else:
		_pens[player].apply_flick(impulse.normalized(), impulse.length(), contact_offset)


func _finish_shot(_phase: String) -> void:
	_shot_active = false
	var settle_time := float(_shot_frames) / PHYSICS_HZ
	_sum_settle_time += settle_time
	if _shot_frames >= int(TurnState.RESOLVE_TIMEOUT * PHYSICS_HZ):
		_backstops += 1
	if not _shot_had_impact:
		_no_impacts += 1
	if _shot_oob:
		_oobs += 1
	_record_persona_shot(str(_series[_active_shooter]), settle_time)
	var shots := _shots_so_far()
	if str(_turn_state.state().get("phase", "")) == TurnState.PHASE_ROUND_OVER:
		for pen: PenBody in _pens.values():
			pen.reset()
		_turn_state.continue_to_next_round()
	_scheduled_player = ""
	if shots >= SERIES_SHOTS:
		_matches.append(_metrics_record())
		_rig.queue_free()
		_series_index += 1
		call_deferred("_start_series")


func _on_pen_impact(_pen_uid: String, _speed: float) -> void:
	if _shot_active:
		_shot_had_impact = true


func _on_pen_oob(_pen_uid: String) -> void:
	if _shot_active:
		_shot_oob = true


func _snapshot_for(player: String) -> PolicyBotScript.Snapshot:
	var pen: PenBody = _pens[player]
	var opponent: PenBody = _pens[_other(player)]
	var snapshot := PolicyBotScript.Snapshot.new()
	snapshot.pen_pos = pen.global_position
	snapshot.pen_rot = pen.global_rotation
	snapshot.opp_pos = opponent.global_position
	snapshot.opp_rot = opponent.global_rotation
	snapshot.table_rect = TABLE_RECT
	snapshot.oob_margin = 13.0
	return snapshot


func _metrics_record() -> Dictionary:
	var shots := _shots_so_far()
	return {
		"seed": int(_series["seed"]),
		"red": str(_series["red"]),
		"blue": str(_series["blue"]),
		"backstop_rate": _rate(_backstops, shots),
		"no_impact_rate": _rate(_no_impacts, shots),
		"oob_rate": _rate(_oobs, shots),
		"shots": shots,
		"mean_impulse": _rounded(_sum_impulse / shots),
		"mean_contact_offset": _rounded(_sum_contact / shots),
		"spin_usage": _rate(_spin_shots, shots),
		"settle_time_s": _rounded(_sum_settle_time / shots),
	}


func _write_results() -> void:
	var result := {
		"format": "policy-bot-wave2-v1",
		"series_shots": SERIES_SHOTS,
		"matches": _matches,
		"persona_metrics": _persona_metrics(),
	}
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://prototypes/policy_bot/results"))
	if dir_error != OK:
		_finish(false, "could not create results directory (%d)" % dir_error)
		return
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file == null:
		_finish(false, "could not write %s" % RESULT_PATH)
		return
	file.store_string(JSON.stringify(result, "\t", false) + "\n")
	file.close()
	print("match_harness: ALL PASS — %d seeded series, %d shots; wrote %s" % [
		_matches.size(), PAIRINGS.size() * SERIES_SHOTS, RESULT_PATH])
	quit(0)


func _shots_so_far() -> int:
	return _series_shots


func _rate(numerator: int, denominator: int) -> float:
	return _rounded(float(numerator) / maxf(float(denominator), 1.0))


func _rounded(value: float) -> float:
	return snappedf(value, 0.0001)


func _other(player: String) -> String:
	return "blue" if player == "red" else "red"


func _empty_totals() -> Dictionary:
	return {
		"shots": 0,
		"backstops": 0,
		"no_impacts": 0,
		"oobs": 0,
		"sum_impulse": 0.0,
		"sum_contact": 0.0,
		"spin_shots": 0,
		"sum_settle_time": 0.0,
	}


func _record_persona_shot(controller: String, settle_time: float) -> void:
	if not _persona_totals.has(controller):
		return  # AutoFlick is the comparison baseline, not a policy persona.
	var total: Dictionary = _persona_totals[controller]
	total["shots"] = int(total["shots"]) + 1
	total["backstops"] = int(total["backstops"]) + (1 if _shot_frames >= int(TurnState.RESOLVE_TIMEOUT * PHYSICS_HZ) else 0)
	total["no_impacts"] = int(total["no_impacts"]) + (0 if _shot_had_impact else 1)
	total["oobs"] = int(total["oobs"]) + (1 if _shot_oob else 0)
	# The active shot's authored input is already represented in the series sums;
	# retain it per controller so docs can distinguish policy personas directly.
	total["sum_impulse"] = float(total["sum_impulse"]) + _active_impulse.length()
	total["sum_contact"] = float(total["sum_contact"]) + absf(_active_contact_offset)
	total["spin_shots"] = int(total["spin_shots"]) + (1 if absf(_active_contact_offset) >= 0.5 else 0)
	total["sum_settle_time"] = float(total["sum_settle_time"]) + settle_time


func _persona_metrics() -> Array:
	var result: Array = []
	for persona in ["hitter", "spin", "edge"]:
		var total: Dictionary = _persona_totals[persona]
		var shots: int = int(total["shots"])
		result.append({
			"persona": persona,
			"backstop_rate": _rate(int(total["backstops"]), shots),
			"no_impact_rate": _rate(int(total["no_impacts"]), shots),
			"oob_rate": _rate(int(total["oobs"]), shots),
			"shots": shots,
			"mean_impulse": _rounded(float(total["sum_impulse"]) / maxf(float(shots), 1.0)),
			"mean_contact_offset": _rounded(float(total["sum_contact"]) / maxf(float(shots), 1.0)),
			"spin_usage": _rate(int(total["spin_shots"]), shots),
			"settle_time_s": _rounded(float(total["sum_settle_time"]) / maxf(float(shots), 1.0)),
		})
	return result


func _finish(passed: bool, detail: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("match_harness: %s — %s" % ["PASS" if passed else "FAIL", detail])
	quit(0 if passed else 1)
