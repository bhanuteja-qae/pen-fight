extends SceneTree
class_name LoopAttributionTest
## Deterministic headless tests for round-decision attribution: TurnState's
## `decided_by()` (knockout / self_oob / stalemate / idle / backstop) and the
## LoopStats session tally built on it.
##
## Why this suite exists: the core-loop re-check (docs/design/core-loop.md) made
## "did a collision decide this round, or did the round end by itself?" the one
## number the Phase-1 playtest needs, and it is only trustworthy if every path
## through the state machine reports the right cause. A mis-attributed metric is
## worse than no metric — the prototype harness already produced one
## (game/prototypes/policy_bot/match_harness.gd:230-232, one conflated
## `_shot_oob` flag), which is exactly what this suite guards against.
##
## Run headless (project root is game/):
##   godot --headless --path game --script res://tests/loop_attribution_test.gd
## (exit code 0 = pass, 1 = fail)
##
## Programmatic entry for the orchestrator:
##   var script = load("res://tests/loop_attribution_test.gd")
##   script.run_tests()   # -> bool
##
## Values are intentionally untyped (Variant): the classes are reached through
## preloaded GDScripts, so typed calls would fail static analysis.

const TurnStateScript := preload("res://scripts/turn_state.gd")
const LoopStatsScript := preload("res://scripts/loop_stats.gd")

# -- entry points --------------------------------------------------------------

## Programmatic entry point: returns true if all tests pass.
static func run_tests() -> bool:
	var failures: Array[String] = []
	_test_undecided_before_any_verdict(failures)
	_test_knockout_attribution(failures)
	_test_self_oob_attribution(failures)
	_test_same_tick_double_oob_is_self_oob(failures)
	_test_settle_stalemate_attribution(failures)
	_test_backstop_stall_attribution(failures)
	_test_backstop_defers_to_oob(failures)
	_test_backstop_handover_is_not_a_decision(failures)
	_test_idle_forfeit_attribution(failures)
	_test_ceremony_flag_follows_attribution(failures)
	_test_begin_turn_clears_attribution(failures)
	_test_stats_counts_and_shares(failures)
	_test_stats_counts_unknown_outcome(failures)
	_test_stats_line_is_greppable(failures)
	_test_stats_from_real_rounds(failures)
	if failures.is_empty():
		print("loop_attribution_test: ALL PASS")
	else:
		print("loop_attribution_test: %d FAILURE(S)" % failures.size())
		for failure in failures:
			print("  FAIL: " + failure)
	return failures.is_empty()

func _init() -> void:
	var ok := run_tests()
	quit(0 if ok else 1)

# -- helpers -------------------------------------------------------------------

static func _check(failures: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)

static func _new_ts() -> Variant:
	return TurnStateScript.new(["red", "blue"], 5.0, Rect2(0, 0, 100, 80))

## Flick, then knock the OTHER pen off the table.
static func _knockout_round(ts: Variant) -> void:
	ts.begin_turn()
	ts.on_flick(Vector2(1, 0))
	ts.on_pen_moved("blue")
	ts.on_out_of_bounds("blue")
	ts.resolve_pending_oob()

## Flick, then send the FLICKER's own pen off the table.
static func _self_oob_round(ts: Variant) -> void:
	ts.begin_turn()
	ts.on_flick(Vector2(1, 0))
	ts.on_out_of_bounds("red")
	ts.resolve_pending_oob()

# -- TurnState attribution -----------------------------------------------------

static func _test_undecided_before_any_verdict(failures: Array[String]) -> void:
	var ts = _new_ts()
	ts.begin_turn()
	_check(failures, ts.decided_by() == "", "a fresh AIM round has no attribution")
	_check(failures, ts.state()["decided_by"] == "", "state() exposes the empty attribution")
	ts.on_flick(Vector2(1, 0))
	_check(failures, ts.decided_by() == "", "an in-flight round has no attribution yet")

static func _test_knockout_attribution(failures: Array[String]) -> void:
	var ts = _new_ts()
	_knockout_round(ts)
	_check(failures, ts.decided_by() == TurnStateScript.DECIDED_BY_KNOCKOUT,
		"the opponent's pen leaving is a knockout")
	_check(failures, ts.state()["decided_by"] == "knockout", "state() carries knockout")
	_check(failures, ts.state()["winner"] == "red", "the flicker wins a knockout")

