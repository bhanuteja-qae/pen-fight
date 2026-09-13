extends SceneTree
class_name TurnStateTest
## Deterministic headless unit tests for TurnState (pure logic, Phase 1b).
## No randomness. Covers: begin_turn advancement, on_flick AIM->IN_FLIGHT,
## on_out_of_bounds winner resolution parking in ROUND_OVER, on_settled
## next-turn advancement, forfeit_tick timeout, continue_to_next_round (winner
## starts), stale/duplicate-event guards, and the table-rect geometric helper.
##
## Run headless (project root is game/):
##   godot --headless --path game --script res://tests/turn_state_test.gd
## (exit code 0 = pass, 1 = fail)
##
## Programmatic entry for the orchestrator:
##   var script = load("res://tests/turn_state_test.gd")
##   script.run_tests()   # -> bool
##
## Entry convention: `extends SceneTree` + `_init()` calling quit(code) is
## Godot's documented standalone-script pattern (docs "Command line tutorial").
## Note: test values are intentionally untyped (Variant) because TurnState is
## reached through a preloaded GDScript — typed method calls would fail static
## analysis ("cannot find member on RefCounted/Object").

const TurnStateScript := preload("res://scripts/turn_state.gd")

# -- entry points --------------------------------------------------------------

## Programmatic entry point: returns true if all tests pass.
static func run_tests() -> bool:
	var failures: Array[String] = []
	_test_begin_turn_advances_player(failures)
	_test_on_flick_transitions_to_in_flight(failures)
	_test_out_of_bounds_declares_other_winner(failures)
	_test_out_of_bounds_for_non_flicked_pen(failures)
	_test_settled_advances_to_next_turn(failures)
	_test_settled_stalemate_forfeits(failures)
	_test_forfeit_timeout(failures)
	_test_forfeit_boundary(failures)
	_test_stale_and_duplicate_events_ignored(failures)
	_test_continue_to_next_round_winner_starts(failures)
	_test_continue_cycles_red_blue(failures)
	_test_continue_requires_round_over(failures)
	_test_table_rect_helper(failures)
	if failures.is_empty():
		print("turn_state_test: ALL PASS")
		return true
	print("turn_state_test: %d FAILURE(S)" % failures.size())
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

## Fresh TurnState instance over plain data (no scene dependencies).
static func _new_ts(pens: Array = ["red", "blue"], timeout: float = 5.0,
		rect: Rect2 = Rect2(0, 0, 100, 80)) -> Variant:
	return TurnStateScript.new(pens, timeout, rect)

# -- tests ------------------------------------------------------------------------

static func _test_begin_turn_advances_player(failures: Array[String]) -> void:
	var ts = _new_ts()
	_check(failures, ts.state()["phase"] == TurnStateScript.PHASE_AIM, "initial phase is AIM")
	_check(failures, ts.state()["current_player"] == "", "no current player before begin_turn")
	ts.begin_turn()
	var s: Dictionary = ts.state()
	_check(failures, s["current_player"] == "red", "begin_turn picks the first pen")
	_check(failures, s["phase"] == TurnStateScript.PHASE_AIM, "phase is AIM after begin_turn")
	# A completed round advances to the next player.
	ts.on_flick(Vector2(1, 0))
	ts.on_pen_moved("red")  # real exchange (otherwise it is a stalemate forfeit)
	ts.on_settled("red")
	_check(failures, ts.state()["current_player"] == "blue", "completed round advances to blue")

static func _test_on_flick_transitions_to_in_flight(failures: Array[String]) -> void:
	var ts = _new_ts()
	ts.begin_turn()
	ts.on_flick(Vector2(5, -3))
	var s: Dictionary = ts.state()
	_check(failures, s["phase"] == TurnStateScript.PHASE_IN_FLIGHT, "on_flick -> IN_FLIGHT")
	_check(failures, s["flicked_pen"] == "red", "flicked pen is the current player")
	_check(failures, s["last_impulse"] == Vector2(5, -3), "impulse is recorded")

static func _test_out_of_bounds_declares_other_winner(failures: Array[String]) -> void:
	var ts = _new_ts()
	ts.begin_turn()
	ts.on_flick(Vector2(1, 0))
	ts.on_out_of_bounds("red")
	var s: Dictionary = ts.state()
	_check(failures, s["phase"] == TurnStateScript.PHASE_ROUND_OVER, "flicked-pen OOB -> ROUND_OVER (gate)")
	_check(failures, s["winner"] == "blue", "other player wins when the flicked pen goes OOB")
	_check(failures, s["round_winner"] == "blue", "round_winner mirrors winner")
	_check(failures, s["loser"] == "red", "flicked pen is the loser")
	_check(failures, s["round_over"] == true, "round flagged over")

