extends SceneTree
class_name MatchContractTest
## Plain-data contract tests for Participant, MatchConfig, and ShotCommand.
##
## Every case must enter and then take a verdict. Godot can abort a case on a
## runtime error without failing the process, so _finish() rejects any entered
## case that did not reach _leave() or _fail().
##
## Run from the repository root:
##   /home/ubuntu/godot/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path game --script res://tests/match_contract_test.gd

const PARTICIPANT_PATH := "res://scripts/participant.gd"
const MATCH_CONFIG_PATH := "res://scripts/match_config.gd"
const SHOT_COMMAND_PATH := "res://scripts/shot_command.gd"

var _failures: Array[String] = []
var _cases_entered: int = 0
var _verdicts: int = 0
var _verdict_taken: bool = false
var _current_case: String = ""
var _failed_cases: Dictionary = {}


func _init() -> void:
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	_case_participant_factory()
	_case_match_config_factory()
	_case_shot_command_factory()
	_finish()


func _case_participant_factory() -> void:
	_enter("participant_factory")
	var participant_script: GDScript = load(PARTICIPANT_PATH)
	if participant_script == null:
		_fail("could not load %s" % PARTICIPANT_PATH)
		return

	var local: Variant = participant_script.create(
		"red", "local_player", "Alice", "human", "amber", "spin", "")
	if local == null:
		_fail("valid local human participant was rejected")
		return
	_check(local.slot() == "red", "slot accessor preserves red")
	_check(local.kind() == "local_player", "kind accessor preserves local_player")
	_check(local.display_name() == "Alice", "display_name accessor preserves the name")
	_check(local.controller() == "human", "controller accessor preserves human")
	_check(local.pen_model() == "amber", "pen_model accessor preserves amber")
	_check(local.pen_profile() == "spin", "pen_profile accessor preserves the effective profile")
	_check(local.bot_profile() == "", "human participant has an empty bot profile")
	_check(not _has_public_contract_field(local), "contract fields are not writable public properties")

	var rival: Variant = participant_script.create(
		"blue", "rival", "Edge Rival", "bot", "ivory", "glide", "edge")
	_check(rival != null, "valid rival bot participant is accepted")
	if rival != null:
		_check(rival.bot_profile() == "edge", "bot profile accessor preserves edge")

	var rejected: Array = [
		participant_script.create("green", "local_player", "Alice", "human", "amber", "spin", ""),
		participant_script.create("red", "guest", "Alice", "human", "amber", "spin", ""),
		participant_script.create("red", "local_player", "", "human", "amber", "spin", ""),
		participant_script.create("red", "local_player", "   ", "human", "amber", "spin", ""),
		participant_script.create("red", "local_player", "Alice", "remote", "amber", "spin", ""),
		participant_script.create("red", "local_player", "Alice", "human", "plastic", "spin", ""),
		participant_script.create("red", "local_player", "Alice", "human", "amber", "power", ""),
		participant_script.create("red", "rival", "Rival", "human", "amber", "spin", ""),
		participant_script.create("red", "local_player", "Alice", "bot", "amber", "spin", "hitter"),
		participant_script.create("red", "local_player", "Alice", "human", "amber", "spin", "hitter"),
		participant_script.create("red", "rival", "Rival", "bot", "amber", "spin", ""),
		participant_script.create("red", "rival", "Rival", "bot", "amber", "spin", "camper"),
	]
	for i in range(rejected.size()):
		_check(rejected[i] == null, "invalid participant matrix row %d is rejected" % i)
	_leave()


