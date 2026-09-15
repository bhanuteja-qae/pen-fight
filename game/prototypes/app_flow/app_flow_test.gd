extends SceneTree
class_name AppFlowTest
## Deterministic headless unit tests for AppFlow (Wave 1, wayfinder ticket #5;
## docs/prototypes/CONTRACTS-app-flow.md). Pure logic, no scene deps. Covers:
## the full transition table, both pinned invariants (gameplay_start_requested
## fires only on entry to PLAYING, and a negative check that it never escapes
## from any menu-state walk), Back from every screen (including a double-Back
## toggle), the leave-confirm cancel path, and a source-scan guard that the
## module never instantiates a scene or node.
##
## Run headless (project root is game/):
##   godot --headless --path game --script res://prototypes/app_flow/app_flow_test.gd
## (exit code 0 = pass, 1 = fail)
##
## Entry convention matches game/tests/turn_state_test.gd: `extends SceneTree`
## + `_init()` calling quit(code) is Godot's documented standalone-script
## pattern. Test values are intentionally untyped (Variant) where they touch
## the preloaded GDScript, matching the same reasoning turn_state_test.gd
## documents (typed calls through a preloaded script fail static analysis).

const AppFlowScript := preload("res://prototypes/app_flow/app_flow.gd")

# -- entry points --------------------------------------------------------------

## Programmatic entry point: returns true if all tests pass.
static func run_tests() -> bool:
	var failures: Array[String] = []
	_test_initial_screen_is_boot(failures)
	_test_boot_complete_enters_home(failures)
	_test_boot_complete_is_idempotent(failures)
	_test_boot_back_not_consumed(failures)
	_test_home_back_not_consumed(failures)
	_test_home_opens_mode_pens_settings(failures)
	_test_back_returns_menus_to_home(failures)
	_test_open_menus_guarded_outside_home(failures)
	_test_open_settings_guarded_from_playing(failures)
	_test_start_match_enters_playing_and_emits_signal(failures)
	_test_start_match_guarded_outside_mode(failures)
	_test_playing_back_goes_to_confirm_leave_not_home(failures)
	_test_confirm_leave_back_cancels_to_playing(failures)
	_test_cancel_leave_resumes_without_signal(failures)
	_test_confirm_leave_ends_match_emits_stop(failures)
	_test_end_match_from_playing_emits_stop(failures)
	_test_double_back_toggle_between_playing_and_confirm_leave(failures)
	_test_no_start_signal_escapes_menu_walk(failures)
	_test_no_stop_signal_outside_end_and_confirm(failures)
	_test_no_scene_or_node_instantiation_in_source(failures)
	if failures.is_empty():
		print("app_flow_test: ALL PASS")
		return true
	print("app_flow_test: %d FAILURE(S)" % failures.size())
	for failure in failures:
		print("  FAIL: " + failure)
	return false

## Entry when run via `--script`. Uses the documented SceneTree pattern.
func _init() -> void:
	var ok := run_tests()
	quit(0 if ok else 1)

# -- harness --------------------------------------------------------------------

static func _check(failures: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)

## Fresh AppFlow instance, no scene dependencies.
static func _new_flow() -> Variant:
	return AppFlowScript.new()

## Wires a recorder dictionary of every signal this module can emit. Dictionary
## (not typed vars) so the lambdas below capture and mutate the same instance.
static func _recorder(flow: Variant) -> Dictionary:
	var rec := {"changed": [], "start": [], "stop": []}
	flow.screen_changed.connect(func(from, to): rec["changed"].append([from, to]))
	flow.gameplay_start_requested.connect(func(mode): rec["start"].append(mode))
	flow.gameplay_stop_requested.connect(func(): rec["stop"].append(true))
	return rec

## Drives a fresh, already-booted (HOME) flow with its recorder.
static func _flow_at_home() -> Array:
	var flow = _new_flow()
	var rec := _recorder(flow)
	flow.boot_complete()
	rec["changed"].clear()  # isolate boot's own transition from the caller's assertions
	return [flow, rec]