static func _test_out_of_bounds_for_non_flicked_pen(failures: Array[String]) -> void:
	var ts = _new_ts()
	ts.begin_turn()
	ts.on_flick(Vector2(1, 0))
	ts.on_out_of_bounds("blue")
	var s: Dictionary = ts.state()
	_check(failures, s["phase"] == TurnStateScript.PHASE_ROUND_OVER, "defensive OOB also parks in ROUND_OVER")
	_check(failures, s["winner"] == "red", "defensive: flicking player wins if the other pen goes OOB")
	_check(failures, s["round_winner"] == "red", "defensive round_winner mirrors winner")

static func _test_settled_advances_to_next_turn(failures: Array[String]) -> void:
	var ts = _new_ts()
	ts.begin_turn()
	ts.on_flick(Vector2(1, 0))
	ts.on_pen_moved("red")   # a real exchange: the flicked pen actually moved
	ts.on_settled("red")
	var s: Dictionary = ts.state()
	_check(failures, s["phase"] == TurnStateScript.PHASE_AIM, "both pens settled -> back to AIM")
	_check(failures, s["current_player"] == "blue", "next player's turn after settle")
	_check(failures, s["winner"] == "", "no winner when both pens stay on the table")

static func _test_settled_stalemate_forfeits(failures: Array[String]) -> void:
	# Stalemate rule (docs/ART_AND_FEEL_SPEC.md §7): a settled turn where NO pen
	# ever exceeded MOVED_LINEAR_VEL is a forfeit — the flicking player loses,
	# not a clean hand-over. This closes the tickle-flick stall (weak-flick every
	# timeout period to avoid the no-input forfeit).
	var ts = _new_ts()
	ts.begin_turn()
	ts.on_flick(Vector2(0.001, 0.0))  # so weak the pen barely moves
	ts.on_settled("red")              # no on_pen_moved — nothing exceeded 25 px/s
	var s: Dictionary = ts.state()
	_check(failures, s["phase"] == TurnStateScript.PHASE_ROUND_OVER, "stalemate parks in ROUND_OVER (gate)")
	_check(failures, s["winner"] == "blue", "other player wins the round on a stalemate")
	_check(failures, s["round_winner"] == "blue", "round_winner mirrors winner on stalemate")
	_check(failures, s["loser"] == "red", "flicking player loses the round on a stalemate")
	_check(failures, s["round_over"] == true, "round flagged over on stalemate")

static func _test_forfeit_timeout(failures: Array[String]) -> void:
	var ts = _new_ts()
	ts.begin_turn()
	ts.forfeit_tick(2.0)
	_check(failures, ts.state()["phase"] == TurnStateScript.PHASE_AIM, "still AIM before timeout")
	ts.forfeit_tick(2.0)
	ts.forfeit_tick(1.0)  # total elapsed == 5.0 -> forfeit
	var s: Dictionary = ts.state()
	_check(failures, s["phase"] == TurnStateScript.PHASE_ROUND_OVER, "timeout parks in ROUND_OVER (gate)")
	_check(failures, s["winner"] == "blue", "other player wins on forfeit")
	_check(failures, s["round_winner"] == "blue", "round_winner mirrors winner on forfeit")
	_check(failures, s["loser"] == "red", "active player loses on forfeit")
	_check(failures, s["round_over"] == true, "round flagged over on forfeit")
	# Once forfeited, further ticks change nothing.
	var winner_before: String = s["winner"]
	ts.forfeit_tick(10.0)
	_check(failures, ts.state()["winner"] == winner_before, "forfeit result is final")

static func _test_forfeit_boundary(failures: Array[String]) -> void:
	var ts = _new_ts()
	ts.begin_turn()
	ts.forfeit_tick(4.999)
	_check(failures, ts.state()["phase"] == TurnStateScript.PHASE_AIM, "just under timeout still AIM")
	ts.forfeit_tick(0.001)
	_check(failures, ts.state()["phase"] == TurnStateScript.PHASE_ROUND_OVER, "reaching the timeout parks in ROUND_OVER")