func _case_match_config_factory() -> void:
	_enter("match_config_factory")
	var participant_script: GDScript = load(PARTICIPANT_PATH)
	var config_script: GDScript = load(MATCH_CONFIG_PATH)
	if participant_script == null or config_script == null:
		_fail("could not load MatchConfig dependencies")
		return

	# Classic resolves both effective profiles to control, regardless of the
	# valid-but-wrong effective profiles supplied by the caller.
	var red: Variant = participant_script.create(
		"red", "local_player", "Alice", "human", "amber", "anchor", "")
	var blue: Variant = participant_script.create(
		"blue", "local_player", "Bob", "human", "graphite", "glide", "")
	var source: Array = [red, blue]
	var classic: Variant = config_script.create("hot_seat", "classic", 5, 987654, source)
	if classic == null:
		_fail("valid hot-seat Classic config was rejected")
		return
	_check(classic.mode() == "hot_seat", "mode accessor preserves hot_seat")
	_check(classic.ruleset() == "classic", "ruleset accessor preserves classic")
	_check(classic.best_of() == 5, "best_of accessor preserves 5")
	_check(classic.rounds_to_win() == 3, "best of 5 requires 3 round wins")
	_check(classic.seed() == 987654, "explicit nonzero seed is preserved")
	_check(classic.participant_for_slot("red").display_name() == "Alice",
		"participant lookup resolves red")
	_check(classic.participant_for_slot("blue").display_name() == "Bob",
		"participant lookup resolves blue")
	_check(classic.participant_for_slot("green") == null,
		"participant lookup rejects an unknown slot")
	_check(classic.participant_for_slot("red").pen_profile() == "control",
		"Classic forces amber to effective control")
	_check(classic.participant_for_slot("blue").pen_profile() == "control",
		"Classic forces graphite to effective control")
	_check(not _has_named_public_field(classic,
		["mode", "ruleset", "best_of", "seed", "participants"]),
		"MatchConfig fields are not writable public properties")

	# Both ingress and egress arrays are copies. Mutating either must not alter
	# the canonical red/blue list held by MatchConfig.
	source.clear()
	_check(classic.participants().size() == 2,
		"clearing the caller array does not alter MatchConfig")
	var exposed: Array = classic.participants()
	exposed.reverse()
	exposed.pop_back()
	var stable: Array = classic.participants()
	_check(stable.size() == 2, "mutating an accessor result does not alter MatchConfig")
	_check(stable[0].slot() == "red" and stable[1].slot() == "blue",
		"participants stay in canonical red/blue order")
	_check(stable[0] != red and stable[1] != blue,
		"MatchConfig owns resolved participant copies")
	stable[0]._pen_profile = "glide"
	_check(classic.participant_for_slot("red").pen_profile() == "control",
		"mutating a returned Participant cannot alter MatchConfig")
	var looked_up: Variant = classic.participant_for_slot("blue")
	looked_up._slot = "red"
	_check(classic.participant_for_slot("blue") != null,
		"mutating a lookup result cannot alter MatchConfig")

	# Pen Powers maps each model to its effective profile and does not trust the
	# profile supplied on the Participant.
	var powers_ab: Variant = config_script.create("hot_seat", "pen_powers", 1, 11, [
		participant_script.create("red", "local_player", "A", "human", "amber", "control", ""),
		participant_script.create("blue", "local_player", "B", "human", "cobalt", "glide", ""),
	])
	var powers_gi: Variant = config_script.create("hot_seat", "pen_powers", 7, 12, [
		participant_script.create("red", "local_player", "G", "human", "graphite", "spin", ""),
		participant_script.create("blue", "local_player", "I", "human", "ivory", "anchor", ""),
	])
	_check(powers_ab != null and powers_gi != null, "valid Pen Powers configs are accepted")
	if powers_ab != null and powers_gi != null:
		_check(powers_ab.participant_for_slot("red").pen_profile() == "spin",
			"amber maps to spin")
		_check(powers_ab.participant_for_slot("blue").pen_profile() == "control",
			"cobalt maps to control")
		_check(powers_gi.participant_for_slot("red").pen_profile() == "anchor",
			"graphite maps to anchor")
		_check(powers_gi.participant_for_slot("blue").pen_profile() == "glide",
			"ivory maps to glide")

	var solo: Variant = config_script.create("solo", "classic", 3, 44, [
		participant_script.create("red", "local_player", "Alice", "human", "amber", "spin", ""),
		participant_script.create("blue", "rival", "Hitter", "bot", "cobalt", "control", "hitter"),
	])
	_check(solo != null, "one local human plus one rival bot is a valid solo config")

	var zero_seed: Variant = config_script.create("hot_seat", "classic", 3, 0, [red, blue])
	_check(zero_seed != null, "zero seed is accepted and resolved")
	if zero_seed != null:
		var resolved: int = zero_seed.seed()
		_check(resolved != 0, "zero seed resolves to a nonzero seed")
		_check(zero_seed.seed() == resolved, "resolved seed is stable after construction")

	var rejected: Array = [
		config_script.create("network", "classic", 3, 1, [red, blue]),
		config_script.create("hot_seat", "chaos", 3, 1, [red, blue]),
		config_script.create("hot_seat", "classic", 2, 1, [red, blue]),
		config_script.create("hot_seat", "classic", 3, 1, [red]),
		config_script.create("hot_seat", "classic", 3, 1, [blue, red]),
		config_script.create("hot_seat", "classic", 3, 1, [red, red]),
		config_script.create("hot_seat", "classic", 3, 1, [
			red,
			participant_script.create("blue", "rival", "Bot", "bot", "cobalt", "control", "spin"),
		]),
		config_script.create("solo", "classic", 3, 1, [red, blue]),
		config_script.create("solo", "classic", 3, 1, [
			participant_script.create("red", "rival", "One", "bot", "amber", "spin", "hitter"),
			participant_script.create("blue", "rival", "Two", "bot", "cobalt", "control", "edge"),
		]),
	]
	for i in range(rejected.size()):
		_check(rejected[i] == null, "invalid MatchConfig matrix row %d is rejected" % i)
	_leave()


