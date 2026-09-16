extends SceneTree
class_name SeriesRecordTest
## Durable series record — the one outcome that outlives a round.
##
## Covers the ranked item A1 from docs/design/feature-priorities.md: a match win
## is recorded in user://settings.cfg (two new keys) and surfaced on the
## match-over gate. The loop's re-entry leg currently belongs entirely to the
## second human (docs/design/core-loop.md finding 1); this is the substrate any
## later comparison layer needs.
##
## Covers the whole vertical slice against the REAL scene:
##   1. series_round_trip            — defaults are 0-0, values survive save/reload,
##                                     and a corrupt file does not poison them
##   2. fresh_profile_starts_at_zero — a store loaded by Main starts at 0-0
##   3. match_win_recorded           — with best-of-1, one decided round ends the
##                                     match, bumps exactly one counter, persists
##                                     it, and the gate names the series
##   4. series_accumulates           — the rematch tap clears the MATCH score but
##                                     NOT the series; a second decided match
##                                     makes it 2
##
## HARNESS RULE (learned the hard way): in Godot a runtime error inside a case
## (e.g. reading a property that does not exist) ABORTS that case without
## running its _fail() calls — the suite then prints ALL PASS with exit 0 while
## proving nothing. So every case must take a verdict: either it reports a
## failure or it reaches _leave(). _finish() hard-fails if any case took none,
## and all feature reads go through Object.get() / _series() (never int(<null>)).
##
## The test snapshots and RESTORES user://settings.cfg (same reason as
## settings_test.gd: every other suite boots main.tscn, which loads that file).
##
## Run (cwd = game/):
##   DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --headless --path . \
##     --script res://tests/series_record_test.gd

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
	# Case 1 needs a genuinely fresh store, so clear the file first.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_PATH))

	await _case_series_round_trip()

	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_finish(false, "series_record_test: could not load res://scenes/main.tscn")
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)

	_case_fresh_profile_starts_at_zero()
	await _case_match_win_recorded()
	await _case_series_accumulates()

	_finish(_failures.is_empty(), _summary())


func _summary() -> String:
	if _failures.is_empty():
		return "series_record_test: ALL PASS (%d cases)" % _cases_run
	return "series_record_test: %d of %d cases FAILED (%d assertions) — %s" % [
		_failed_cases.size(), _cases_run, _failures.size(), "; ".join(_failures)]


# ------------------------------------------------------- 1. store round trip

