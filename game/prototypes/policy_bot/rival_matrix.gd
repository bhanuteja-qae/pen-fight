extends SceneTree
## Round-by-round attribution probe for the frozen PolicyBot match rig.

const PolicyBotScript = preload("res://prototypes/policy_bot/policy_bot.gd")
const TABLE_RECT := Rect2(-590.0, -320.0, 1180.0, 640.0)
const SHOTS_PER_SERIES := 4
const PHYSICS_HZ := 60.0
const RESULT_PATH := "res://prototypes/policy_bot/.scratch/rival_matrix/results/rival_matrix.json"
const PAIRINGS := [
	{"red": "hitter", "blue": "auto", "seed": 91001},
	{"red": "spin", "blue": "auto", "seed": 91002},
	{"red": "edge", "blue": "auto", "seed": 91003},
	{"red": "hitter", "blue": "spin", "seed": 91004},
	{"red": "hitter", "blue": "edge", "seed": 91005},
	{"red": "spin", "blue": "edge", "seed": 91006},
]

var _series_index := 0
var _series: Dictionary = {}
var _matches: Array = []
var _rig: Node2D
var _pens: Dictionary = {}
var _turn_state: TurnState
var _auto_flick: AutoFlick
var _policy_rng := RandomNumberGenerator.new()
var _baseline_rng := RandomNumberGenerator.new()
var _shot_active := false
var _shot_frames := 0
var _shot_had_impact := false
var _active_shooter := ""
var _active_impulse := Vector2.ZERO
var _active_contact_offset := 0.0
var _scheduled_player := ""
var _shot_oobs: Array[String] = []
var _shot_records: Array = []
var _totals: Dictionary = {}


func _init() -> void:
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	physics_frame.connect(_on_physics_frame)
	_start_series()


func _start_series() -> void:
	if _series_index >= PAIRINGS.size():
		_write_results()
		return
	_series = PAIRINGS[_series_index].duplicate()
	_policy_rng.seed = int(_series["seed"])
	_baseline_rng.seed = int(_series["seed"]) + 500000
	_shot_records = []
	_totals = {
		"rounds_won_red": 0, "rounds_won_blue": 0,
		"self_oob_shots": 0, "opponent_oob_shots": 0,
		"knockouts": 0, "forfeits": 0,
		"sum_impulse": 0.0, "sum_abs_contact_offset": 0.0,
		"spin_shots": 0, "settle_time_s": 0.0,
	}
	_scheduled_player = ""
	_build_rig()


func _build_rig() -> void:
	_rig = Node2D.new()
	_rig.name = "RivalMatrixRig"
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
	if _series_index >= PAIRINGS.size():
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
		var shooter: PenBody = _pens[player]
		var opponent: PenBody = _pens[_other(player)]
		var direction := (opponent.global_position - shooter.global_position).normalized()
		if direction.length_squared() < 0.0001:
			direction = Vector2.RIGHT
		direction = (direction + direction.orthogonal() * _baseline_rng.randf_range(-0.35, 0.35)).normalized()
		_auto_flick.fire_now(player, direction * _baseline_rng.randf_range(0.5, 1.0), _baseline_rng.randf_range(-1.0, 1.0))
		return
	var candidate := PolicyBotScript.choose(_snapshot_for(player), persona, _policy_rng)
	_route_flick(player, candidate.direction * candidate.impulse, candidate.contact_offset, candidate)


func _on_auto_flick_requested(cmd: ShotCommand) -> void:
	_route_flick(cmd.slot(), cmd.direction() * cmd.power(), cmd.contact_offset())


func _route_flick(player: String, impulse: Vector2, contact_offset: float, candidate: Variant = null) -> void:
	if str(_turn_state.state().get("phase", "")) != TurnState.PHASE_AIM:
		return
	if str(_turn_state.state().get("current_player", "")) != player:
		return
	_shot_active = true
	_shot_frames = 0
	_shot_had_impact = false
	_active_shooter = player
	_active_impulse = impulse
	_active_contact_offset = contact_offset
	_shot_oobs = []
	_totals["sum_impulse"] = float(_totals["sum_impulse"]) + impulse.length()
	_totals["sum_abs_contact_offset"] = float(_totals["sum_abs_contact_offset"]) + absf(contact_offset)
	if absf(contact_offset) >= 0.5:
		_totals["spin_shots"] = int(_totals["spin_shots"]) + 1
	_turn_state.on_flick(impulse)
	if candidate != null:
		PolicyBotScript.commit(candidate as PolicyBotScript.Candidate, _pens[player])
	else:
		_pens[player].apply_flick(impulse.normalized(), impulse.length(), contact_offset)