static func _test_self_oob_attribution(failures: Array[String]) -> void:
	var ts = _new_ts()
	_self_oob_round(ts)
	_check(failures, ts.decided_by() == TurnStateScript.DECIDED_BY_SELF_OOB,
		"the flicker's own pen leaving is self_oob")
	_check(failures, ts.state()["winner"] == "blue", "the other player wins a self-OOB")

static func _test_same_tick_double_oob_is_self_oob(failures: Array[String]) -> void:
	var ts = _new_ts()
	ts.begin_turn()
	ts.on_flick(Vector2(1, 0))
	ts.on_out_of_bounds("red")
	ts.on_out_of_bounds("blue")
	ts.resolve_pending_oob()
	_check(failures, ts.decided_by() == TurnStateScript.DECIDED_BY_SELF_OOB,
		"a same-tick double-OOB is attributed to the flicker (self_oob)")
	_check(failures, ts.state()["winner"] == "blue", "double-OOB: the flicker loses")

static func _test_settle_stalemate_attribution(failures: Array[String]) -> void:
	var ts = _new_ts()
	ts.begin_turn()
	ts.on_flick(Vector2(1, 0))
	ts.on_settled("blue")
	ts.on_settled("red")   # both settled, neither moved
	_check(failures, ts.decided_by() == TurnStateScript.DECIDED_BY_STALEMATE,
		"a settle with no movement is a stalemate")
	_check(failures, ts.state()["loser"] == "red", "the flicker forfeits a stalemate")

static func _test_backstop_stall_attribution(failures: Array[String]) -> void:
	var ts = _new_ts()
	ts.begin_turn()
	ts.on_flick(Vector2(1, 0))
	ts.resolve_tick(TurnStateScript.RESOLVE_TIMEOUT + 0.1)
	_check(failures, ts.decided_by() == TurnStateScript.DECIDED_BY_BACKSTOP,
		"the 8 s in-flight clock forcing a never-moved verdict is a backstop")

static func _test_backstop_defers_to_oob(failures: Array[String]) -> void:
	var ts = _new_ts()
	ts.begin_turn()
	ts.on_flick(Vector2(1, 0))
	ts.on_out_of_bounds("blue")
	ts.resolve_tick(TurnStateScript.RESOLVE_TIMEOUT + 0.1)
	_check(failures, ts.decided_by() == TurnStateScript.DECIDED_BY_KNOCKOUT,
		"the backstop defers to a buffered OOB verdict, and reports it as such")

static func _test_backstop_handover_is_not_a_decision(failures: Array[String]) -> void:
	var ts = _new_ts()
	ts.begin_turn()
	ts.on_flick(Vector2(1, 0))
	ts.on_pen_moved("red")
	ts.resolve_tick(TurnStateScript.RESOLVE_TIMEOUT + 0.1)
	_check(failures, ts.decided_by() == "",
		"a backstop hand-over (pens moved, still on the table) decides nothing")
	_check(failures, ts.state()["phase"] == TurnStateScript.PHASE_AIM,
		"a backstop hand-over returns to AIM for the next player")

static func _test_idle_forfeit_attribution(failures: Array[String]) -> void:
	var ts = _new_ts()
	ts.begin_turn()
	ts.forfeit_tick(5.1)
	_check(failures, ts.decided_by() == TurnStateScript.DECIDED_BY_IDLE,
		"not flicking inside forfeit_timeout is an idle forfeit")
	_check(failures, ts.state()["loser"] == "red", "the idle player forfeits")

static func _test_ceremony_flag_follows_attribution(failures: Array[String]) -> void:
	var ts = _new_ts()
	_knockout_round(ts)
	_check(failures, ts.decided_by_oob() == true, "knockout drives the impact ceremony")
	var ts2 = _new_ts()
	ts2.begin_turn()
	ts2.forfeit_tick(5.1)
	_check(failures, ts2.decided_by_oob() == false, "idle forfeit does not drive the impact ceremony")
	var ts3 = _new_ts()
	ts3.begin_turn()
	ts3.on_flick(Vector2(1, 0))
	ts3.resolve_tick(TurnStateScript.RESOLVE_TIMEOUT + 0.1)
	_check(failures, ts3.decided_by_oob() == false, "backstop does not drive the impact ceremony")

