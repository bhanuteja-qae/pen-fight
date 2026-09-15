extends SceneTree

const PolicyBotScript = preload("res://prototypes/policy_bot/policy_bot.gd")


class ProbePenBody extends PenBody:
	var apply_count: int = 0
	var last_direction: Vector2 = Vector2.ZERO
	var last_power: float = -1.0
	var last_contact_offset: float = 2.0

	func apply_flick(impulse_dir: Vector2, power: float, contact_offset: float = 0.0) -> void:
		apply_count += 1
		last_direction = impulse_dir
		last_power = power
		last_contact_offset = contact_offset


var _failed: bool = false


func _init() -> void:
	var snapshot := _snapshot()
	_test_fixed_seed_determinism(snapshot)
	_test_single_commit(snapshot)
	_test_no_simulation_guard(snapshot)
	if _failed:
		quit(1)
		return
	print("policy_bot_test: ALL PASS")
	quit(0)


func _snapshot() -> PolicyBotScript.Snapshot:
	var snapshot := PolicyBotScript.Snapshot.new()
	snapshot.pen_pos = Vector2(310.0, 280.0)
	snapshot.pen_rot = 0.15
	snapshot.opp_pos = Vector2(795.0, 390.0)
	snapshot.opp_rot = -0.22
	snapshot.table_rect = Rect2(30.0, 40.0, 1180.0, 640.0)
	snapshot.oob_margin = 13.0
	return snapshot


func _test_fixed_seed_determinism(snapshot: PolicyBotScript.Snapshot) -> void:
	var first_rng := RandomNumberGenerator.new()
	var second_rng := RandomNumberGenerator.new()
	first_rng.seed = 90731
	second_rng.seed = 90731
	var first := PolicyBotScript.choose(snapshot, "spin", first_rng)
	var second := PolicyBotScript.choose(snapshot, "spin", second_rng)
	_assert(is_equal_approx(first.impulse, second.impulse), "same seed chooses the same impulse")
	_assert(is_equal_approx(first.contact_offset, second.contact_offset), "same seed chooses the same contact offset")
	_assert(is_equal_approx(first.spin, second.spin), "same seed chooses the same spin")
	_assert(first.direction.is_equal_approx(second.direction), "same seed chooses the same direction")


func _test_single_commit(snapshot: PolicyBotScript.Snapshot) -> void:
	PolicyBotScript.reset_instrumentation()
	var rng := RandomNumberGenerator.new()
	rng.seed = 44
	var candidate := PolicyBotScript.choose(snapshot, "hitter", rng)
	var probe := ProbePenBody.new()
	PolicyBotScript.commit(candidate, probe)
	_assert(probe.apply_count == 1, "one decision invokes PenBody.apply_flick exactly once")
	_assert(PolicyBotScript.commit_calls() == 1, "policy commit instrumentation records one commit")
	_assert(probe.last_direction.is_equal_approx(candidate.direction), "commit forwards its authored direction")
	_assert(is_equal_approx(probe.last_power, candidate.impulse), "commit forwards the 0..1 power fraction")
	_assert(is_equal_approx(probe.last_contact_offset, candidate.contact_offset), "commit forwards contact offset")
	probe.free()


func _test_no_simulation_guard(snapshot: PolicyBotScript.Snapshot) -> void:
	PolicyBotScript.reset_instrumentation()
	var physics_frames_before := Engine.get_physics_frames()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var options := PolicyBotScript.candidates(snapshot, "edge")
	var chosen := PolicyBotScript.choose(snapshot, "edge", rng)
	_assert(options.size() > 0 and options.size() <= 12, "policy evaluates only a small authored candidate set")
	_assert(chosen.impulse >= 0.0 and chosen.impulse <= 1.0, "candidate power stays in PenBody's fraction range")
	_assert(PolicyBotScript.physics_step_attempts() == 0, "policy instrumentation records zero physics steps")
	_assert(Engine.get_physics_frames() == physics_frames_before, "candidate generation and choice do not advance a physics frame")
	var source := FileAccess.get_file_as_string("res://prototypes/policy_bot/policy_bot.gd")
	for forbidden in ["PhysicsServer", "PhysicsDirectSpaceState", "get_world_2d", "duplicate(", ".step("]:
		_assert(source.find(forbidden) == -1, "policy source has no simulation API: %s" % forbidden)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("policy_bot_test: FAIL — %s" % message)
