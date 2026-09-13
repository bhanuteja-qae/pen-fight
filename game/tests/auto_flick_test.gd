extends SceneTree
class_name AutoFlickTest
## Phase 1b deterministic headless knockout test (docs/phase1b-contract.md — Agent F).
##
## Instantiates the REAL game scene (res://scenes/main.tscn), adds an AutoFlick
## emitter (enabled), and drives rounds headlessly to a REAL knockout — a pen
## leaving the table — through the human-flick routing path: TurnState.on_flick
## + PenBody.apply_flick, exactly what Main._on_flick_ready does minus the drag
## math. The turn-transition gate (Agent G's TurnGate) is inert here: the test
## never delivers input events, and the auto-flick routing is wired directly to
## the auto_flick_requested signal, so Main's _input_locked can never block it.
##
## Physics is non-deterministic run-to-run (docs/RESEARCH.md §4.1), so this test
## is TOLERANT: it asserts that a ROUND ENDS with a winner — OOB knockout or the
## forfeit path — never which pen wins. If no round resolves within
## MAX_TEST_SECONDS of simulated time the test FAILS: that is the signal that a
## knockout is unreachable (the bug this harness exists to catch).
##
## Run headless (project root is game/):
##   godot --headless --path game --script res://tests/auto_flick_test.gd
## (exit code 0 = pass, 1 = fail)
##
## Entry convention mirrors turn_state_test.gd: `extends SceneTree` with _init()
## driving the run and quit(0|1) at the end. This test needs LIVE physics
## frames, so it cannot be a static pure-logic test — the poll is driven by the
## SceneTree.physics_frame signal (60 Hz) and setup is deferred from _init() to
## the first process frame so the tree (root window + physics server) is fully
## live before the scene is instantiated.

const STRONG_IMPULSE: float = 1000000.0  # direction * magnitude impulse toward the table edge
const FLICK_DELAY_SEC: float = 0.4       # seconds after the active player's AIM begins
const MAX_TEST_SECONDS: float = 12.0     # budget (720 physics frames @ 60 Hz)

var _main: Node = null
var _auto_flick: AutoFlick = null
var _turn_state: Variant = null
var _physics_frames: int = 0
var _shots_fired: int = 0
var _round_start_shots: int = 0
var _scheduled_player: String = ""
var _done: bool = false


func _init() -> void:
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_finish(false, "could not load res://scenes/main.tscn")
		return
	_main = packed.instantiate()
	root.add_child(_main)

	_auto_flick = AutoFlick.new()
	root.add_child(_auto_flick)
	_auto_flick.enabled = true
	# Route the auto-flick through the human-flick path. If Main (Agent G) also
	# connects auto_flick_requested, the AIM guard in _on_auto_flick_requested
	# keeps exactly one application — never a double impulse.
	_auto_flick.auto_flick_requested.connect(_on_auto_flick_requested)
	_turn_state = _main.get("turn_state")

	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	if _done:
		return
	_physics_frames += 1
	if _turn_state == null:
		_turn_state = _main.get("turn_state") if _main != null else null
	if _turn_state == null:
		if _elapsed_seconds() >= MAX_TEST_SECONDS:
			_finish(false, "Main.turn_state never became available")
		return
	var snapshot: Dictionary = _turn_state.state()
	var phase: String = str(snapshot.get("phase", ""))
	# A decided round parks in ROUND_OVER (OOB knockout or forfeit). Accept the
	# legacy GAME_OVER phase too in case a merged TurnState still uses it.
	if phase == TurnState.PHASE_ROUND_OVER or phase == TurnState.PHASE_GAME_OVER:
		var winner: String = str(snapshot.get("winner", ""))
		if winner == "":
			_finish(false, "round ended in %s but no winner was declared" % phase)
		else:
			_finish(true, "round resolved — winner=%s loser=%s phase=%s shots_this_round=%d (total=%d)" % [
				snapshot.get("winner", "?"), snapshot.get("loser", "?"), phase,
				_shots_fired - _round_start_shots, _shots_fired])
		return
	_schedule_for_active_player(snapshot)
	if _elapsed_seconds() >= MAX_TEST_SECONDS:
		_finish(false, "no round resolved within %.0fs of simulated time (phase=%s, shots=%d)" % [
			MAX_TEST_SECONDS, phase, _shots_fired])


func _schedule_for_active_player(snapshot: Dictionary) -> void:
	if str(snapshot.get("phase", "")) != TurnState.PHASE_AIM:
		return
	var player: String = str(snapshot.get("current_player", ""))
	if player == "" or player == _scheduled_player:
		return  # no turn yet, or a flick for this player is already pending
	var pen := _find_pen(player)
	if pen == null:
		_finish(false, "active player '%s' has no PenBody in the scene tree" % player)
		return
	_scheduled_player = player
	_round_start_shots = _shots_fired
	_auto_flick.schedule_flick(player, _edge_impulse(pen), FLICK_DELAY_SEC)


## Push the pen radially away from the table center (the origin) so it leaves
## the nearest table edge no matter where it settled this round.
func _edge_impulse(pen: PenBody) -> Vector2:
	var away: Vector2 = pen.global_position
	if away.length_squared() < 1.0:
		away = Vector2.RIGHT
	return away.normalized() * STRONG_IMPULSE


## Mirror Main._on_flick_ready minus the slingshot drag math: record the
## impulse in TurnState and apply it to the pen. Guarded on AIM so a duplicate
## routing (if Main also connected the signal) can never double-fire.
func _on_auto_flick_requested(player: String, impulse: Vector2, contact_offset: float = 0.0) -> void:
	if _turn_state == null:
		return
	var snapshot: Dictionary = _turn_state.state()
	if str(snapshot.get("phase", "")) != TurnState.PHASE_AIM:
		return
	if str(snapshot.get("current_player", "")) != player:
		return
	_shots_fired += 1
	_turn_state.on_flick(impulse)
	var pen := _find_pen(player)
	if pen != null:
		pen.apply_flick(impulse.normalized(), impulse.length(), contact_offset)


func _find_pen(player: String) -> PenBody:
	return _search_pens(root, player)


func _search_pens(node: Node, player: String) -> PenBody:
	var body := node as PenBody
	if body != null and body.pen_id == player:
		return body
	for child in node.get_children():
		var found := _search_pens(child, player)
		if found != null:
			return found
	return null


func _finish(passed: bool, detail: String) -> void:
	if _done:
		return
	_done = true
	print("auto_flick_test: %s — %s (frames=%d, shots=%d, elapsed=%.2fs)" % [
		"PASS" if passed else "FAIL", detail, _physics_frames, _shots_fired, _elapsed_seconds()])
	quit(0 if passed else 1)


func _elapsed_seconds() -> float:
	return float(_physics_frames) / 60.0
