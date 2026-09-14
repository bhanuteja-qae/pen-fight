extends SceneTree
class_name RoundsGateTest
## Phase 1 20-round gate test (docs/RESEARCH.md §5 — "Gate: 20 rounds, want a 21st").
##
## Headless mechanical proxy for the playtest gate. Drives the REAL scene
## (res://scenes/main.tscn) through TARGET_ROUNDS played rounds, each reaching a
## verdict — OOB knockout or forfeit — exactly like a human could, but with a
## scripted strong flick fired at each AIM turn (mirroring AutoFlick's
## signal path, which routes through TurnState + PenBody like Main._on_flick_ready).
## Between rounds it mimics Main._on_gate_tapped: reset both pens, then
## TurnState.continue_to_next_round() (winner starts next round, hot-seat).
##
## What this does NOT assert (honestly): "want a 21st" is a human-fun signal that
## no headless harness can measure. What it DOES assert mechanically: 20 rounds
## each resolve to a winner, the game never deadlocks or crashes, the turn gate
## flows into the next round, and BOTH players win at least once — i.e. the
## knockout loop is reachable from both sides. The human playtest gate remains a
## separate step, but "can the game sustain 20 rounds" is now proven in CI.
##
## Physics is non-deterministic run-to-run (docs §4.1), so per-round outcomes are
## tolerant: a round must END with a winner (knockout or forfeit, either pen).
## Rare settle-advances (both pens stay on the table -> next player, no winner)
## are counted as no-decision rounds and re-run — the gate needs 20 RESOLVED
## rounds. FAIL if the total budget elapses before the target is hit.
##
## Run headless (project root is game/):
##   godot --headless --path game --script res://tests/rounds_gate_test.gd
## (exit code 0 = gate PASS, 1 = FAIL)

const TARGET_ROUNDS: int = 20
## Human-scale flicks with seeded power RANGE: a perfect full-power kill shot
## every turn would trivially resolve every round (shooter always wins). Real
## play varies — underpowered shots leave both pens on (no decision -> the
## round re-fires), overpowered shots can overshoot the shooter off. So draw
## power from 0.5..1.0 per shot with a FIXED seed: deterministic in CI, but the
## natural physics of the miss/hit spread is what exercises feel. (MAX_IMPULSE
## lives INSIDE apply_flick — the test passes the human 0..1 fraction, never
## a raw magnitude, or the impulse double-scales.)
const SHOT_POWER_MIN: float = 0.5
const SHOT_POWER_MAX: float = 1.0
const POWER_SEED: int = 42
const FLICK_DELAY_SEC: float = 0.4
const MAX_TEST_SECONDS: float = 600.0   # generous: collisions + settle need time

var _main: Node = null
var _turn_state: Variant = null
var _physics_frames: int = 0
var _shots_fired: int = 0
var _round_start_shots: int = 0
var _rounds_resolved: int = 0
var _no_decision_rounds: int = 0
var _wins: Dictionary = {}
var _losers: Dictionary = {}
var _scheduled_player: String = ""
var _round_over_pens: Array = []
var _done: bool = false
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_finish(false, "could not load res://scenes/main.tscn")
		return
	_main = packed.instantiate()
	root.add_child(_main)
	_turn_state = _main.get("turn_state")
	_rng.seed = POWER_SEED
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
	if phase == TurnState.PHASE_ROUND_OVER:
		_on_round_over(snapshot)
		return
	_schedule_for_active_player(snapshot)
	if _elapsed_seconds() >= MAX_TEST_SECONDS:
		_finish(false, "budget elapsed at %d/%d resolved rounds (phase=%s, shots=%d)" % [
			_rounds_resolved, TARGET_ROUNDS, phase, _shots_fired])


## A decided round parked in ROUND_OVER (OOB or forfeit). Record the outcome,
## then mimic Main._on_gate_tapped to start the next round: reset both pens and
## continue_to_next_round() (winner starts next round, hot-seat cycling).
func _on_round_over(snapshot: Dictionary) -> void:
	var winner: String = str(snapshot.get("winner", ""))
	var loser: String = str(snapshot.get("loser", ""))
	if winner == "":
		_finish(false, "round ended in %s but no winner declared" % str(snapshot.get("phase", "?")))
		return
	_wins[winner] = _wins.get(winner, 0) + 1
	_losers[loser] = _losers.get(loser, 0) + 1
	var shots_this_round: int = _shots_fired - _round_start_shots
	print("[ROUND %02d] %s beats %s (shots=%d, total=%-3d elapsed=%.1fs) %s" % [
		_rounds_resolved + 1, winner, loser, shots_this_round, _shots_fired, _elapsed_seconds(),
		""])
	_rounds_resolved += 1
	if _rounds_resolved >= TARGET_ROUNDS:
		_finish(true, "")
		return
	# Tap-to-restart (docs §3.5 #7 / Main._on_gate_tapped): reset both pens and
	# continue to the next round so the winner starts it.
	var pen_red: PenBody = _find_pen("red")
	var pen_blue: PenBody = _find_pen("blue")
	if pen_red != null:
		pen_red.reset()
	if pen_blue != null:
		pen_blue.reset()
	var st_before: String = str(_turn_state.state().get("phase", ""))
	_turn_state.continue_to_next_round()
	_scheduled_player = ""
	# Guards re-armed in Main; the test mirrors them so a fresh round can't
	# accidentally reuse a stale winner.
	var st_after: String = str(_turn_state.state().get("phase", ""))
	if st_after != TurnState.PHASE_AIM:
		_finish(false, "continue_to_next_round from %s left phase=%s (expected AIM)" % [st_before, st_after])