func _case_shot_command_factory() -> void:
	_enter("shot_command_factory")
	var shot_script: GDScript = load(SHOT_COMMAND_PATH)
	if shot_script == null:
		_fail("could not load %s" % SHOT_COMMAND_PATH)
		return

	var shot: Variant = shot_script.create("red", Vector2(3.0, 4.0), 0.75, -0.25, "human")
	if shot == null:
		_fail("valid ShotCommand was rejected")
		return
	_check(shot.slot() == "red", "shot slot accessor preserves red")
	_check(shot.direction().is_equal_approx(Vector2(0.6, 0.8)),
		"shot direction is normalized at build time")
	_check(is_equal_approx(shot.direction().length(), 1.0),
		"shot direction has unit length")
	_check(is_equal_approx(shot.power(), 0.75), "shot power accessor preserves 0.75")
	_check(is_equal_approx(shot.contact_offset(), -0.25),
		"shot contact offset accessor preserves -0.25")
	_check(shot.source() == "human", "shot source accessor preserves human")
	_check(not _has_named_public_field(shot,
		["slot", "direction", "power", "contact_offset", "source"]),
		"ShotCommand fields are not writable public properties")

	# Inclusive boundaries and every supported producer source are legal.
	_check(shot_script.create("blue", Vector2.LEFT, 0.0, -1.0, "bot") != null,
		"power 0 and contact -1 are accepted for a bot")
	_check(shot_script.create("red", Vector2.UP, 1.0, 1.0, "harness") != null,
		"power 1 and contact 1 are accepted for a harness")

	# Every finite nonzero vector is legal, including values whose naive squared
	# length would overflow or underflow a float.
	var huge: Variant = shot_script.create(
		"red", Vector2(1.0e30, -1.0e30), 0.5, 0.0, "harness")
	var tiny: Variant = shot_script.create(
		"blue", Vector2(1.0e-30, 0.0), 0.5, 0.0, "bot")
	_check(huge != null, "large finite direction is accepted")
	_check(tiny != null, "small finite nonzero direction is accepted")
	if huge != null and tiny != null:
		_check(is_equal_approx(huge.direction().length(), 1.0),
			"large finite direction normalizes to unit length")
		_check(is_equal_approx(tiny.direction().length(), 1.0),
			"small finite direction normalizes to unit length")

	var rejected: Array = [
		shot_script.create("green", Vector2.RIGHT, 0.5, 0.0, "human"),
		shot_script.create("red", Vector2.ZERO, 0.5, 0.0, "human"),
		shot_script.create("red", Vector2(NAN, 1.0), 0.5, 0.0, "human"),
		shot_script.create("red", Vector2(1.0, INF), 0.5, 0.0, "human"),
		shot_script.create("red", Vector2.RIGHT, NAN, 0.0, "human"),
		shot_script.create("red", Vector2.RIGHT, INF, 0.0, "human"),
		shot_script.create("red", Vector2.RIGHT, -0.001, 0.0, "human"),
		shot_script.create("red", Vector2.RIGHT, 1.001, 0.0, "human"),
		shot_script.create("red", Vector2.RIGHT, 0.5, NAN, "human"),
		shot_script.create("red", Vector2.RIGHT, 0.5, -INF, "human"),
		shot_script.create("red", Vector2.RIGHT, 0.5, -1.001, "human"),
		shot_script.create("red", Vector2.RIGHT, 0.5, 1.001, "human"),
		shot_script.create("red", Vector2.RIGHT, 0.5, 0.0, "replay"),
	]
	for i in range(rejected.size()):
		_check(rejected[i] == null, "invalid ShotCommand matrix row %d is rejected" % i)
	_leave()


func _has_public_contract_field(value: Object) -> bool:
	return _has_named_public_field(value,
		["slot", "kind", "display_name", "controller", "pen_model", "pen_profile", "bot_profile"])


func _has_named_public_field(value: Object, forbidden: Array) -> bool:
	for property: Dictionary in value.get_property_list():
		if forbidden.has(str(property.get("name", ""))):
			return true
	return false


func _enter(case_name: String) -> void:
	_current_case = case_name
	_cases_entered += 1
	_verdict_taken = false


func _check(condition: bool, why: String) -> void:
	if not condition:
		_fail(why)


func _leave() -> void:
	if not _verdict_taken:
		_verdict_taken = true
		_verdicts += 1


func _fail(why: String) -> void:
	if not _verdict_taken:
		_verdict_taken = true
		_verdicts += 1
	_failed_cases[_current_case] = true
	_failures.append("%s: %s" % [_current_case, why])
	push_error("match_contract_test FAIL %s — %s" % [_current_case, why])


func _finish() -> void:
	var silent: int = _cases_entered - _verdicts
	if silent > 0:
		_failures.append("HARNESS: %d case(s) aborted without a verdict (last: %s)" % [silent, _current_case])
	if _failures.is_empty():
		print("match_contract_test: ALL PASS")
		quit(0)
		return
	print("match_contract_test: %d of %d cases FAILED (%d assertions) — %s" % [
		_failed_cases.size(), _cases_entered, _failures.size(), "; ".join(_failures)])
	quit(1)
