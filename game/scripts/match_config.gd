class_name MatchConfig
extends RefCounted
## Immutable, validated plain-data configuration built once at match start.

const MODES: Array[String] = ["hot_seat", "solo"]
const RULESETS: Array[String] = ["classic", "pen_powers"]
const BEST_OF_VALUES: Array[int] = [1, 3, 5, 7]
const PEN_POWER_PROFILES: Dictionary = {
	"amber": "spin",
	"cobalt": "control",
	"graphite": "anchor",
	"ivory": "glide",
}

var _mode: String
var _ruleset: String
var _best_of: int
var _seed: int
var _participants: Array[Participant]


func _init(mode_value: String, ruleset_value: String, best_of_value: int,
		seed_value: int, participants_value: Array[Participant]) -> void:
	_mode = mode_value
	_ruleset = ruleset_value
	_best_of = best_of_value
	_seed = seed_value
	_participants = participants_value.duplicate()


## Returns null unless the complete match composition is valid. Participant
## effective profiles are rebuilt here from the ruleset and pen model; a caller's
## supplied Participant.pen_profile is deliberately ignored.
static func create(mode_value: String, ruleset_value: String, best_of_value: int,
		seed_value: int, participants_value: Array) -> MatchConfig:
	if not MODES.has(mode_value):
		return null
	if not RULESETS.has(ruleset_value):
		return null
	if not BEST_OF_VALUES.has(best_of_value):
		return null
	if participants_value.size() != 2:
		return null
	if not participants_value[0] is Participant or not participants_value[1] is Participant:
		return null

	var red: Participant = participants_value[0]
	var blue: Participant = participants_value[1]
	if red.slot() != "red" or blue.slot() != "blue":
		return null
	if not _composition_is_valid(mode_value, red, blue):
		return null

	var resolved: Array[Participant] = []
	for participant: Participant in [red, blue]:
		var profile: String = _profile_for(ruleset_value, participant.pen_model())
		var copy: Participant = Participant.create(
			participant.slot(), participant.kind(), participant.display_name(),
			participant.controller(), participant.pen_model(), profile,
			participant.bot_profile())
		if copy == null:
			return null
		resolved.append(copy)

	var resolved_seed: int = seed_value
	if resolved_seed == 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		resolved_seed = rng.randi_range(1, 2147483647)
		print("MatchConfig: resolved seed 0 to %d" % resolved_seed)

	return MatchConfig.new(mode_value, ruleset_value, best_of_value,
		resolved_seed, resolved)


static func _composition_is_valid(mode_value: String, red: Participant,
		blue: Participant) -> bool:
	var local_humans: int = 0
	var rival_bots: int = 0
	for participant: Participant in [red, blue]:
		if participant.kind() == "local_player" and participant.controller() == "human":
			local_humans += 1
		elif participant.kind() == "rival" and participant.controller() == "bot":
			rival_bots += 1
		else:
			return false
	if mode_value == "hot_seat":
		return local_humans == 2 and rival_bots == 0
	return local_humans == 1 and rival_bots == 1


static func _profile_for(ruleset_value: String, pen_model_value: String) -> String:
	if ruleset_value == "classic":
		return "control"
	return str(PEN_POWER_PROFILES.get(pen_model_value, ""))


func mode() -> String:
	return _mode


func ruleset() -> String:
	return _ruleset


func best_of() -> int:
	return _best_of


func seed() -> int:
	return _seed


## A new array and new immutable-value objects are returned on every call.
func participants() -> Array[Participant]:
	var copies: Array[Participant] = []
	for participant: Participant in _participants:
		copies.append(_copy_participant(participant))
	return copies


func participant_for_slot(slot_value: String) -> Participant:
	for participant: Participant in _participants:
		if participant.slot() == slot_value:
			return _copy_participant(participant)
	return null


func _copy_participant(participant: Participant) -> Participant:
	return Participant.create(
		participant.slot(), participant.kind(), participant.display_name(),
		participant.controller(), participant.pen_model(), participant.pen_profile(),
		participant.bot_profile())


func rounds_to_win() -> int:
	return int(ceil(float(_best_of) / 2.0))