func _finish_shot(phase: String) -> void:
	_shot_active = false
	var settle_time := float(_shot_frames) / PHYSICS_HZ
	_totals["settle_time_s"] = float(_totals["settle_time_s"]) + settle_time
	var state: Dictionary = _turn_state.state()
	var winner := str(state.get("round_winner", "")) if bool(state.get("round_over", false)) else ""
	var has_self_oob := _shot_oobs.has(_active_shooter)
	var opponent := _other(_active_shooter)
	var has_opponent_oob := _shot_oobs.has(opponent)
	var decided_by := "unresolved"
	if not _shot_oobs.is_empty():
		decided_by = "knockout" if has_opponent_oob and not has_self_oob else "oob"
	elif phase == TurnState.PHASE_ROUND_OVER:
		decided_by = "stalemate_forfeit"
	elif _shot_frames >= int(TurnState.RESOLVE_TIMEOUT * PHYSICS_HZ):
		decided_by = "backstop"
	if has_self_oob:
		_totals["self_oob_shots"] = int(_totals["self_oob_shots"]) + 1
	if has_opponent_oob:
		_totals["opponent_oob_shots"] = int(_totals["opponent_oob_shots"]) + 1
	if decided_by == "knockout":
		_totals["knockouts"] = int(_totals["knockouts"]) + 1
	if decided_by in ["stalemate_forfeit", "idle_forfeit"]:
		_totals["forfeits"] = int(_totals["forfeits"]) + 1
	if winner == "red":
		_totals["rounds_won_red"] = int(_totals["rounds_won_red"]) + 1
	elif winner == "blue":
		_totals["rounds_won_blue"] = int(_totals["rounds_won_blue"]) + 1
	_shot_records.append({
		"index": _shot_records.size(),
		"shooter": _active_shooter,
		"impulse": _rounded(_active_impulse.length()),
		"contact_offset": _rounded(_active_contact_offset),
		"oob_pen": "+".join(_shot_oobs),
		"oob_was_self": has_self_oob,
		"round_winner": winner,
		"decided_by": decided_by,
	})
	if phase == TurnState.PHASE_ROUND_OVER:
		for pen: PenBody in _pens.values():
			pen.reset()
		_turn_state.continue_to_next_round()
	_scheduled_player = ""
	if _shot_records.size() >= SHOTS_PER_SERIES:
		_matches.append(_metrics_record())
		_rig.queue_free()
		_series_index += 1
		call_deferred("_start_series")


func _on_pen_impact(_pen_uid: String, _speed: float) -> void:
	if _shot_active:
		_shot_had_impact = true


func _on_pen_oob(pen_uid: String) -> void:
	if _shot_active and not _shot_oobs.has(pen_uid):
		_shot_oobs.append(pen_uid)


func _snapshot_for(player: String) -> PolicyBotScript.Snapshot:
	var snapshot := PolicyBotScript.Snapshot.new()
	var pen: PenBody = _pens[player]
	var opponent: PenBody = _pens[_other(player)]
	snapshot.pen_pos = pen.global_position
	snapshot.pen_rot = pen.global_rotation
	snapshot.opp_pos = opponent.global_position
	snapshot.opp_rot = opponent.global_rotation
	snapshot.table_rect = TABLE_RECT
	snapshot.oob_margin = 13.0
	return snapshot


func _metrics_record() -> Dictionary:
	var shots := _shot_records.size()
	return {
		"seed": int(_series["seed"]),
		"red": str(_series["red"]),
		"blue": str(_series["blue"]),
		"shots": _shot_records,
		"totals": {
			"rounds_won_red": int(_totals["rounds_won_red"]),
			"rounds_won_blue": int(_totals["rounds_won_blue"]),
			"self_oob_shots": int(_totals["self_oob_shots"]),
			"opponent_oob_shots": int(_totals["opponent_oob_shots"]),
			"knockouts": int(_totals["knockouts"]),
			"forfeits": int(_totals["forfeits"]),
			"mean_impulse": _rounded(float(_totals["sum_impulse"]) / maxf(float(shots), 1.0)),
			"mean_abs_contact_offset": _rounded(float(_totals["sum_abs_contact_offset"]) / maxf(float(shots), 1.0)),
			"spin_usage": _rounded(float(_totals["spin_shots"]) / maxf(float(shots), 1.0)),
			"settle_time_s": _rounded(float(_totals["settle_time_s"]) / maxf(float(shots), 1.0)),
		},
	}


func _write_results() -> void:
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://prototypes/policy_bot/.scratch/rival_matrix/results"))
	if dir_error != OK:
		push_error("rival_matrix: FAIL — could not create results directory")
		quit(1)
		return
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("rival_matrix: FAIL — could not write results")
		quit(1)
		return
	file.store_string(JSON.stringify({"format": "rival-matrix-v1", "shots_per_series": SHOTS_PER_SERIES, "matches": _matches}, "\t", false) + "\n")
	file.close()
	print("rival_matrix: PASS — %d seeded series, %d shots; wrote %s" % [_matches.size(), PAIRINGS.size() * SHOTS_PER_SERIES, RESULT_PATH])
	quit(0)


func _other(player: String) -> String:
	return "blue" if player == "red" else "red"


func _rounded(value: float) -> float:
	return snappedf(value, 0.0001)