static func _test_stale_and_duplicate_events_ignored(failures: Array[String]) -> void:
	# A flick outside AIM is ignored.
	var ts = _new_ts()
	ts.begin_turn()
	ts.on_flick(Vector2(1, 0))
	ts.on_flick(Vector2(0, 1))
	_check(failures, ts.state()["last_impulse"] == Vector2(1, 0), "second flick (not in AIM) is ignored")
	# A duplicate OOB after the round is decided is ignored.
	ts.on_out_of_bounds("red")
	var winner_before: String = ts.state()["winner"]
	ts.on_out_of_bounds("blue")
	_check(failures, ts.state()["winner"] == winner_before, "OOB after ROUND_OVER is ignored")
	# on_flick / forfeit_tick are no-ops while the round is over (input locked).
	ts.on_flick(Vector2(0, 1))
	_check(failures, ts.state()["phase"] == TurnStateScript.PHASE_ROUND_OVER, "on_flick ignored while ROUND_OVER")
	ts.forfeit_tick(10.0)
	_check(failures, ts.state()["phase"] == TurnStateScript.PHASE_ROUND_OVER, "forfeit_tick ignored while ROUND_OVER")
	# A stale settle after the round advanced is ignored.
	var ts2 = _new_ts()
	ts2.begin_turn()
	ts2.on_flick(Vector2(1, 0))
	ts2.on_pen_moved("red")  # real exchange so the settle advances the turn
	ts2.on_settled("red")    # advances to blue, phase back to AIM
	ts2.on_settled("red")
	_check(failures, ts2.state()["current_player"] == "blue", "stale settle does not double-advance")

static func _test_continue_to_next_round_winner_starts(failures: Array[String]) -> void:
	var ts = _new_ts()
	ts.begin_turn()                    # round 1: red starts
	ts.on_flick(Vector2(1, 0))
	ts.on_out_of_bounds("red")         # red flicked & lost -> blue wins the round
	_check(failures, ts.state()["phase"] == TurnStateScript.PHASE_ROUND_OVER, "round parks in ROUND_OVER")
	_check(failures, ts.state()["winner"] == "blue", "blue is the round winner")
	ts.continue_to_next_round()
	var s: Dictionary = ts.state()
	_check(failures, s["phase"] == TurnStateScript.PHASE_AIM, "continue -> AIM")
	_check(failures, s["current_player"] == "blue", "round winner starts the next round")
	_check(failures, s["round_over"] == false, "round_over cleared after continue")
	_check(failures, s["winner"] == "", "winner cleared after continue")
	_check(failures, s["loser"] == "", "loser cleared after continue")

static func _test_continue_cycles_red_blue(failures: Array[String]) -> void:
	var ts = _new_ts()
	ts.begin_turn()                    # round 1: red
	ts.on_flick(Vector2(1, 0))
	ts.on_out_of_bounds("red")         # blue wins round 1
	ts.continue_to_next_round()        # round 2: blue starts
	_check(failures, ts.state()["current_player"] == "blue", "continue #1 -> blue starts round 2")
	ts.on_flick(Vector2(1, 0))
	ts.on_out_of_bounds("blue")        # red wins round 2
	ts.continue_to_next_round()        # round 3: red starts
	_check(failures, ts.state()["current_player"] == "red", "continue #2 cycles back to red")
	_check(failures, ts.state()["phase"] == TurnStateScript.PHASE_AIM, "round 3 back in AIM")

static func _test_continue_requires_round_over(failures: Array[String]) -> void:
	# continue_to_next_round only works from ROUND_OVER; mid-AIM it is a no-op.
	var ts = _new_ts()
	ts.begin_turn()
	ts.continue_to_next_round()
	_check(failures, ts.state()["phase"] == TurnStateScript.PHASE_AIM, "continue from AIM is a no-op")
	_check(failures, ts.state()["current_player"] == "red", "no player advance from AIM")

static func _test_table_rect_helper(failures: Array[String]) -> void:
	var rect: Rect2 = Rect2(0, 0, 100, 80)
	var ts = _new_ts(["red", "blue"], 5.0, rect)
	_check(failures, ts.is_outside_table(Vector2(50, 40)) == false, "point inside the table is not outside")
	_check(failures, ts.is_outside_table(Vector2(101, 40)) == true, "point past the right edge is outside")
	_check(failures, ts.state()["table_rect"] == rect, "table_rect appears in the state snapshot")