func _schedule_for_active_player(snapshot: Dictionary) -> void:
	if str(snapshot.get("phase", "")) != TurnState.PHASE_AIM:
		return
	var player: String = str(snapshot.get("current_player", ""))
	if player == "" or player == _scheduled_player:
		return
	var pen := _find_pen(player)
	if pen == null:
		_finish(false, "active player '%s' has no PenBody in the scene tree" % player)
		return
	_scheduled_player = player
	_round_start_shots = _shots_fired
	# Fire directly (no timer) so a slow CI box can't drift the timeline: the
	# flick lands on the next physics frame after the AIM guard passes.
	var target := _find_pen(_other_player(player))
	if target == null:
		_finish(false, "active player '%s' has no opponent PenBody" % player)
		return
	var shot: Vector2 = _shot_impulse(pen, target)
	_round_start_shots = _shots_fired
	# Human-path launch with varied power (seeded, 0.5..1.0): Deterministic in
	# CI, but the natural miss/hit spread exercises real physics (no-decision
	# settles, overshoot self-losses) instead of a perfect kill shot every turn.
	var power: float = _rng.randf_range(SHOT_POWER_MIN, SHOT_POWER_MAX)
	_launch(player, pen, shot, power)


## The real game move: fire the ACTIVE pen at the OPPONENT pen (collision
## knock-off), not radially away (self-eject). Power is the human 0..1 drag
## fraction (apply_flick multiplies it by MAX_IMPULSE internally — the test
## MUST pass the fraction, not a raw magnitude, or the impulse double-scales).
## Full power 1.0 travels ~762px (≈1600/(1·2.1)), so from ±280 the active pen
## reaches past the opponent at ±280 and stops ~78px short of the far edge
## (radius-10 threshold at ±550): sometimes the hit knocks the defender off,
## sometimes both stay on (no decision -> re-run), occasionally the shooter
## overshoots itself off. That is the actual loop.
const SHOT_POWER: float = 1.0

func _shot_impulse(shooter: PenBody, target: PenBody) -> Vector2:
	var toward: Vector2 = target.global_position - shooter.global_position
	if toward.length_squared() < 1.0:
		toward = Vector2.RIGHT
	return toward.normalized()


## Mirror Main._on_flick_ready minus the slingshot drag math: record the
## impulse in TurnState and apply the human (direction, power) shape to the pen.
func _launch(player: String, pen: PenBody, direction: Vector2, power: float) -> void:
	if _turn_state == null:
		return
	var snapshot: Dictionary = _turn_state.state()
	if str(snapshot.get("phase", "")) != TurnState.PHASE_AIM:
		return
	if str(snapshot.get("current_player", "")) != player:
		return
	_shots_fired += 1
	_turn_state.on_flick(direction * power)
	pen.apply_flick(direction, power)


func _other_player(player: String) -> String:
	if player == "red":
		return "blue"
	return "red"


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
	if passed and detail == "":
		detail = "20-round gate sustained"
	var red_wins: int = _wins.get("red", 0)
	var blue_wins: int = _wins.get("blue", 0)
	# Balance floor (review, QA-1): both sides must WIN at least once. A 0/N
	# split means one side can literally never win — a real regression. Note
	# the observed 4/16-type splits are streak-driven (pre-resize the same seed
	# gave 13/7), not left/right asymmetry: the test drives both sides
	# identically from point-symmetric spawns, so a structural side advantage is
	# ruled out by construction. The round-start convention is strict
	# alternation (TurnState.begin_turn — whoever did not flick last starts),
	# which hands the next round to the winner in the common self-OOB case and
	# to the loser on a knockout, so a winner only keeps the tempo when the
	# flicker lost. The floor is therefore >= 1, not a 50/50 expectation; the
	# split itself is printed for the balance watch, and whether it reads as
	# unfairness to a human is the playtest question in
	# docs/handoff-2026-09-14.md §5.
	var both_sides_won: bool = red_wins >= 1 and blue_wins >= 1
	if passed and not both_sides_won:
		print("rounds_gate_test: BALANCE FAIL — one side never won (red=%d blue=%d) — "
			+ "win rule or spawn geometry regression" % [red_wins, blue_wins])
		passed = false
		detail = "balance floor: both sides must win >= 1 round"
	print("rounds_gate_test: %s — %s (rounds=%d red=%d blue=%d, shots=%d, %.1fs)" % [
		"PASS" if passed else "FAIL", detail, _rounds_resolved, red_wins, blue_wins,
		_shots_fired, _elapsed_seconds()])
	quit(0 if passed else 1)


func _elapsed_seconds() -> float:
	return float(_physics_frames) / 60.0