extends SceneTree
class_name AutoFlickTest
## Phase 1b deterministic headless knockout test (docs/phase1b-contract.md — Agent F).
##
## Instantiates the REAL game scene (res://scenes/main.tscn), adds an AutoFlick
## emitter (enabled), and drives rounds headlessly to a REAL knockout — a pen
## leaving the table — through the project's single submission boundary: the
## harness emits a ShotCommand and this test submits it via Main._submit_shot,
## the same boundary the human adapter calls. Settle-handoff gates are tapped
## through like a human at the table (the boundary rejects while a gate is up).
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
## SceneTree.physics_frame signal (fixed timestep; the tick rate lives in
## project.godot) and setup is deferred from _init() to the first process
## frame so the tree (root window + physics server) is fully live before the
## scene is instantiated.

const EDGE_POWER: float = 1.0            # full-power edge shot: direction * power, power in 0..1
const FLICK_DELAY_SEC: float = 0.4       # seconds after the active player's AIM begins
const MAX_TEST_SECONDS: float = 12.0     # simulated-seconds budget (frames = 12 x tick rate)

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
	# Route the harness command through the shared submission boundary — the
	# same Main._submit_shot the human adapter calls. _submit_shot is atomic:
	# a duplicate routing could never double-apply.
	_auto_flick.auto_flick_requested.connect(_on_harness_command)
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
	# A decided round parks in ROUND_OVER (OOB knockout or forfeit). PHASE_FORFEIT
	# and PHASE_GAME_OVER no longer exist — never assigned in the shipped build,
	# so a merged TurnState that set them would be a real bug, not a legacy shape.
	if phase == TurnState.PHASE_ROUND_OVER:
		var winner: String = str(snapshot.get("winner", ""))
		if winner == "":
			_finish(false, "round ended in %s but no winner was declared" % phase)
		else:
			_finish(true, "round resolved — winner=%s loser=%s phase=%s shots_this_round=%d (total=%d)" % [
				snapshot.get("winner", "?"), snapshot.get("loser", "?"), phase,
				_shots_fired - _round_start_shots, _shots_fired])
		return
	if _elapsed_seconds() >= MAX_TEST_SECONDS:
		_finish(false, "no round resolved within %.0fs of simulated time (phase=%s, shots=%d)" % [
			MAX_TEST_SECONDS, phase, _shots_fired])
		return
	# Tap through any gate Main is showing (e.g. a settle handoff): the shared
	# submission boundary rejects commands while a gate is up.
	if bool(_main.get("_gate_showing")):
		_main.call("_on_gate_tapped")
		_scheduled_player = ""
		return
	_schedule_for_active_player(snapshot)


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
## the nearest table edge no matter where it settled this round. Full power —
## the emitted ShotCommand carries direction * power with power in the 0..1
## contract range.
func _edge_impulse(pen: PenBody) -> Vector2:
	var away: Vector2 = pen.global_position
	if away.length_squared() < 1.0:
		away = Vector2.RIGHT
	return away.normalized() * EDGE_POWER


## Submit the harness command through the one session boundary (Main's
## _submit_shot) — no parallel TurnState/PenBody application here. Counts only
## accepted commits so the report shows real shots.
func _on_harness_command(cmd: ShotCommand) -> void:
	if _main == null:
		return
	if bool(_main.call("_submit_shot", cmd)):
		_shots_fired += 1


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
	return float(_physics_frames) / float(Engine.physics_ticks_per_second)
