class_name Participant
extends RefCounted
## Immutable plain-data description of one Match competitor.
##
## Build through create(). Contract data is held in private fields and exposed
## only through accessors so callers cannot rewrite a participant after a match
## has started.

const SLOTS: Array[String] = ["red", "blue"]
const KINDS: Array[String] = ["local_player", "rival"]
const CONTROLLERS: Array[String] = ["human", "bot"]
const PEN_PROFILES: Array[String] = ["control", "spin", "anchor", "glide"]

var _slot: String
var _kind: String
var _display_name: String
var _controller: String
var _pen_model: String
var _pen_profile: String
var _bot_profile: String


func _init(slot_value: String, kind_value: String, display_name_value: String,
		controller_value: String, pen_model_value: String, pen_profile_value: String,
		bot_profile_value: String) -> void:
	_slot = slot_value
	_kind = kind_value
	_display_name = display_name_value
	_controller = controller_value
	_pen_model = pen_model_value
	_pen_profile = pen_profile_value
	_bot_profile = bot_profile_value


## Returns null when any field or V1 kind/controller composition is invalid.
static func create(slot_value: String, kind_value: String, display_name_value: String,
		controller_value: String, pen_model_value: String, pen_profile_value: String,
		bot_profile_value: String = "") -> Participant:
	if not SLOTS.has(slot_value):
		return null
	if not KINDS.has(kind_value):
		return null
	if display_name_value.strip_edges().is_empty():
		return null
	if not CONTROLLERS.has(controller_value):
		return null
	# Model and bot-profile values are opaque registry IDs. This contract owns
	# their shape; the composition roots for pen art and issue #10 own which IDs
	# are registered. Freezing either registry here would couple match data to a
	# particular content revision.
	if not _is_registry_id(pen_model_value):
		return null
	if not PEN_PROFILES.has(pen_profile_value):
		return null

	# V1 has exactly two compositions: a Local Player is human and a Rival is a bot.
	if kind_value == "local_player" and controller_value != "human":
		return null
	if kind_value == "rival" and controller_value != "bot":
		return null
	if controller_value == "human" and not bot_profile_value.is_empty():
		return null
	if controller_value == "bot" and not _is_registry_id(bot_profile_value):
		return null

	return Participant.new(slot_value, kind_value, display_name_value,
		controller_value, pen_model_value, pen_profile_value, bot_profile_value)


static func _is_registry_id(value: String) -> bool:
	return value == value.to_lower() and value.is_valid_identifier()


func slot() -> String:
	return _slot


func kind() -> String:
	return _kind


func display_name() -> String:
	return _display_name


func controller() -> String:
	return _controller


func pen_model() -> String:
	return _pen_model


func pen_profile() -> String:
	return _pen_profile


func bot_profile() -> String:
	return _bot_profile
