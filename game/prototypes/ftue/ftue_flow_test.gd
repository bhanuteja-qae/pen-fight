extends SceneTree
class_name FtueFlowTest
## Deterministic headless tests for FtueFlow (Wave 1, wayfinder ticket #12;
## docs/prototypes/CONTRACTS-ftue.md). Pure logic, no scene deps: the module is
## preloaded, never added to the tree. Covers: the pinned Beat enum, the
## mode x ruleset matrix (exact beat chains), the tap budget, an EXHAUSTIVE
## interaction walk over all four mode x ruleset combos (every sequence of
## length 4 over {drag, skip, ack, commit, tick}) proving (a) RIVAL_CHOICE
## iff Solo, (b) TRADEOFF iff Pen Powers, (c) only PLAY after the first shot
## commits, (d) no illegal beat edge can ever fire, plus teach-cancel-on-drag
## from every beat, no-re-arm, double-flick, skip() from every beat, tick
## advance without input, cue fit, and a source-scan guard for nodes/timers.
##
## Run headless (project root is game/):
##   godot --headless --path game --script res://prototypes/ftue/ftue_flow_test.gd
## (exit code 0 = pass, 1 = fail)
##
## Entry convention matches game/tests/turn_state_test.gd and
## game/prototypes/app_flow/app_flow_test.gd: `extends SceneTree` + `_init()`
## calling quit(code) is Godot's documented standalone-script pattern. The
## module preloaded here derives from MainLoop (see its class doc comment), so
## it is NOT reference-counted: this suite keeps every instance it creates in
## `_owned` and frees them before reporting, or Godot would print an ObjectDB
## leak warning at exit.
##
## Test values that touch the preloaded script are intentionally untyped
## (Variant), matching turn_state_test.gd / app_flow_test.gd (typed calls
## through a preloaded script fail static analysis).

const FtueFlowScript := preload("res://prototypes/ftue/ftue_flow.gd")

## Frame step used wherever a test simulates real time. This is the test's own
## simulation step, independent of the engine's physics tick rate.
const FRAME := 1.0 / 60.0
## The interaction alphabet for the exhaustive walk.
const TOKENS := ["drag", "skip", "ack", "commit", "tick"]
## Idle-timer step used by the "tick" token: comfortably past the dwell.
const IDLE_STEP := 30.0
## Printed-failure cap: the gate output must stay readable.
const MAX_REPORTED_FAILURES := 40

static var _owned: Array = []

# -- entry points --------------------------------------------------------------

## Programmatic entry point: returns true if all tests pass.
static func run_tests() -> bool:
	var failures: Array[String] = []
	var walks := [0]
	_test_beat_enum_matches_pinned_order(failures)
	_test_initial_state_is_play_and_silent(failures)
	_test_process_smoke_frame_exits_and_is_inert(failures)
	_test_mode_ruleset_matrix_chains(failures)
	_test_resolution_defaults_are_strict(failures)
	_test_teach_dies_on_drag_from_every_beat(failures)
	_test_teach_never_rearms_after_drag(failures)
	_test_only_play_after_first_shot_committed(failures)
	_test_skip_from_every_beat(failures)
	_test_tick_advance_without_input(failures)
	_test_tap_budget_boot_to_live_aim(failures)
	_test_beat_changed_edges_are_legal(failures)
	_test_exhaustive_interaction_walk(failures, walks)
	_test_cue_text_fits(failures)
	_test_no_nodes_or_timers_in_source(failures)
	if failures.is_empty():
		print("ftue_flow_test: exhaustive walk cross-checked %d interaction sequences over 4 mode x ruleset combos" % walks[0])
		print("ftue_flow_test: ALL PASS")
		_release_flows()
		return true
	print("ftue_flow_test: %d FAILURE(S)" % failures.size())
	var shown := mini(failures.size(), MAX_REPORTED_FAILURES)
	for i in range(shown):
		print("  FAIL: " + failures[i])
	if failures.size() > shown:
		print("  ... %d more failure(s) not printed" % (failures.size() - shown))
	_release_flows()
	return false


## Entry when run via `--script`. Uses the documented SceneTree pattern.
func _init() -> void:
	var ok := run_tests()
	quit(0 if ok else 1)

