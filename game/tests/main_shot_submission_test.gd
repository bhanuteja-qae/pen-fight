extends SceneTree
class_name MainShotSubmissionTest
## Contract tests for Main's single ShotCommand submission seam, the human
## adapter, every rejection no-op, duplicate submission, and human-vs-harness
## producer parity.
##
## Run from the repository root:
##   /home/ubuntu/godot/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path game --script res://tests/main_shot_submission_test.gd

const MAIN_SCENE := "res://scenes/main.tscn"

var _main: Main = null
var _failures: Array[String] = []
var _flick_events: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		_fail("accepted_commit", "could not load %s" % MAIN_SCENE)
		_finish()
		return
	_main = packed.instantiate() as Main
	root.add_child(_main)
	_case_accepted_command_commits_once()
	_case_rejections_are_hard_noops(packed)
	_case_producer_parity(packed)
	_case_settings_change_does_not_mutate_config(packed)
	_finish()


func _case_accepted_command_commits_once() -> void:
	if not _main.has_method("_submit_shot"):
		_fail("accepted_commit", "Main does not expose the canonical _submit_shot boundary")
		return
	if _main.get("active_match_config") == null:
		_fail("accepted_commit", "Main did not build an active MatchConfig at session start")
		return
	var pen: PenBody = _main.get_node("PenRed") as PenBody
	pen.flicked.connect(_on_pen_flicked)
	var command := ShotCommand.create("red", Vector2.RIGHT, 0.25, 0.5, "human")
	var accepted: bool = _main._submit_shot(command)
	_check(accepted, "accepted_commit", "valid active-player command was rejected")
	var state: Dictionary = _main.turn_state.state()
	_check(str(state.get("phase", "")) == TurnState.PHASE_IN_FLIGHT,
		"accepted_commit", "accepted command did not advance TurnState")
	_check((state.get("last_impulse", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(0.25, 0.0)),
		"accepted_commit", "TurnState did not record direction * normalized power")
	_check(_flick_events.size() == 1, "accepted_commit", "PenBody did not receive exactly one flick")
	if _flick_events.size() == 1:
		_check((_flick_events[0].get("impulse", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(400.0, 0.0)),
			"accepted_commit", "PenBody did not own the single MAX_IMPULSE scaling")


func _case_rejections_are_hard_noops(packed: PackedScene) -> void:
	# Session/config preconditions.
	_new_main(packed)
	var command := _command()
	_main.active_match_config = null
	_assert_rejected_noop("missing active config", command)

	_new_main(packed)
	_assert_rejected_noop("missing command", null)

	# Complete command validation is repeated at the boundary. The value object is
	# immutable by public API, but corrupt/private construction must not bypass the
	# session seam.
	_new_main(packed)
	command = _command()
	command._slot = "green"
	_assert_rejected_noop("unknown slot", command)

	_new_main(packed)
	command = _command()
	command._source = "replay"
	_assert_rejected_noop("unknown source", command)

	_new_main(packed)
	command = _command()
	command._direction = Vector2(1.002, 0.0)
	_assert_rejected_noop("non-unit direction", command)

	_new_main(packed)
	command = _command()
	command._direction = Vector2(NAN, 0.0)
	_assert_rejected_noop("non-finite direction", command)

	_new_main(packed)
	command = _command()
	command._power = 1.01
	_assert_rejected_noop("power above range", command)

	_new_main(packed)
	command = _command()
	command._contact_offset = -1.01
	_assert_rejected_noop("contact below range", command)

	# Turn ownership and every intake lock reject before either downstream write.
	_new_main(packed)
	_assert_rejected_noop("wrong active slot",
		ShotCommand.create("blue", Vector2.LEFT, 0.5, 0.0, "human"))

	_new_main(packed)
	_main._input_locked = true
	_assert_rejected_noop("input lock", _command())

	_new_main(packed)
	_main._gate_showing = true
	_assert_rejected_noop("handoff gate", _command())

	_new_main(packed)
	_main.settings_screen.open()
	_assert_rejected_noop("blocking settings modal", _command())

	_new_main(packed)
	_main._match_over = true
	_assert_rejected_noop("ended match", _command())

	_new_main(packed)
	_main.pen_red.pen_id = "missing"
	_assert_rejected_noop("missing active pen", _command())

	# The first commit closes AIM synchronously; an identical duplicate must lose
	# that race and leave both state and physics exactly where the first left them.
	_new_main(packed)
	command = _command()
	_check(_main._submit_shot(command), "duplicate submission", "first command was rejected")
	_assert_rejected_noop("duplicate submission", command)


## Producer parity (contract acceptance): the human adapter and the AutoFlick
## harness must commit identical state and physics for the same slot,
## direction, power and contact values.
func _case_producer_parity(packed: PackedScene) -> void:
	var human: Dictionary = _record_commit(packed, true)
	var harness: Dictionary = _record_commit(packed, false)
	if human.is_empty() or harness.is_empty():
		_fail("producer_parity", "a producer did not commit (human=%s harness=%s)" % [human, harness])
		return
	if not (human["last_impulse"] as Vector2).is_equal_approx(harness["last_impulse"] as Vector2):
		_fail("producer_parity", "last_impulse differs: human=%s harness=%s" % [human["last_impulse"], harness["last_impulse"]])
	if not (human["flick_impulse"] as Vector2).is_equal_approx(harness["flick_impulse"] as Vector2):
		_fail("producer_parity", "apply_flick impulse differs: human=%s harness=%s" % [human["flick_impulse"], harness["flick_impulse"]])


## Contract acceptance: changing settings after match start must not mutate
## the active config (the snapshot is frozen for the life of the match).
func _case_settings_change_does_not_mutate_config(packed: PackedScene) -> void:
	_new_main(packed)
	var config: MatchConfig = _main.active_match_config
	if config == null:
		_fail("settings_freeze", "no active config at session start")
		return
	var before_seed: int = config.seed()
	var before_best_of: int = config.best_of()
	var before_red: String = config.participant_for_slot("red").display_name()
	_main.settings_store.match_length = 7
	_main.settings_store.set_pen("red", "ivory")
	_main.call("_apply_settings")
	var after: MatchConfig = _main.active_match_config
	if after != config:
		_fail("settings_freeze", "a settings change replaced the active config")
		return
	if after.best_of() != before_best_of or after.seed() != before_seed:
		_fail("settings_freeze", "config fields changed: best_of %d->%d seed %d->%d" % [
			before_best_of, after.best_of(), before_seed, after.seed()])
	if after.participant_for_slot("red").display_name() != before_red:
		_fail("settings_freeze", "participant display_name changed: %s -> %s" % [
			before_red, after.participant_for_slot("red").display_name()])


## Commit Vector2.RIGHT / 0.5 / 0.25 through the chosen producer on a fresh
## Main; returns {last_impulse, flick_impulse} or {} when nothing committed.
func _record_commit(packed: PackedScene, human: bool) -> Dictionary:
	_new_main(packed)
	_main.pen_red.flicked.connect(_on_pen_flicked)
	var before: int = _flick_events.size()
	if human:
		_main._on_flick_ready(Vector2.RIGHT, 0.5, 0.25)
	else:
		var harness := AutoFlick.new()
		root.add_child(harness)
		harness.enabled = true
		harness.auto_flick_requested.connect(_main.get("_submit_shot"))
		harness.fire_now("red", Vector2.RIGHT * 0.5, 0.25)
		harness.queue_free()
	if _flick_events.size() <= before:
		return {}
	var state: Dictionary = _main.turn_state.state()
	return {
		"last_impulse": state.get("last_impulse", Vector2.ZERO),
		"flick_impulse": _flick_events[_flick_events.size() - 1].get("impulse", Vector2.ZERO),
	}


func _new_main(packed: PackedScene) -> void:
	if _main != null:
		_main.free()
	_main = packed.instantiate() as Main
	root.add_child(_main)


func _command() -> ShotCommand:
	return ShotCommand.create("red", Vector2.RIGHT, 0.5, 0.25, "human")


func _assert_rejected_noop(label: String, command: ShotCommand) -> void:
	var before_state: Dictionary = _main.turn_state.state()
	var before_red: Vector2 = _main.pen_red.get("_pending_impulse") as Vector2
	var before_blue: Vector2 = _main.pen_blue.get("_pending_impulse") as Vector2
	var accepted: bool = _main._submit_shot(command)
	_check(not accepted, label, "submission returned true")
	_check(_main.turn_state.state() == before_state, label, "rejection mutated TurnState")
	_check((_main.pen_red.get("_pending_impulse") as Vector2) == before_red,
		label, "rejection mutated the red pen")
	_check((_main.pen_blue.get("_pending_impulse") as Vector2) == before_blue,
		label, "rejection mutated the blue pen")


func _on_pen_flicked(pen_id: String, impulse: Vector2) -> void:
	_flick_events.append({"pen_id": pen_id, "impulse": impulse})


func _check(condition: bool, case_name: String, why: String) -> void:
	if not condition:
		_fail(case_name, why)


func _fail(case_name: String, why: String) -> void:
	_failures.append("%s: %s" % [case_name, why])
	push_error("main_shot_submission_test FAIL %s — %s" % [case_name, why])


func _finish() -> void:
	if _failures.is_empty():
		print("main_shot_submission_test: ALL PASS")
		quit(0)
		return
	print("main_shot_submission_test: %d failure(s) — %s" % [
		_failures.size(), "; ".join(_failures)])
	quit(1)