# -- tests: boot -----------------------------------------------------------------

static func _test_initial_screen_is_boot(failures: Array[String]) -> void:
	var flow = _new_flow()
	_check(failures, flow.screen == AppFlowScript.Screen.BOOT, "AppFlow starts at BOOT")


static func _test_boot_complete_enters_home(failures: Array[String]) -> void:
	var flow = _new_flow()
	var rec := _recorder(flow)
	flow.boot_complete()
	_check(failures, flow.screen == AppFlowScript.Screen.HOME, "boot_complete moves BOOT -> HOME")
	_check(failures, rec["changed"].size() == 1, "boot_complete emits exactly one screen_changed")
	if rec["changed"].size() == 1:
		var edge: Array = rec["changed"][0]
		_check(failures, edge[0] == AppFlowScript.Screen.BOOT and edge[1] == AppFlowScript.Screen.HOME,
			"boot_complete's screen_changed carries (BOOT, HOME)")


static func _test_boot_complete_is_idempotent(failures: Array[String]) -> void:
	var flow = _new_flow()
	flow.boot_complete()
	var rec := _recorder(flow)
	flow.boot_complete()
	_check(failures, flow.screen == AppFlowScript.Screen.HOME, "a second boot_complete stays at HOME")
	_check(failures, rec["changed"].is_empty(), "a second boot_complete emits no screen_changed")


static func _test_boot_back_not_consumed(failures: Array[String]) -> void:
	var flow = _new_flow()
	var rec := _recorder(flow)
	var consumed: bool = flow.handle_back()
	_check(failures, consumed == false, "handle_back() from BOOT is not consumed")
	_check(failures, flow.screen == AppFlowScript.Screen.BOOT, "handle_back() from BOOT does not move the screen")
	_check(failures, rec["changed"].is_empty(), "handle_back() from BOOT emits no screen_changed")

# -- tests: home + the three menu screens -----------------------------------------

static func _test_home_back_not_consumed(failures: Array[String]) -> void:
	var pair := _flow_at_home()
	var flow = pair[0]
	var rec: Dictionary = pair[1]
	var consumed: bool = flow.handle_back()
	_check(failures, consumed == false, "handle_back() from HOME is not consumed (host quits)")
	_check(failures, flow.screen == AppFlowScript.Screen.HOME, "handle_back() from HOME stays at HOME")
	_check(failures, rec["changed"].is_empty(), "handle_back() from HOME emits no screen_changed")


static func _test_home_opens_mode_pens_settings(failures: Array[String]) -> void:
	var openers := [
		["open_mode_select", AppFlowScript.Screen.MODE],
		["open_pens", AppFlowScript.Screen.PENS],
		["open_settings", AppFlowScript.Screen.SETTINGS],
	]
	for entry in openers:
		var pair := _flow_at_home()
		var flow = pair[0]
		var rec: Dictionary = pair[1]
		flow.call(entry[0])
		_check(failures, flow.screen == entry[1], "%s moves HOME -> %s" % [entry[0], entry[1]])
		_check(failures, rec["changed"].size() == 1, "%s emits exactly one screen_changed" % entry[0])


static func _test_back_returns_menus_to_home(failures: Array[String]) -> void:
	var openers := ["open_mode_select", "open_pens", "open_settings"]
	for opener in openers:
		var pair := _flow_at_home()
		var flow = pair[0]
		flow.call(opener)
		var rec: Dictionary = pair[1]
		rec["changed"].clear()
		var consumed: bool = flow.handle_back()
		_check(failures, consumed == true, "handle_back() after %s is consumed" % opener)
		_check(failures, flow.screen == AppFlowScript.Screen.HOME,
			"handle_back() after %s returns to HOME" % opener)
		_check(failures, rec["changed"].size() == 1,
			"handle_back() after %s emits exactly one screen_changed" % opener)