func _case_series_round_trip() -> void:
	_enter("series_round_trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_PATH))
	var fresh := SettingsStore.new()
	fresh.load_from_disk()

	var first: Array = _series(fresh)
	if first.is_empty():
		return
	if first[0] != 0 or first[1] != 0:
		_fail("first run starts at %d-%d, expected 0-0" % [first[0], first[1]])

	fresh.set("matches_won_red", 2)
	fresh.set("matches_won_blue", 1)
	fresh.save_to_disk()

	var reloaded := SettingsStore.new()
	reloaded.load_from_disk()
	var again: Array = _series(reloaded)
	if again.is_empty():
		return
	if again[0] != 2 or again[1] != 1:
		_fail("reload gave %d-%d, expected 2-1" % [again[0], again[1]])

	# A corrupt file must not crash the load or invent a record.
	var f := FileAccess.open(CFG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("not a config file\n" + char(0) + char(255))
		f.close()
	var after_corrupt := SettingsStore.new()
	after_corrupt.load_from_disk()
	var corrupt: Array = _series(after_corrupt)
	if corrupt.is_empty():
		return
	if corrupt[0] != 0 or corrupt[1] != 0:
		_fail("corrupt file produced a record %d-%d" % [corrupt[0], corrupt[1]])
	_leave()


# --------------------------------------------------------- 2. fresh profile

func _case_fresh_profile_starts_at_zero() -> void:
	_enter("fresh_profile_starts_at_zero")
	var store: SettingsStore = _main.get("settings_store")
	if store == null:
		_fail("Main has no settings_store")
		return
	var series: Array = _series(store)
	if series.is_empty():
		return
	if series[0] != 0 or series[1] != 0:
		_fail("Main loaded a non-zero series %d-%d" % [series[0], series[1]])
	_leave()


# --------------------------------------------------- 3. a match win is recorded

func _case_match_win_recorded() -> void:
	_enter("match_win_recorded")
	var store: SettingsStore = _main.get("settings_store")
	if store == null:
		_fail("Main has no settings_store")
		return
	store.match_length = 1                      # first win decides the match
	_main.call("_apply_settings")

	var winner: String = await _decide_one_round()
	if winner == "":
		return
	var series: Array = _series(store)
	if series.is_empty():
		return
	var red: int = series[0]
	var blue: int = series[1]
	if red + blue != 1:
		_fail("series is %d-%d after one match, expected a single win" % [red, blue])
	if (red == 1 and winner != "red") or (blue == 1 and winner != "blue"):
		_fail("winner %s was recorded as %d-%d" % [winner, red, blue])

	var gate_text: String = str(_main.get("turn_gate").get("_label").text)
	if not gate_text.contains("series"):
		_fail("match-over gate does not name the series: %s" % gate_text)

	# It must be on disk, not just in memory (a kill must not lose the record).
	var reloaded := SettingsStore.new()
	reloaded.load_from_disk()
	var persisted: Array = _series(reloaded)
	if persisted.is_empty():
		return
	if persisted[0] + persisted[1] != 1:
		_fail("disk has %d-%d after one match" % [persisted[0], persisted[1]])
	_leave()


# ------------------------------------------------- 4. the series outlives the match

func _case_series_accumulates() -> void:
	_enter("series_accumulates")
	var store: SettingsStore = _main.get("settings_store")
	if store == null:
		_fail("Main has no settings_store")
		return
	var start: Array = _series(store)
	if start.is_empty():
		return
	var before: int = start[0] + start[1]

	# The rematch tap must clear the MATCH score and leave the series alone.
	_main.call("_on_gate_tapped")
	await _settle(6)
	var wins: Dictionary = _main.get("_round_wins")
	if int(wins.get("red", 0)) + int(wins.get("blue", 0)) != 0:
		_fail("the rematch tap did not reset the match score")
	var mid_series: Array = _series(store)
	if mid_series.is_empty():
		return
	var mid: int = mid_series[0] + mid_series[1]
	if mid != before:
		_fail("the rematch tap changed the series (%d -> %d)" % [before, mid])

	var winner: String = await _decide_one_round()
	if winner == "":
		return
	var end_series: Array = _series(store)
	if end_series.is_empty():
		return
	var after: int = end_series[0] + end_series[1]
	if after != before + 1:
		_fail("series is %d after two matches, expected %d" % [after, before + 1])
	var gate_text: String = str(_main.get("turn_gate").get("_label").text)
	if not gate_text.contains("series"):
		_fail("second match-over gate lost the series line: %s" % gate_text)
	_leave()


# ------------------------------------------------------------------- helpers

## Series counters as [red, blue], or [] with a failure recorded when the store
## has no series keys. int(<null>) is an engine error that would abort a case
## silently, so every series read goes through here.
func _series(store: SettingsStore) -> Array:
	var red: Variant = store.get("matches_won_red")
	var blue: Variant = store.get("matches_won_blue")
	if red == null or blue == null:
		_fail("SettingsStore has no series keys (matches_won_red/matches_won_blue)")
		return []
	return [int(red), int(blue)]


## Fire the project's own edge shot (the shape the 20-round gate uses) and wait
## for the round to resolve. Returns the winning player id, or "" on failure.
func _decide_one_round() -> String:
	var st: Dictionary = _state()
	if str(st.get("phase", "")) != "AIM":
		_fail("expected AIM to fire the deciding shot, phase=%s" % st.get("phase"))
		return ""
	var player: String = str(st.get("current_player", ""))
	var pen := _pen_for(player)
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


func _settle(frames: int) -> void:
	for i in range(frames):
		await physics_frame


# ------------------------------------------------------- case-verdict harness

func _enter(case_name: String) -> void:
	_current_case = case_name
	_cases_run += 1
	_verdict_taken = false


## Every case that reaches its end calls this: the case ran and was judged.
func _leave() -> void:
	if not _verdict_taken:
		_verdict_taken = true
		_verdicts += 1


## A case that reports a failure takes its verdict here, so an early return
## after _fail() is not mistaken for a silent abort.
func _fail(why: String) -> void:
	if not _verdict_taken:
		_verdict_taken = true
		_verdicts += 1
	_failed_cases[_current_case] = true
	_failures.append("%s: %s" % [_current_case, why])
	push_error("series_record_test FAIL %s — %s" % [_current_case, why])


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