static func _test_begin_turn_clears_attribution(failures: Array[String]) -> void:
	var ts = _new_ts()
	_self_oob_round(ts)
	_check(failures, ts.decided_by() == "self_oob", "precondition: round decided")
	ts.continue_to_next_round()
	_check(failures, ts.decided_by() == "", "the next round starts with a clean attribution")
	_check(failures, ts.state()["decided_by"] == "", "state() is clean too")

# -- LoopStats -----------------------------------------------------------------

static func _test_stats_counts_and_shares(failures: Array[String]) -> void:
	var stats = LoopStatsScript.new()
	_check(failures, stats.rounds() == 0, "a fresh tally has no rounds")
	_check(failures, stats.contact_share() == 0.0, "a fresh tally has no contact share")
	_check(failures, stats.shots_per_round() == 0.0, "a fresh tally has no shots/round")
	for i in 7:
		stats.record_flick()
	stats.record_round("knockout")
	stats.record_round("knockout")
	stats.record_round("self_oob")
	stats.record_round("idle")
	stats.record_round("backstop")
	_check(failures, stats.rounds() == 5, "five decided rounds counted")
	_check(failures, stats.flicks() == 7, "seven flicks counted")
	_check(failures, stats.count("knockout") == 2, "two knockouts counted")
	_check(failures, stats.resolved_by_contact() == 3, "knockout + self_oob is the contact count")
	_check(failures, is_equal_approx(stats.contact_share(), 0.6), "3 of 5 rounds decided by contact")
	_check(failures, is_equal_approx(stats.shots_per_round(), 1.4), "7 shots over 5 rounds")

static func _test_stats_counts_unknown_outcome(failures: Array[String]) -> void:
	var stats = LoopStatsScript.new()
	stats.record_round("some_future_outcome")
	_check(failures, stats.count("some_future_outcome") == 1,
		"an unknown outcome is counted, never silently dropped")
	_check(failures, stats.rounds() == 1, "an unknown outcome still counts as a round")

static func _test_stats_line_is_greppable(failures: Array[String]) -> void:
	var stats = LoopStatsScript.new()
	stats.record_flick()
	stats.record_round("knockout")
	stats.record_round("self_oob")
	stats.record_round("idle")
	stats.record_round("backstop")
	var line: String = stats.to_line()
	_check(failures, line.begins_with("[LOOP] rounds=4 "), "the tally line is prefixed and countable: " + line)
	_check(failures, line.contains("contact=2 (50%)"), "the tally line reports the contact share: " + line)
	_check(failures, line.contains("shots/round=0.25"), "the tally line reports pacing: " + line)
	var summary: Dictionary = stats.summary()
	_check(failures, int(summary.get("rounds", -1)) == 4, "summary() reports rounds")
	_check(failures, is_equal_approx(float(summary.get("contact_share", -1.0)), 0.5), "summary() reports the share")

static func _test_stats_from_real_rounds(failures: Array[String]) -> void:
	## End-to-end: drive TurnState through three rounds and tally what it reports.
	## This is the check that the two vocabularies cannot drift apart.
	var ts = _new_ts()
	var stats = LoopStatsScript.new()
	_knockout_round(ts)
	stats.record_round(ts.decided_by())
	stats.record_flick()
	ts.continue_to_next_round()
	_self_oob_round(ts)
	stats.record_round(ts.decided_by())
	stats.record_flick()
	ts.continue_to_next_round()
	ts.forfeit_tick(5.1)
	stats.record_round(ts.decided_by())
	_check(failures, stats.count("knockout") == 1, "real knockout round reached the tally")
	_check(failures, stats.count("self_oob") == 1, "real self-OOB round reached the tally")
	_check(failures, stats.count("idle") == 1, "real idle forfeit reached the tally")
	_check(failures, stats.rounds() == 3, "three real rounds tallied")
	_check(failures, stats.flicks() == 2, "two real accepted shots tallied")