## The three "open a menu" entries are only meaningful from HOME (they are
## HOME's children, not a tab bar between siblings) — calling them from
## anywhere else must be a strict no-op: no screen change, no signal.
static func _test_open_menus_guarded_outside_home(failures: Array[String]) -> void:
	var openers := ["open_mode_select", "open_pens", "open_settings"]
	var other_screens := ["open_mode_select", "open_pens", "open_settings"]
	for setup in other_screens:
		for opener in openers:
			var pair := _flow_at_home()
			var flow = pair[0]
			flow.call(setup)
			var before: Variant = flow.screen
			var rec: Dictionary = pair[1]
			rec["changed"].clear()
			flow.call(opener)
			_check(failures, flow.screen == before,
				"%s from %s is a no-op" % [opener, AppFlowScript.Screen.keys()[before]])
			_check(failures, rec["changed"].is_empty(),
				"%s from %s emits no screen_changed" % [opener, AppFlowScript.Screen.keys()[before]])


## Explicit ticket callout: "Settings entry from PLAYING is not allowed
## (suspend semantics live with the host)."
static func _test_open_settings_guarded_from_playing(failures: Array[String]) -> void:
	var pair := _flow_at_home()
	var flow = pair[0]
	flow.open_mode_select()
	flow.start_match("hot_seat")
	var rec: Dictionary = pair[1]
	rec["changed"].clear()
	rec["start"].clear()
	flow.open_settings()
	_check(failures, flow.screen == AppFlowScript.Screen.PLAYING, "open_settings from PLAYING is a no-op")
	_check(failures, rec["changed"].is_empty(), "open_settings from PLAYING emits no screen_changed")
	_check(failures, rec["start"].is_empty(), "open_settings from PLAYING emits no gameplay_start_requested")

# -- tests: match start/stop -------------------------------------------------------

static func _test_start_match_enters_playing_and_emits_signal(failures: Array[String]) -> void:
	var pair := _flow_at_home()
	var flow = pair[0]
	var rec: Dictionary = pair[1]
	flow.open_mode_select()
	rec["changed"].clear()
	flow.start_match("solo")
	_check(failures, flow.screen == AppFlowScript.Screen.PLAYING, "start_match moves MODE -> PLAYING")
	_check(failures, rec["changed"].size() == 1, "start_match emits exactly one screen_changed")
	_check(failures, rec["start"] == ["solo"], "start_match emits gameplay_start_requested with its mode")
	_check(failures, rec["stop"].is_empty(), "start_match emits no gameplay_stop_requested")


static func _test_start_match_guarded_outside_mode(failures: Array[String]) -> void:
	var setups := ["", "open_pens", "open_settings"]
	for setup in setups:
		var pair := _flow_at_home()
		var flow = pair[0]
		if setup != "":
			flow.call(setup)
		var before: Variant = flow.screen
		var rec: Dictionary = pair[1]
		rec["changed"].clear()
		flow.start_match("hot_seat")
		_check(failures, flow.screen == before,
			"start_match from %s is a no-op" % AppFlowScript.Screen.keys()[before])
		_check(failures, rec["start"].is_empty(),
			"start_match from %s emits no gameplay_start_requested" % AppFlowScript.Screen.keys()[before])


static func _test_end_match_from_playing_emits_stop(failures: Array[String]) -> void:
	var pair := _flow_at_home()
	var flow = pair[0]
	flow.open_mode_select()
	flow.start_match("hot_seat")
	var rec: Dictionary = pair[1]
	rec["changed"].clear()
	rec["stop"].clear()
	flow.end_match()
	_check(failures, flow.screen == AppFlowScript.Screen.HOME, "end_match moves PLAYING -> HOME")
	_check(failures, rec["changed"].size() == 1, "end_match emits exactly one screen_changed")
	_check(failures, rec["stop"].size() == 1, "end_match emits gameplay_stop_requested exactly once")

