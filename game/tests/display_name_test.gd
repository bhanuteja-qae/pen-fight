extends SceneTree
class_name DisplayNameTest
## A2 from docs/design/feature-priorities.md: the gate and the verdict must name
## the pen that is actually on the table.
##
## Before this, _display_name() hardcoded red -> "Amber" / blue -> "Cobalt" while
## four designs are selectable, so the one piece of feedback that carries the
## turn owner, the score and the winner could name a pen that is not in the
## scene (docs/design/core-loop.md finding 4). The name now follows the chosen
## design.
##
## Covers, against the REAL scene:
##   1. default_names          — red/blue resolve to Amber/Cobalt out of the box
##   2. every_skin_is_named    — all four designs carry a distinct, non-empty name
##   3. name_follows_the_skin  — set_pen_skin("blue", "ivory") renames that slot
##   4. unknown_slot_falls_back— an unrecognised id is capitalised, never empty
##   5. gate_names_the_skin    — a decided match names the WINNER's design, not
##                               the default art, in the match-over prompt
##   6. sheet_label_follows    — the settings sheet's "X's pen" rows follow too
##
## HARNESS RULE: a Godot runtime error inside a case aborts it silently and the
## suite can still print ALL PASS, so every case takes a verdict (_fail or
## _leave) and _finish() hard-fails if any case took none.
##
## Run (cwd = game/):
##   DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --headless --path . \
##     --script res://tests/display_name_test.gd

const CFG_PATH := "user://settings.cfg"
const RESOLVE_TIMEOUT_SEC := 12.0

var _main: Node = null
var _auto: AutoFlick = null
var _failures: Array[String] = []
var _cases_run: int = 0
var _verdicts: int = 0
var _verdict_taken: bool = false
var _failed_cases: Dictionary = {}
var _current_case: String = ""
var _cfg_backup: PackedByteArray = PackedByteArray()
var _cfg_existed: bool = false


func _init() -> void:
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	_backup_settings_file()
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_finish(false, "display_name_test: could not load res://scenes/main.tscn")
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)

	_case_default_names()
	_case_every_skin_is_named()
	_case_name_follows_the_skin()
	_case_unknown_slot_falls_back()
	_case_sheet_label_follows()
	await _case_gate_names_the_skin()

	_finish(_failures.is_empty(), _summary())


func _summary() -> String:
	if _failures.is_empty():
		return "display_name_test: ALL PASS (%d cases)" % _cases_run
	return "display_name_test: %d of %d cases FAILED (%d assertions) — %s" % [
		_failed_cases.size(), _cases_run, _failures.size(), "; ".join(_failures)]


# ------------------------------------------------------------------- 1-2. names

func _case_default_names() -> void:
	_enter("default_names")
	if _name("red") != "Amber":
		_fail("red resolves to %s, expected Amber" % _name("red"))
	if _name("blue") != "Cobalt":
		_fail("blue resolves to %s, expected Cobalt" % _name("blue"))
	_leave()


func _case_every_skin_is_named() -> void:
	_enter("every_skin_is_named")
	var skins: Dictionary = _skins()
	if skins.is_empty():
		_fail("Main exposes no PEN_SKINS constant")
		return
	if skins.size() != 4:
		_fail("%d designs, expected 4" % skins.size())
	var seen: Dictionary = {}
	for key: String in skins.keys():
		var entry: Dictionary = skins[key]
		var label: String = str(entry.get("name", ""))
		if label == "":
			_fail("design '%s' has no display name" % key)
			continue
		if seen.has(label):
			_fail("design '%s' reuses the name '%s'" % [key, label])
		seen[label] = true
		if label.to_lower() == "red" or label.to_lower() == "blue":
			_fail("design '%s' is named %s — the CVD-safe naming rule forbids slot colours" % [key, label])
	_leave()


# ------------------------------------------------------- 3-4. skin-driven naming

func _case_name_follows_the_skin() -> void:
	_enter("name_follows_the_skin")
	if not bool(_main.call("set_pen_skin", "blue", "ivory")):
		_fail("set_pen_skin('blue','ivory') returned false")
		return
	if _name("blue") != "Ivory":
		_fail("after choosing ivory, blue resolves to %s" % _name("blue"))
	if _name("red") != "Amber":
		_fail("red changed to %s — the other slot must not move" % _name("red"))

	# ...and the same through the store path Main actually uses at startup.
	var store: SettingsStore = _main.get("settings_store")
	if store == null:
		_fail("Main has no settings_store")
		return
	store.set_pen("blue", "graphite")
	_main.call("_apply_settings")
	if _name("blue") != "Graphite":
		_fail("after the store applied graphite, blue resolves to %s" % _name("blue"))
	store.set_pen("blue", "ivory")
	_main.call("_apply_settings")
	if _name("blue") != "Ivory":
		_fail("restoring ivory gave %s" % _name("blue"))
	_leave()


func _case_unknown_slot_falls_back() -> void:
	_enter("unknown_slot_falls_back")
	if _name("green") != "Green":
		_fail("an unknown slot resolved to '%s', expected a capitalised id" % _name("green"))
	# An empty id cannot reach the display path (Main only names a non-empty
	# current player), but it must fall through, not invent a name.
	if _name("") != "":
		_fail("an empty id invented the name '%s'" % _name(""))
	_leave()


