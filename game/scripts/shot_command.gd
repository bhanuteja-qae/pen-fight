class_name ShotCommand
extends RefCounted
## Immutable, validated intent submitted by human, bot, or test harness.

const SLOTS: Array[String] = ["red", "blue"]
const SOURCES: Array[String] = ["human", "bot", "harness"]

var _slot: String
var _direction: Vector2
var _power: float
var _contact_offset: float
var _source: String


func _init(slot_value: String, direction_value: Vector2, power_value: float,
		contact_offset_value: float, source_value: String) -> void:
	_slot = slot_value
	_direction = direction_value
	_power = power_value
	_contact_offset = contact_offset_value
	_source = source_value


## Returns null for invalid input. Values outside the legal power/contact ranges
## are rejected, never clamped, so producers cannot silently submit another shot.
static func create(slot_value: String, direction_value: Vector2, power_value: float,
		contact_offset_value: float, source_value: String) -> ShotCommand:
	if not SLOTS.has(slot_value):
		return null
	if not is_finite(direction_value.x) or not is_finite(direction_value.y):
		return null
	if direction_value == Vector2.ZERO:
		return null
	if not is_finite(power_value) or power_value < 0.0 or power_value > 1.0:
		return null
	if (not is_finite(contact_offset_value)
			or contact_offset_value < -1.0 or contact_offset_value > 1.0):
		return null
	if not SOURCES.has(source_value):
		return null

	# Scale first so length calculation cannot overflow or underflow for any
	# finite nonzero Vector2. At least one scaled component has magnitude 1.
	var scale: float = maxf(absf(direction_value.x), absf(direction_value.y))
	var scaled: Vector2 = direction_value / scale
	var normalized: Vector2 = scaled.normalized()
	if normalized == Vector2.ZERO or not is_finite(normalized.x) or not is_finite(normalized.y):
		return null
	return ShotCommand.new(slot_value, normalized, power_value,
		contact_offset_value, source_value)


func slot() -> String:
	return _slot


func direction() -> Vector2:
	return _direction


func power() -> float:
	return _power


func contact_offset() -> float:
	return _contact_offset


func source() -> String:
	return _source