# -- tests: leave-confirm flow ------------------------------------------------------

static func _test_playing_back_goes_to_confirm_leave_not_home(failures: Array[String]) -> void:
	var pair := _flow_at_home()
	var flow = pair[0]
	flow.open_mode_select()
	flow.start_match("hot_seat")
	var rec: Dictionary = pair[1]
	rec["changed"].clear()
	rec["stop"].clear()
	var consumed: bool = flow.handle_back()
	_check(failures, consumed == true, "handle_back() from PLAYING is consumed")
	_check(failures, flow.screen == AppFlowScript.Screen.CONFIRM_LEAVE,
		"handle_back() from PLAYING lands on CONFIRM_LEAVE, never straight out")
	_check(failures, rec["stop"].is_empty(),
		"handle_back() from PLAYING does not tear down the match before confirmation")


static func _test_confirm_leave_back_cancels_to_playing(failures: Array[String]) -> void:
	var pair := _flow_at_home()
	var flow = pair[0]
	flow.open_mode_select()
	flow.start_match("hot_seat")
	flow.handle_back()  # PLAYING -> CONFIRM_LEAVE
	var rec: Dictionary = pair[1]
	rec["changed"].clear()
	var consumed: bool = flow.handle_back()
	_check(failures, consumed == true, "handle_back() from CONFIRM_LEAVE is consumed")
	_check(failures, flow.screen == AppFlowScript.Screen.PLAYING,
		"handle_back() from CONFIRM_LEAVE cancels back to PLAYING")
	_check(failures, rec["stop"].is_empty(), "handle_back() from CONFIRM_LEAVE emits no gameplay_stop_requested")


static func _test_cancel_leave_resumes_without_signal(failures: Array[String]) -> void:
	var pair := _flow_at_home()
	var flow = pair[0]
	flow.open_mode_select()
	flow.start_match("hot_seat")
	flow.handle_back()  # PLAYING -> CONFIRM_LEAVE
	var rec: Dictionary = pair[1]
	rec["changed"].clear()
	rec["start"].clear()  # orchestrator fix: this step asserts on start/stop; clear them too
	rec["stop"].clear()
	flow.cancel_leave()
	_check(failures, flow.screen == AppFlowScript.Screen.PLAYING, "cancel_leave moves CONFIRM_LEAVE -> PLAYING")
	_check(failures, rec["changed"].size() == 1, "cancel_leave emits exactly one screen_changed")
	_check(failures, rec["stop"].is_empty(), "cancel_leave emits no gameplay_stop_requested (nothing torn down)")
	_check(failures, rec["start"].is_empty(), "cancel_leave emits no gameplay_start_requested")


static func _test_confirm_leave_ends_match_emits_stop(failures: Array[String]) -> void:
	var pair := _flow_at_home()
	var flow = pair[0]
	flow.open_mode_select()
	flow.start_match("hot_seat")
	flow.handle_back()  # PLAYING -> CONFIRM_LEAVE
	var rec: Dictionary = pair[1]
	rec["changed"].clear()
	rec["stop"].clear()
	flow.confirm_leave()
	_check(failures, flow.screen == AppFlowScript.Screen.HOME, "confirm_leave moves CONFIRM_LEAVE -> HOME")
	_check(failures, rec["changed"].size() == 1, "confirm_leave emits exactly one screen_changed")
	_check(failures, rec["stop"].size() == 1, "confirm_leave emits gameplay_stop_requested exactly once")