# ------------------------------------------------------------ 5. the two surfaces

func _case_sheet_label_follows() -> void:
	_enter("sheet_label_follows")
	var screen: SettingsScreen = _main.get("settings_screen")
	if screen == null:
		_fail("Main has no settings_screen")
		return
	var labels: Array = screen.get("_labels")
	if labels == null or labels.size() <= SettingsScreen.Row.PEN_BLUE:
		_fail("the sheet exposes no PEN_BLUE label")
		return
	var blue_label: Label = labels[SettingsScreen.Row.PEN_BLUE]
	if not blue_label.text.contains("Ivory"):
		_fail("PEN_BLUE row reads '%s' while that slot plays ivory" % blue_label.text)
	_leave()


## The winner is whoever did NOT flick, so give the non-flicker a distinctive
## design and check the match-over prompt names it.
func _case_gate_names_the_skin() -> void:
	_enter("gate_names_the_skin")
	var store: SettingsStore = _main.get("settings_store")
	if store == null:
		_fail("Main has no settings_store")
		return
	var st: Dictionary = _state()
	if str(st.get("phase", "")) != "AIM":
		_fail("expected AIM to fire the deciding shot, phase=%s" % st.get("phase"))
		return
	var flicker: String = str(st.get("current_player", ""))
	var winner: String = "blue" if flicker == "red" else "red"

	store.match_length = 1                      # first win decides the match
	store.set_pen(winner, "ivory")
	store.set_pen(flicker, "amber")
	_main.call("_apply_settings")
	if _name(winner) != "Ivory":
		_fail("could not put ivory on the %s slot (it resolves to %s)" % [winner, _name(winner)])

	if await _flick_current_away(flicker) == "":
		return
	var decided: String = str(_state().get("winner", ""))
	if decided != winner:
		_fail("expected %s to win, state says %s" % [winner, decided])
	var gate_text: String = str(_main.get("turn_gate").get("_label").text)
	if not gate_text.contains("Ivory"):
		_fail("match-over gate names '%s' but ivory is on the table" % gate_text)
	if gate_text.contains("Cobalt"):
		_fail("gate still names the default art: %s" % gate_text)
	_leave()


# ------------------------------------------------------------------- helpers

func _skins() -> Dictionary:
	var script: GDScript = _main.get_script()
	if script == null:
		return {}
	return script.get_script_constant_map().get("PEN_SKINS", {})


func _name(pen_id: String) -> String:
	return str(_main.call("_display_name", pen_id))


func _state() -> Dictionary:
	var ts: Variant = _main.get("turn_state")
	return ts.state() if ts != null else {}


func _pen_for(player: String) -> PenBody:
	match player:
		"red":
			return _main.get("pen_red")
		"blue":
			return _main.get("pen_blue")
		_:
			return null


## Fire the project's own edge shot for `player` (radially away from the table
## centre) so that pen leaves and the round resolves. Returns the winner, or "".
func _flick_current_away(player: String) -> String:
	var pen: PenBody = _pen_for(player)
	if pen == null:
		_fail("no pen for %s" % player)
		return ""
	if _auto == null:
		_auto = AutoFlick.new()
		root.add_child(_auto)
		_auto.enabled = true
		_auto.auto_flick_requested.connect(_main.get("_submit_shot"))
	var away: Vector2 = pen.global_position
	if away.length_squared() < 1.0:
		away = Vector2.RIGHT
	_auto.schedule_flick(player, away.normalized() * 1.0, 0.35)

	var elapsed := 0.0
	while elapsed < RESOLVE_TIMEOUT_SEC:
		await physics_frame
		elapsed += 1.0 / float(Engine.physics_ticks_per_second)
		if str(_state().get("phase", "")) == "ROUND_OVER":
			break
	if str(_state().get("phase", "")) != "ROUND_OVER":
		_fail("the round never resolved within %.0fs" % RESOLVE_TIMEOUT_SEC)
		return ""
	await _settle(4)
	return str(_state().get("winner", ""))


func _settle(frames: int) -> void:
	for i in range(frames):
		await physics_frame


# ------------------------------------------------------- case-verdict harness

func _enter(case_name: String) -> void:
	_current_case = case_name
	_cases_run += 1
	_verdict_taken = false


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
	push_error("display_name_test FAIL %s — %s" % [_current_case, why])


func _backup_settings_file() -> void:
	_cfg_existed = FileAccess.file_exists(CFG_PATH)
	if not _cfg_existed:
		return
	var f := FileAccess.open(CFG_PATH, FileAccess.READ)
	if f != null:
		_cfg_backup = f.get_buffer(f.get_length())
		f.close()


func _restore_settings_file() -> void:
	if _cfg_existed:
		var f := FileAccess.open(CFG_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_cfg_backup)
			f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_PATH))


func _finish(ok: bool, msg: String) -> void:
	var silent: int = _cases_run - _verdicts
	if silent > 0:
		ok = false
		msg += "  [HARNESS] %d case(s) aborted without a verdict (last: %s) — a Godot runtime error in a case does NOT fail the suite by itself" % [silent, _current_case]
	if _auto != null:
		_auto.queue_free()
	_restore_settings_file()
	print(msg)
	quit(0 if ok else 1)