# -- harness --------------------------------------------------------------------

static func _check(failures: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


## Fresh FtueFlow instance, no scene dependencies. Tracked for manual freeing.
static func _new_flow() -> Variant:
	var flow = FtueFlowScript.new()
	_owned.append(flow)
	return flow


## MainLoop is not reference-counted: every instance this suite created is
## freed here, once, after all assertions have run.
static func _release_flows() -> void:
	for flow in _owned:
		if is_instance_valid(flow):
			flow.free()
	_owned.clear()


## Recorder for the module's only signal. Dictionary (not typed vars) so the
## lambdas below capture and mutate the same instance.
static func _recorder(flow: Variant) -> Dictionary:
	var rec := {"changed": []}
	flow.beat_changed.connect(func(from, to): rec["changed"].append([from, to]))
	return rec


## Drives a fresh flow into the canonical state that shows `target`. The path
## is deliberately the shortest legal one a host would take; the recorder is
## cleared at the end so callers only see their own edges.
static func _flow_at_beat(target: int) -> Array:
	var flow = _new_flow()
	var rec := _recorder(flow)
	var teach: int = FtueFlowScript.Beat.TEACH
	var first_shot: int = FtueFlowScript.Beat.FIRST_SHOT
	var rival: int = FtueFlowScript.Beat.RIVAL_CHOICE
	var tradeoff: int = FtueFlowScript.Beat.TRADEOFF
	if target == rival:
		flow.start_first_minute("solo", "classic")
	elif target == tradeoff:
		flow.start_first_minute("hot_seat", "pen_powers")
	elif target == teach:
		flow.start_first_minute("hot_seat", "classic")
	elif target == first_shot:
		flow.start_first_minute("hot_seat", "classic")
		flow.tick(IDLE_STEP)
	else:
		flow.start_first_minute("hot_seat", "classic")
		flow.skip()
	rec["changed"].clear()
	return [flow, rec]


## Every beat the module can present as the *first* beat of a first minute.
static func _reachable_beats() -> Array:
	return [
		FtueFlowScript.Beat.TEACH,
		FtueFlowScript.Beat.FIRST_SHOT,
		FtueFlowScript.Beat.RIVAL_CHOICE,
		FtueFlowScript.Beat.TRADEOFF,
		FtueFlowScript.Beat.PLAY,
	]


static func _beat_name(value: int) -> String:
	return FtueFlowScript.Beat.keys()[value]


static func _chain_names(edges: Array) -> String:
	var parts: Array[String] = []
	for edge in edges:
		parts.append("%s->%s" % [_beat_name(edge[0]), _beat_name(edge[1])])
	return "[" + ", ".join(parts) + "]"


static func _apply(flow: Variant, token: String) -> void:
	match token:
		"drag":
			flow.on_drag_started()
		"skip":
			flow.skip()
		"ack":
			flow.on_tradeoff_acknowledged()
		"commit":
			flow.on_first_shot_committed()
		"tick":
			flow.tick(IDLE_STEP)


## All sequences of `length` tokens over TOKENS.
static func _sequences(length: int) -> Array:
	var out: Array = [[]]
	for _i in range(length):
		var grown: Array = []
		for seq in out:
			for token in TOKENS:
				var extended: Array = (seq as Array).duplicate()
				extended.append(token)
				grown.append(extended)
		out = grown
	return out

# -- tests: pinned shape --------------------------------------------------------

## The contract pins the beat set and its order; a reordering would silently
## change every chain below, so it is asserted literally.
static func _test_beat_enum_matches_pinned_order(failures: Array[String]) -> void:
	var keys: Array = FtueFlowScript.Beat.keys()
	_check(failures, keys == ["TEACH", "FIRST_SHOT", "RIVAL_CHOICE", "TRADEOFF", "PLAY"],
		"Beat enum is exactly {TEACH, FIRST_SHOT, RIVAL_CHOICE, TRADEOFF, PLAY} in pinned order (got %s)" % str(keys))


static func _test_initial_state_is_play_and_silent(failures: Array[String]) -> void:
	var flow = _new_flow()
	var rec := _recorder(flow)
	_check(failures, flow.beat == FtueFlowScript.Beat.PLAY, "FtueFlow starts at PLAY (no first-minute beat armed)")
	_check(failures, flow.visible_cue() == "", "a flow that never started shows no cue")
	flow.tick(IDLE_STEP)
	flow.on_drag_started()
	flow.skip()
	flow.on_tradeoff_acknowledged()
	flow.on_first_shot_committed()
	_check(failures, flow.beat == FtueFlowScript.Beat.PLAY, "driving the whole API before start_first_minute() stays at PLAY")
	_check(failures, rec["changed"].is_empty(), "driving the whole API before start_first_minute() emits no beat_changed")


## The pinned smoke gate runs this file as a main loop; `_process()` must end
## that loop on its first frame and must not be a back door into the beat
## machine (no consumer feeds it, but the contract asks for no self-driven
## behavior, so it is asserted rather than assumed).
static func _test_process_smoke_frame_exits_and_is_inert(failures: Array[String]) -> void:
	var flow = _new_flow()
	var rec := _recorder(flow)
	flow.start_first_minute("solo", "pen_powers")
	rec["changed"].clear()
	var before: int = flow.beat
	_check(failures, flow._process(FRAME) == true, "_process() returns true on its first call (the --script smoke gate then exits 0)")
	_check(failures, flow._process(FRAME) == true, "_process() keeps returning true")
	_check(failures, flow.beat == before, "_process() does not move the beat")
	_check(failures, rec["changed"].is_empty(), "_process() emits no beat_changed")

# -- tests: mode x ruleset matrix -------------------------------------------------

## The matrix, as exact chains. Each combo is driven through the tap path a
## real player would take and every beat change is compared literally.
static func _test_mode_ruleset_matrix_chains(failures: Array[String]) -> void:
	var combos := [
		{
			"mode": "hot_seat", "ruleset": "classic",
			"steps": ["tick", "commit"],
			"expected": [[4, 0], [0, 1], [1, 4]],
			"label": "hot_seat x classic",
		},
		{
			"mode": "hot_seat", "ruleset": "pen_powers",
			"steps": ["ack", "skip"],
			"expected": [[4, 3], [3, 0], [0, 4]],
			"label": "hot_seat x pen_powers",
		},
		{
			"mode": "solo", "ruleset": "classic",
			"steps": ["skip", "skip"],
			"expected": [[4, 2], [2, 0], [0, 4]],
			"label": "solo x classic",
		},
		{
			"mode": "solo", "ruleset": "pen_powers",
			"steps": ["skip", "ack", "drag"],
			"expected": [[4, 2], [2, 3], [3, 0], [0, 4]],
			"label": "solo x pen_powers",
		},
	]
	for combo in combos:
		var flow = _new_flow()
		var rec := _recorder(flow)
		flow.start_first_minute(combo["mode"], combo["ruleset"])
		for step in combo["steps"]:
			_apply(flow, step)
		_check(failures, rec["changed"] == combo["expected"],
			"%s chain is %s (got %s)" % [combo["label"], str(combo["expected"]), _chain_names(rec["changed"])])
		_check(failures, flow.beat == FtueFlowScript.Beat.PLAY,
			"%s ends in PLAY (got %s)" % [combo["label"], _beat_name(flow.beat)])


## Unknown or near-miss tokens resolve to the safe defaults instead of erroring
## — that is what makes the RIVAL_CHOICE/TRADEOFF invariants strict, so the
## fallback itself is pinned here. Columns: [mode in, ruleset in, opening beat,
## TRADEOFF visible at open, RIVAL_CHOICE visible at open, TRADEOFF reachable].
## "Pen Powers" and "pen powers" are deliberate near-misses: they must NOT
## resolve to pen_powers (exact token after lowercasing/trimming only). Note
## solo x pen_powers opens on RIVAL_CHOICE, so TRADEOFF is reachable but not
## visible at open — exactly the case the reachability probe below covers.
static func _test_resolution_defaults_are_strict(failures: Array[String]) -> void:
	var cases := [
		["solo", "Pen Powers", 2, false, true, false],
		["solo", "pen powers", 2, false, true, false],
		[" solo ", " PEN_POWERS ", 2, false, true, true],
		["SOLO", "pen_powers", 2, false, true, true],
		["hot seat", "classic", 0, false, false, false],
		["", "", 0, false, false, false],
		["hot_seat", "PEN_POWERS", 3, true, false, true],
		["hot_seat", "0", 0, false, false, false],
	]
	for case in cases:
		var flow = _new_flow()
		var rec := _recorder(flow)
		flow.start_first_minute(case[0], case[1])
		_check(failures, flow.beat == case[2],
			"start_first_minute(%s, %s) opens on %s (got %s)" % [case[0], case[1], _beat_name(case[2]), _beat_name(flow.beat)])
		_check(failures, _visited(rec, flow, FtueFlowScript.Beat.RIVAL_CHOICE) == case[4],
			"start_first_minute(%s, %s) opens on RIVAL_CHOICE == %s" % [case[0], case[1], str(case[4])])
		_check(failures, _visited(rec, flow, FtueFlowScript.Beat.TRADEOFF) == case[3],
			"start_first_minute(%s, %s) opens on TRADEOFF == %s" % [case[0], case[1], str(case[3])])
	## The other half of "TRADEOFF only when pen_powers": the canonical pre-flick
	## path (dismiss whatever card is up) MUST surface TRADEOFF under pen_powers
	## and must never surface it otherwise.
	for case in cases:
		var flow = _new_flow()
		var rec := _recorder(flow)
		flow.start_first_minute(case[0], case[1])
		for _step in range(4):
			flow.skip()
		_check(failures, _visited(rec, flow, FtueFlowScript.Beat.TRADEOFF) == case[5],
			"the canonical pre-flick path for (%s, %s) surfaces TRADEOFF == %s" % [case[0], case[1], str(case[5])])


## true if `beat` is either currently active or appeared in the edge log.
static func _visited(rec: Dictionary, flow: Variant, beat: int) -> bool:
	if flow.beat == beat:
		return true
	for edge in rec["changed"]:
		if edge[0] == beat or edge[1] == beat:
			return true
	return false

# -- tests: the teach ------------------------------------------------------------

## Invariant 2, first half: from EVERY beat, one grab clears the beat, with no
## acknowledgement, no tick and no other call in between.
static func _test_teach_dies_on_drag_from_every_beat(failures: Array[String]) -> void:
	for beat in _reachable_beats():
		var pair := _flow_at_beat(beat)
		var flow = pair[0]
		var rec: Dictionary = pair[1]
		var cue_before: String = flow.visible_cue()
		flow.on_drag_started()
		_check(failures, flow.beat == FtueFlowScript.Beat.PLAY,
			"one drag from %s lands in PLAY (got %s)" % [_beat_name(beat), _beat_name(flow.beat)])
		_check(failures, flow.visible_cue() == "",
			"one drag from %s clears the cue (was %s, now %s)" % [_beat_name(beat), cue_before, flow.visible_cue()])
		var expected_edges := 0 if beat == FtueFlowScript.Beat.PLAY else 1
		_check(failures, rec["changed"].size() == expected_edges,
			"one drag from %s emits %d beat_changed (got %s)" % [_beat_name(beat), expected_edges, _chain_names(rec["changed"])])
		if expected_edges == 1:
			_check(failures, rec["changed"][0] == [beat, FtueFlowScript.Beat.PLAY],
				"the drag edge from %s is %s->PLAY" % [_beat_name(beat), _beat_name(beat)])
		var second := _recorder(flow)
		flow.on_drag_started()
		_check(failures, second["changed"].is_empty(), "a second drag after %s emits no beat_changed" % _beat_name(beat))


## Invariant 2, second half: a cancelled gesture (grab, no committed flick) must
## not bring the teach back — not on the next frame, not 5 minutes later, not
## via any other entry point. The only call that can arm a beat is
## start_first_minute(), which is the host's turn/rematch boundary.
static func _test_teach_never_rearms_after_drag(failures: Array[String]) -> void:
	var pair := _flow_at_beat(FtueFlowScript.Beat.TEACH)
	var flow = pair[0]
	var rec: Dictionary = pair[1]
	flow.on_drag_started()
	rec["changed"].clear()
	for _frame in range(int(300.0 / FRAME)):
		flow.tick(FRAME)
	_check(failures, rec["changed"].is_empty(), "300 s of ticks after a grab emit no beat_changed")
	_check(failures, flow.beat == FtueFlowScript.Beat.PLAY, "300 s of ticks after a grab stay in PLAY")
	_check(failures, flow.visible_cue() == "", "300 s of ticks after a grab show no cue")
	flow.skip()
	flow.on_tradeoff_acknowledged()
	flow.tick(IDLE_STEP)
	_check(failures, flow.beat == FtueFlowScript.Beat.PLAY, "skip/ack/tick after a grab cannot re-arm a beat")
	## ... and the boundary is real: the host's next first minute DOES arm it.
	flow.start_first_minute("hot_seat", "classic")
	_check(failures, flow.beat == FtueFlowScript.Beat.TEACH,
		"only start_first_minute() re-arms the first minute (new turn / rematch)")


## Invariant 3, including the double-flick case: after the first shot commits,
## no beat other than PLAY may ever be active again.
static func _test_only_play_after_first_shot_committed(failures: Array[String]) -> void:
	for beat in _reachable_beats():
		var pair := _flow_at_beat(beat)
		var flow = pair[0]
		var rec: Dictionary = pair[1]
		flow.on_first_shot_committed()
		_check(failures, flow.beat == FtueFlowScript.Beat.PLAY,
			"the first committed flick from %s leaves PLAY active (got %s)" % [_beat_name(beat), _beat_name(flow.beat)])
		_check(failures, flow.visible_cue() == "", "no cue survives the first committed flick (was %s)" % _beat_name(beat))
		var expected_edges := 0 if beat == FtueFlowScript.Beat.PLAY else 1
		_check(failures, rec["changed"].size() == expected_edges,
			"committing from %s emits %d beat_changed" % [_beat_name(beat), expected_edges])
		var after := _recorder(flow)
		for token in TOKENS:
			_apply(flow, token)
		flow.on_first_shot_committed()
		_check(failures, flow.beat == FtueFlowScript.Beat.PLAY,
			"every call after the first committed flick from %s (double-flick included) stays in PLAY" % _beat_name(beat))
		_check(failures, after["changed"].is_empty(),
			"every call after the first committed flick from %s emits no beat_changed" % _beat_name(beat))

# -- tests: skip, tick, budget ----------------------------------------------------

## skip() is defined from every beat: an escape (PLAY) from the teach beats,
## a dismissal-to-next-beat from the two pre-flick cards, a no-op in PLAY.
static func _test_skip_from_every_beat(failures: Array[String]) -> void:
	var expectations := {
		FtueFlowScript.Beat.TEACH: FtueFlowScript.Beat.PLAY,
		FtueFlowScript.Beat.FIRST_SHOT: FtueFlowScript.Beat.PLAY,
		FtueFlowScript.Beat.RIVAL_CHOICE: FtueFlowScript.Beat.TEACH,
		FtueFlowScript.Beat.TRADEOFF: FtueFlowScript.Beat.TEACH,
		FtueFlowScript.Beat.PLAY: FtueFlowScript.Beat.PLAY,
	}
	for beat in _reachable_beats():
		var pair := _flow_at_beat(beat)
		var flow = pair[0]
		var rec: Dictionary = pair[1]
		flow.skip()
		var want: int = expectations[beat]
		_check(failures, flow.beat == want,
			"skip() from %s lands on %s (got %s)" % [_beat_name(beat), _beat_name(want), _beat_name(flow.beat)])
		var expected_edges := 0 if beat == want else 1
		_check(failures, rec["changed"].size() == expected_edges,
			"skip() from %s emits %d beat_changed (got %s)" % [_beat_name(beat), expected_edges, _chain_names(rec["changed"])])
	## Skipping solo x pen_powers' two cards reaches the teach, and one more
	## skip from there is the pinned one-tap escape.
	var flow = _new_flow()
	flow.start_first_minute("solo", "pen_powers")
	flow.skip()
	flow.skip()
	flow.skip()
	_check(failures, flow.beat == FtueFlowScript.Beat.PLAY, "skip() twice through solo x pen_powers cards then escapes to PLAY")


## tick() is the only self-advance: it relaxes the teach into the first-shot
## cue and moves past the rival card, never touches a grabbed turn, never
## re-arms, never fast-forwards more than one beat, and ignores paused frames.
static func _test_tick_advance_without_input(failures: Array[String]) -> void:
	var flow = _new_flow()
	var rec := _recorder(flow)
	var dwell: float = FtueFlowScript.IDLE_ADVANCE_SECONDS
	flow.start_first_minute("hot_seat", "classic")
	rec["changed"].clear()
	flow.tick(dwell - 1.0)
	_check(failures, flow.beat == FtueFlowScript.Beat.TEACH, "the teach survives a dwell just under the idle window")
	flow.tick(0.5)
	_check(failures, flow.beat == FtueFlowScript.Beat.TEACH, "... and still survives it while the dwell is below the window")
	flow.tick(0.5)
	_check(failures, flow.beat == FtueFlowScript.Beat.FIRST_SHOT,
		"an idle player who never grabs is moved to the first-shot cue (got %s)" % _beat_name(flow.beat))
	flow.tick(IDLE_STEP)
	flow.tick(IDLE_STEP)
	_check(failures, flow.beat == FtueFlowScript.Beat.FIRST_SHOT, "the first-shot cue waits for the real flick instead of scrolling on")
	_check(failures, rec["changed"] == [[FtueFlowScript.Beat.TEACH, FtueFlowScript.Beat.FIRST_SHOT]],
		"the idle path emits exactly one edge (%s)" % _chain_names(rec["changed"]))
	## A single giant delta must not fast-forward the whole first minute.
	var jump = _new_flow()
	var jump_rec := _recorder(jump)
	jump.start_first_minute("solo", "pen_powers")
	jump_rec["changed"].clear()
	jump.tick(3600.0)
	_check(failures, jump.beat == FtueFlowScript.Beat.TRADEOFF,
		"one enormous delta advances at most one beat (got %s)" % _beat_name(jump.beat))
	_check(failures, jump_rec["changed"].size() == 1, "one enormous delta emits exactly one edge")
	## Negative / zero deltas (a paused host) are inert, and TRADEOFF is sticky.
	jump.tick(0.0)
	jump.tick(-5.0)
	_check(failures, jump.beat == FtueFlowScript.Beat.TRADEOFF,
		"TRADEOFF waits for its acknowledgement: paused and negative deltas do nothing (got %s)" % _beat_name(jump.beat))
	jump.tick(3600.0)
	_check(failures, jump.beat == FtueFlowScript.Beat.TRADEOFF, "TRADEOFF is sticky under idle time as well")


## Invariant 5: the whole launch path costs three host taps, and the FTUE's own
## required-tap cost is zero — from every first beat of every combo, the very
## first FTUE call a grabbing player makes is honoured.
static func _test_tap_budget_boot_to_live_aim(failures: Array[String]) -> void:
	## Host tap ledger, mirrored 1:1 in docs/prototypes/ftue/mock/index.html:
	##   tap 1: BOOT -> HOME     app_flow.boot_complete()
	##   tap 2: HOME -> MODE     app_flow.open_mode_select()
	##   tap 3: MODE -> live AIM app_flow.start_match(mode) + ftue.start_first_minute(mode, ruleset)
	var host_taps := 3
	_check(failures, FtueFlowScript.TAPS_REQUIRED_BEFORE_FIRST_FLICK == 0,
		"the FTUE's own required-tap cost before a legal flick is 0")
	_check(failures, host_taps + FtueFlowScript.TAPS_REQUIRED_BEFORE_FIRST_FLICK <= FtueFlowScript.TAP_BUDGET_BOOT_TO_LIVE_AIM,
		"%d host taps + %d FTUE taps <= the pinned budget of %d" % [host_taps, FtueFlowScript.TAPS_REQUIRED_BEFORE_FIRST_FLICK, FtueFlowScript.TAP_BUDGET_BOOT_TO_LIVE_AIM])
	var combos := [["hot_seat", "classic"], ["hot_seat", "pen_powers"], ["solo", "classic"], ["solo", "pen_powers"]]
	for combo in combos:
		var flow = _new_flow()
		var rec := _recorder(flow)
		flow.start_first_minute(combo[0], combo[1])
		_check(failures, flow.beat != FtueFlowScript.Beat.PLAY,
			"%s opens the first minute on a real beat (the third tap lands on it)" % str(combo))
		## The player grabs immediately: this is the FIRST FTUE call ever made.
		rec["changed"].clear()
		flow.on_drag_started()
		_check(failures, flow.beat == FtueFlowScript.Beat.PLAY and flow.visible_cue() == "",
			"%s: tap 3 leaves a live AIM turn — a grab is honoured at once, with no beat tapped through first" % str(combo))
		_check(failures, rec["changed"].size() == 1, "%s: grab-first emits exactly one edge" % str(combo))


## Structural guard on the beat machine: the only edges it can ever emit are
## the pinned chain, and never a self-loop.
static func _test_beat_changed_edges_are_legal(failures: Array[String]) -> void:
	var teach: int = FtueFlowScript.Beat.TEACH
	var first_shot: int = FtueFlowScript.Beat.FIRST_SHOT
	var rival: int = FtueFlowScript.Beat.RIVAL_CHOICE
	var tradeoff: int = FtueFlowScript.Beat.TRADEOFF
	var play: int = FtueFlowScript.Beat.PLAY
	var legal := [
		[play, teach], [play, first_shot], [play, rival], [play, tradeoff],
		[rival, tradeoff], [rival, teach], [tradeoff, teach], [teach, first_shot],
		[teach, play], [first_shot, play], [rival, play], [tradeoff, play],
	]
	var combos := [["hot_seat", "classic"], ["hot_seat", "pen_powers"], ["solo", "classic"], ["solo", "pen_powers"]]
	for combo in combos:
		for seq in _sequences(4):
			var flow = _new_flow()
			var rec := _recorder(flow)
			flow.start_first_minute(combo[0], combo[1])
			for token in seq:
				_apply(flow, token)
			for edge in rec["changed"]:
				_check(failures, legal.has([edge[0], edge[1]]),
					"%s / %s emitted an illegal beat edge %s" % [str(combo), str(seq), _chain_names([edge])])


## The exhaustive walk the contract's invariant list implies: 4 combos x 5^4
## interaction sequences. Asserts, at every step of every sequence, that no
## beat other than PLAY survives a committed first shot, that the cue always
## fits, and that neither RIVAL_CHOICE nor TRADEOFF can EVER be reached outside
## its combo (the "never"/"only when" directions). The matching "but it IS
## reachable" directions are probed once per combo here and pinned as exact
## chains in _test_mode_ruleset_matrix_chains(). Note the asymmetry is real,
## not a weakening: a lock ("hot_seat never enters RIVAL_CHOICE") is a
## for-all claim and belongs on every walk; "solo does enter it" is an
## existence claim and belongs on the canonical path.
static func _test_exhaustive_interaction_walk(failures: Array[String], walks: Array) -> void:
	var combos := [["hot_seat", "classic"], ["hot_seat", "pen_powers"], ["solo", "classic"], ["solo", "pen_powers"]]
	var alphabet := _sequences(4)
	var checked := 0
	for combo in combos:
		var solo: bool = combo[0] == "solo"
		var pen_powers: bool = combo[1] == "pen_powers"
		## Reachability probe: start the first minute, dismiss whatever card is
		## up, nothing else. This is the cheapest path to TRADEOFF.
		var probe = _new_flow()
		var probe_rec := _recorder(probe)
		probe.start_first_minute(combo[0], combo[1])
		for _step in range(4):
			probe.skip()
		_check(failures, _visited(probe_rec, probe, FtueFlowScript.Beat.RIVAL_CHOICE) == solo,
			"%s: RIVAL_CHOICE is reachable == %s" % [str(combo), str(solo)])
		_check(failures, _visited(probe_rec, probe, FtueFlowScript.Beat.TRADEOFF) == pen_powers,
			"%s: TRADEOFF is reachable == %s" % [str(combo), str(pen_powers)])
		for seq in alphabet:
			var flow = _new_flow()
			var rec := _recorder(flow)
			flow.start_first_minute(combo[0], combo[1])
			var committed: bool = false
			for token in seq:
				_apply(flow, token)
				if token == "commit":
					committed = true
				if committed and flow.beat != FtueFlowScript.Beat.PLAY:
					_check(failures, false,
						"%s / %s: beat %s is active after the first shot committed" % [str(combo), str(seq), _beat_name(flow.beat)])
			if not solo and _visited(rec, flow, FtueFlowScript.Beat.RIVAL_CHOICE):
				_check(failures, false, "%s / %s: RIVAL_CHOICE reached outside Solo" % [str(combo), str(seq)])
			if not pen_powers and _visited(rec, flow, FtueFlowScript.Beat.TRADEOFF):
				_check(failures, false, "%s / %s: TRADEOFF reached outside pen_powers" % [str(combo), str(seq)])
			_check(failures, flow.visible_cue().length() <= FtueFlowScript.MAX_CUE_CHARS,
				"%s / %s: cue fits" % [str(combo), str(seq)])
			checked += 1
	walks[0] = checked

# -- tests: cue text --------------------------------------------------------------

## The cue is the only copy this module owns, so its shape is pinned: one short
## uppercase line, ASCII, no stray whitespace — a string a phone-width layout
## can always fit (never assume 1280; keep_height means logical width varies).
static func _test_cue_text_fits(failures: Array[String]) -> void:
	var cues := [
		[FtueFlowScript.Beat.TEACH, FtueFlowScript.CUE_TEACH],
		[FtueFlowScript.Beat.FIRST_SHOT, FtueFlowScript.CUE_FIRST_SHOT],
		[FtueFlowScript.Beat.RIVAL_CHOICE, FtueFlowScript.CUE_RIVAL_CHOICE],
		[FtueFlowScript.Beat.TRADEOFF, FtueFlowScript.CUE_TRADEOFF],
	]
	var seen: Array[String] = []
	for entry in cues:
		var pair := _flow_at_beat(entry[0])
		var flow = pair[0]
		var cue: String = flow.visible_cue()
		_check(failures, cue == entry[1], "visible_cue() for %s returns the pinned constant" % _beat_name(entry[0]))
		_check(failures, cue.length() > 0 and cue.length() <= FtueFlowScript.MAX_CUE_CHARS,
			"the %s cue is 1..%d chars (got %d)" % [_beat_name(entry[0]), FtueFlowScript.MAX_CUE_CHARS, cue.length()])
		_check(failures, cue == cue.to_upper(), "the %s cue is uppercase" % _beat_name(entry[0]))
		_check(failures, cue == cue.strip_edges(), "the %s cue has no stray whitespace" % _beat_name(entry[0]))
		_check(failures, not seen.has(cue), "the %s cue is distinct from every other beat's cue" % _beat_name(entry[0]))
		seen.append(cue)
	var play_pair := _flow_at_beat(FtueFlowScript.Beat.PLAY)
	_check(failures, play_pair[0].visible_cue() == "", "PLAY shows nothing (\"\" means nothing should be shown)")

# -- tests: source-scan guard -----------------------------------------------------

## The contract's boundaries made observable in the file itself: pure logic, no
## nodes, no scene deps, no timers of its own, and the one documented base-class
## decision. Mirrors the technique in app_flow_test.gd / policy_bot_test.gd.
static func _test_no_nodes_or_timers_in_source(failures: Array[String]) -> void:
	var source := FileAccess.get_file_as_string("res://prototypes/ftue/ftue_flow.gd")
	_check(failures, source.length() > 0, "ftue_flow.gd source is readable for the scan")
	var lines := source.split("\n")
	var extends_line := ""
	for line in lines:
		if line.begins_with("extends "):
			extends_line = line.strip_edges()
			break
	_check(failures, extends_line == "extends MainLoop",
		"ftue_flow.gd derives from MainLoop so the pinned --script smoke gate can load it (found %s)" % extends_line)
	var forbidden := [
		".instantiate(", "PackedScene", "add_child(", "Node.new(", "Node2D.new(",
		"create_timer(", "Timer.new(", "await ", "get_tree()", "Time.get_",
		"load(\"res://scenes", "Input.", "DisplayServer", "randf", "randi",
	]
	for token in forbidden:
		_check(failures, source.find(token) == -1,
			"ftue_flow.gd has no node/timer/engine-time/randomness API: %s" % token)
	_check(failures, source.find("func _initialize") == -1,
		"ftue_flow.gd defines no _initialize(): the smoke run must not do work before _process()")
