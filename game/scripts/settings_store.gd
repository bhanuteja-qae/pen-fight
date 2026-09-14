extends RefCounted
class_name SettingsStore
## Persisted player settings, backed by user://settings.cfg.
##
## The store is deliberately dumb: it holds values, round-trips them through a
## ConfigFile, and knows nothing about Main, the audio buses or the sprites.
## Main applies the values (skins, mute, shake flag) — see
## Main._apply_settings()/_on_setting_changed(). That split is what lets the
## settings screen be tested headlessly without a scene.
##
## Persistence matters here: "My pen" is a preference, not a per-session choice,
## and the mockup (assets/design/mockups/settings.html) presents these as
## durable settings. Writes are immediate on change (a settings screen has no
## OK/apply button in the design).

const PATH := "user://settings.cfg"
const SECTION := "settings"

## Match lengths offered in the UI, in rounds ("best of N"). The match is won by
## the first player to reach rounds_to_win(), i.e. ceil(N / 2): best of 5 -> 3.
const MATCH_LENGTHS: Array[int] = [1, 3, 5, 7]

var sound_on: bool = true
var haptics_on: bool = true
var screen_shake_on: bool = true
var match_length: int = 5
var pen_red: String = "amber"
var pen_blue: String = "cobalt"


## Rounds needed to win the match.
func rounds_to_win() -> int:
	return int(ceil(float(match_length) / 2.0))


func match_length_label() -> String:
	return "best of %d" % match_length


## Next match length in the cycle (1 -> 3 -> 5 -> 7 -> 1).
func next_match_length() -> int:
	var i: int = MATCH_LENGTHS.find(match_length)
	if i < 0:
		return MATCH_LENGTHS[2]
	return MATCH_LENGTHS[(i + 1) % MATCH_LENGTHS.size()]


func pen_for(player: String) -> String:
	return str(pen_blue if player == "blue" else pen_red)


func set_pen(player: String, design: String) -> void:
	if player == "blue":
		pen_blue = design
	else:
		pen_red = design


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return  # first run: defaults stand
	sound_on = bool(cfg.get_value(SECTION, "sound_on", sound_on))
	haptics_on = bool(cfg.get_value(SECTION, "haptics_on", haptics_on))
	screen_shake_on = bool(cfg.get_value(SECTION, "screen_shake_on", screen_shake_on))
	match_length = int(cfg.get_value(SECTION, "match_length", match_length))
	if not MATCH_LENGTHS.has(match_length):
		match_length = 5
	pen_red = str(cfg.get_value(SECTION, "pen_red", pen_red))
	pen_blue = str(cfg.get_value(SECTION, "pen_blue", pen_blue))


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "sound_on", sound_on)
	cfg.set_value(SECTION, "haptics_on", haptics_on)
	cfg.set_value(SECTION, "screen_shake_on", screen_shake_on)
	cfg.set_value(SECTION, "match_length", match_length)
	cfg.set_value(SECTION, "pen_red", pen_red)
	cfg.set_value(SECTION, "pen_blue", pen_blue)
	cfg.save(PATH)
