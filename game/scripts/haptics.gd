extends RefCounted
class_name Haptics
## Haptic feedback wrapper.
##
## Android/iOS expose Input.vibrate_handheld(ms); every other platform (including
## the headless QA box) silently no-ops it. This wrapper exists so the "Haptics"
## setting has exactly one place to gate, and so tests can assert WHETHER a pulse
## would have fired without needing a device.
##
## Strength mapping mirrors the feel layer's language: a soft nudge is short, a
## hard flick is longer, a knockout is a double pulse.

const FLICK_MAX_MS := 28
const FLICK_MIN_MS := 12
const IMPACT_MS := 18
const KNOCKOUT_MS := 60

var enabled: bool = true
## Number of pulses that actually reached the platform (test/telemetry hook).
var pulses_sent: int = 0


func set_enabled(on: bool) -> void:
	enabled = on


## True when a pulse of this length would reach the platform.
func would_fire() -> bool:
	return enabled and not OS.has_feature("server") and OS.has_feature("mobile")


func _send(ms: int) -> bool:
	if not enabled:
		return false
	pulses_sent += 1
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
	return true


## Flick feedback: length scales with the flick's power (0..1).
func flick(power: float) -> void:
	var t: float = clampf(power, 0.0, 1.0)
	_send(int(round(lerpf(FLICK_MIN_MS, FLICK_MAX_MS, t))))


## A pen-on-pen hit.
func impact() -> void:
	_send(IMPACT_MS)


## Round decided: a double pulse so it is distinguishable by touch alone.
func knockout() -> void:
	if _send(KNOCKOUT_MS):
		_send(KNOCKOUT_MS)