static func _test_double_back_toggle_between_playing_and_confirm_leave(failures: Array[String]) -> void:
	var pair := _flow_at_home()
	var flow = pair[0]
	flow.open_mode_select()
	flow.start_match("hot_seat")
	_check(failures, flow.handle_back() == true, "1st back from PLAYING consumed")
	_check(failures, flow.screen == AppFlowScript.Screen.CONFIRM_LEAVE, "1st back lands on CONFIRM_LEAVE")
	_check(failures, flow.handle_back() == true, "2nd back (from CONFIRM_LEAVE) consumed")
	_check(failures, flow.screen == AppFlowScript.Screen.PLAYING, "2nd back cancels to PLAYING")
	_check(failures, flow.handle_back() == true, "3rd back (from PLAYING again) consumed")
	_check(failures, flow.screen == AppFlowScript.Screen.CONFIRM_LEAVE, "3rd back lands on CONFIRM_LEAVE again")

# -- tests: negative invariants -----------------------------------------------------

## Walks every non-start_match method from every screen it could plausibly be
## called from and asserts gameplay_start_requested never fires outside the
## single intentional start_match() call.
static func _test_no_start_signal_escapes_menu_walk(failures: Array[String]) -> void:
	var flow = _new_flow()
	var rec := _recorder(flow)
	flow.boot_complete()
	flow.open_mode_select()
	flow.open_pens()  # guarded no-op from MODE
	flow.handle_back()  # MODE -> HOME
	flow.open_pens()
	flow.handle_back()  # PENS -> HOME
	flow.open_settings()
	flow.handle_back()  # SETTINGS -> HOME
	flow.open_mode_select()
	flow.start_match("hot_seat")  # the one intentional start
	flow.handle_back()  # PLAYING -> CONFIRM_LEAVE
	flow.cancel_leave()  # CONFIRM_LEAVE -> PLAYING
	flow.handle_back()  # PLAYING -> CONFIRM_LEAVE
	flow.confirm_leave()  # CONFIRM_LEAVE -> HOME
	flow.handle_back()  # HOME, not consumed
	_check(failures, rec["start"] == ["hot_seat"],
		"gameplay_start_requested fires exactly once, only for the real start_match call")


## Walks the same lifecycle and asserts gameplay_stop_requested fires only at
## end_match / confirm_leave, never at the PLAYING -> CONFIRM_LEAVE Back edge
## or at cancel_leave.
static func _test_no_stop_signal_outside_end_and_confirm(failures: Array[String]) -> void:
	var flow = _new_flow()
	var rec := _recorder(flow)
	flow.boot_complete()
	flow.open_mode_select()
	flow.start_match("solo")
	flow.handle_back()  # PLAYING -> CONFIRM_LEAVE: no stop yet
	flow.cancel_leave()  # CONFIRM_LEAVE -> PLAYING: no stop
	flow.end_match()  # PLAYING -> HOME: stop #1
	flow.open_mode_select()
	flow.start_match("solo")
	flow.handle_back()  # PLAYING -> CONFIRM_LEAVE: no stop
	flow.confirm_leave()  # CONFIRM_LEAVE -> HOME: stop #2
	_check(failures, rec["stop"].size() == 2,
		"gameplay_stop_requested fires exactly twice: once per end_match/confirm_leave, never on the Back edge into CONFIRM_LEAVE or on cancel_leave")

# -- tests: source-scan guard -------------------------------------------------------

## ADR-0001 / contract invariant: "nothing in this module instantiates
## scenes/nodes." Mirrors the technique in
## game/prototypes/policy_bot/policy_bot_test.gd, which source-scans for a
## forbidden API set to make a non-simulation boundary observable.
static func _test_no_scene_or_node_instantiation_in_source(failures: Array[String]) -> void:
	var source := FileAccess.get_file_as_string("res://prototypes/app_flow/app_flow.gd")
	_check(failures, source.length() > 0, "app_flow.gd source is readable for the scan")
	var forbidden := [".instantiate(", "PackedScene", "add_child(", "Node.new(", "Node2D.new(", "load(\"res://scenes"]
	for token in forbidden:
		_check(failures, source.find(token) == -1, "app_flow.gd source has no scene/node instantiation API: %s" % token)
