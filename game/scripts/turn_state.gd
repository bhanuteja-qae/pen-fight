class_name TurnState
extends RefCounted
## Pure-logic turn state machine for pen-fight (Phase 0.5).
##
## NO Node2D / scene-tree / physics dependencies: construct with plain data
## (pens as Array of String, forfeit_timeout in seconds, table_rect as Rect2)
## so the class can be unit-tested headless without an engine scene.
##
## Win resolution happens HERE, geometrically, BEFORE any ceremony
## (docs/RESEARCH.md §3.2): the round's outcome is decided the moment a pen
## goes out of bounds (`on_out_of_bounds`); presentation afterwards is pure
## decoration over an already-settled result. A settle with both pens still on
## the table only advances the turn to the next player (`on_settled` ->
## `begin_turn`).
##
## Contract phases: AIM, IN_FLIGHT, SETTLED, FORFEIT, GAME_OVER, ROUND_OVER.
## Decided rounds (OOB winner or forfeit) PARK in PHASE_ROUND_OVER — nothing
## auto-advances; Main shows the tap-to-continue gate and calls
## continue_to_next_round() to start the next round (winner first).

# Phase constants (contract: phase in {AIM, IN_FLIGHT, SETTLED, FORFEIT, GAME_OVER, ROUND_OVER}).
const PHASE_AIM: String = "AIM"
const PHASE_IN_FLIGHT: String = "IN_FLIGHT"
const PHASE_SETTLED: String = "SETTLED"
const PHASE_FORFEIT: String = "FORFEIT"
const PHASE_GAME_OVER: String = "GAME_OVER"
const PHASE_ROUND_OVER: String = "ROUND_OVER"

var _pens: Array[String] = []
var _forfeit_timeout: float = 5.0
var _table_rect: Rect2 = Rect2()

var _current_index: int = -1
var _phase: String = PHASE_AIM
var _forfeit_elapsed: float = 0.0
var _flicked_pen: String = ""
var _last_impulse: Vector2 = Vector2.ZERO
var _settled_pen_uids: Array[String] = []
## Pens that exceeded MOVED_LINEAR_VEL during the current flight (PenBody.moved).
## Emptied each turn; used by the stalemate rule (docs/ART_AND_FEEL_SPEC.md §7):
## a settled turn where NO pen moved is a forfeit, not a clean hand-over.
## NOTE (review, QA-4): with the shipped input, the weakest legal flick
## (min_drag 15/160 -> power 0.094 -> ~140 px/s) already clears MOVED_LINEAR_VEL
## (25 px/s), so the stalemate forfeit is NOT reachable through human input —
## it exists as a scripted/edge-case backstop. The real anti-stall mechanism is
## the no-input idle forfeit (main.gd FORFEIT_TIMEOUT). Do not delete this rule
## (it still protects scripted zero-power flights), do not claim it is the
## primary anti-stall.
var _moved_pen_uids: Array[String] = []
## Pens that reported out-of-bounds THIS flight (PenBody.out_of_bounds).
## Buffered (instead of deciding on the first event) so a same-tick double-OOB
## sees BOTH pens: when both leave the table the FLICKER loses regardless of
## event order (review, QA-3). Resolved once per frame by resolve_pending_oob().
var _oob_pending: Array[String] = []
## In-flight hard backstop (spec §7: "the backstop that makes the other two
## safe"). A settling/creeping pen may never settle (engine sleep disabled), so
## IN_FLIGHT must resolve on a hard clock. [TUNE]
const RESOLVE_TIMEOUT := 8.0
var _resolve_elapsed: float = 0.0
var _winner_uid: String = ""
var _loser_uid: String = ""
var _round_over: bool = false
## True when the CURRENT parked round was decided by an OOB verdict (vs a
## forfeit/backstop). Lets Main pick the impact ceremony strength after
## resolution; cleared each turn.
var _decided_by_oob: bool = false

## pens: list of pen UIDs, e.g. ["red", "blue"]. Stored as String.
## forfeit_timeout: seconds the active player has to flick before the round is
##   forfeit (docs: 4-6 s hard timeout; game default 15 s — tune at playtest).
## table_rect: table geometry in world units (defaults to an empty Rect2()).
##   Kept pure (Rect2 is a Variant type — no scene dependency). The state
##   machine's win rule (flicked pen OOB -> other player wins) is event-driven
##   from PenBody; table_rect is exposed in state() for the debug overlay and
##   usable via is_outside_table() for defensive geometric checks.
func _init(pens: Array, forfeit_timeout: float = 5.0, table_rect: Rect2 = Rect2()) -> void:
	_pens.clear()
	for pen in pens:
		_pens.append(str(pen))
	if _pens.is_empty():
		print("TurnState: constructed with an empty pens list")
	_forfeit_timeout = maxf(forfeit_timeout, 0.0)
	_table_rect = table_rect
	_phase = PHASE_AIM

## Start (or restart) a round: advance to the next player, phase -> AIM, clear
## round bookkeeping. First call gives the first pen; each later call cycles.
func begin_turn() -> void:
	if _pens.is_empty():
		return
	_current_index = (_current_index + 1) % _pens.size()
	_phase = PHASE_AIM
	_forfeit_elapsed = 0.0
	_flicked_pen = ""
	_last_impulse = Vector2.ZERO
	_settled_pen_uids = []
	_moved_pen_uids = []
	_oob_pending = []
	_resolve_elapsed = 0.0
	_winner_uid = ""
	_loser_uid = ""
	_round_over = false
	_decided_by_oob = false

## Round-over gate (docs §3.5 #1): the ONLY way out of PHASE_ROUND_OVER.
## Caller (Main's tap-to-continue) invokes this after a decided round. The
## winner starts the next round: begin_turn() cycles to the next player (the
## round winner when the starter lost, which is the hot-seat convention) and
## clears the round-over bookkeeping. Any other phase is a no-op.
func continue_to_next_round() -> void:
	if _phase != PHASE_ROUND_OVER:
		return
	begin_turn()


## True when the current parked round was decided by an OOB verdict rather than
## a forfeit/backstop (drives which ceremony strength Main plays).
func decided_by_oob() -> bool:
	return _decided_by_oob

## The active player flicked. Valid only during AIM -> transitions to
## IN_FLIGHT. Records the impulse and marks the flicked pen (the active
## player's pen). The non-flicked pen is at rest and stays on the table, so it
## is seeded as already "settled"; the flicked pen settling closes the round.
func on_flick(impulse: Vector2) -> void:
	if _phase != PHASE_AIM:
		return
	_phase = PHASE_IN_FLIGHT
	_flicked_pen = current_player()
	_last_impulse = impulse
	_forfeit_elapsed = 0.0
	_resolve_elapsed = 0.0
	_settled_pen_uids.clear()
	_moved_pen_uids.clear()
	_oob_pending.clear()
	for pen in _pens:
		if pen != _flicked_pen:
			_settled_pen_uids.append(pen)

## A pen exceeded MOVED_LINEAR_VEL during this flight (PenBody.moved). Records
## it so the all-settled verdict can distinguish a real exchange from a
## stalemate. No-op outside IN_FLIGHT and for duplicate / unknown pens.
func on_pen_moved(pen_uid: String) -> void:
	if _phase != PHASE_IN_FLIGHT:
		return
	if _moved_pen_uids.has(pen_uid):
		return
	_moved_pen_uids.append(pen_uid)

## A pen came to rest on the table (PenBody.settled). Once BOTH pens are
## settled the round resolves as "still on the table": a REAL exchange (any
## pen moved) advances to the next player's turn; a STALEMATE (no pen moved)
## forfeits the round to the other player (docs/ART_AND_FEEL_SPEC.md §7) —
## otherwise a player could tickle-flick every timeout period and stall the
## game forever. Duplicate / stale events and events outside IN_FLIGHT ignored.
func on_settled(pen_uid: String) -> void:
	if _phase != PHASE_IN_FLIGHT:
		return
	if _settled_pen_uids.has(pen_uid):
		return  # duplicate settle for an already-settled pen
	_settled_pen_uids.append(pen_uid)
	if _all_pens_settled():
		_phase = PHASE_SETTLED
		if _moved_pen_uids.is_empty():
			# Stalemate: the flick moved nothing. The flicking player forfeits
			# the round (same winner/loser shape as the timeout forfeit).
			_phase = PHASE_ROUND_OVER
			_round_over = true
			_loser_uid = _flicked_pen
			_winner_uid = _other_player(_flicked_pen)
		else:
			begin_turn()

## A pen left the table (PenBody.out_of_bounds). Buffers the event instead of
## deciding immediately: both pens can leave in the SAME physics tick, and the
## rule for that tie is "the FLICKER loses" regardless of which event arrives
## first (review QA-3). resolve_pending_oob() (called once per frame by Main)
## decides the round after all same-tick events have arrived. Events outside
## IN_FLIGHT are ignored so a decided round cannot be re-decided.
func on_out_of_bounds(pen_uid: String) -> void:
	if _phase != PHASE_IN_FLIGHT:
		return
	if _oob_pending.has(pen_uid):
		return  # duplicate event for an already-buffered pen
	_oob_pending.append(pen_uid)

## Resolve the round from buffered OOB events. Called by Main once per frame
## AFTER the physics tick, so every OOB event from that tick has arrived.
## Decision: both pens off the table -> the FLICKER loses (tie rule); exactly
## one pen off -> that pen's player loses (the other wins). Parks in
## ROUND_OVER. No-op when there is nothing pending.
func resolve_pending_oob() -> void:
	if _phase != PHASE_IN_FLIGHT:
		return
	if _oob_pending.is_empty():
		return
	_phase = PHASE_ROUND_OVER
	_round_over = true
	_decided_by_oob = true
	if _oob_pending.size() >= 2:
		# Both pens left the table in the same tick: the flicker loses.
		_loser_uid = _flicked_pen
		_winner_uid = _other_player(_flicked_pen)
	elif _oob_pending.has(_flicked_pen):
		_loser_uid = _flicked_pen
		_winner_uid = _other_player(_flicked_pen)
	else:
		_loser_uid = _oob_pending[0]
		_winner_uid = _flicked_pen

## In-flight hard backstop (spec §7). Main calls this each frame while the
## round is unresolved; after RESOLVE_TIMEOUT seconds in IN_FLIGHT the round is
## forced to a verdict: OOB events win if any happened; otherwise a moved pen
## hands over to the next player; a never-moved flight is a stalemate forfeit.
## This replaces the "blank IN_FLIGHT hang" failure mode (a creeping pen can
## never satisfy the settle detector because engine sleep is disabled).
func resolve_tick(delta: float) -> void:
	if _phase != PHASE_IN_FLIGHT:
		return
	_resolve_elapsed += maxf(delta, 0.0)
	if _resolve_elapsed < RESOLVE_TIMEOUT:
		return
	if not _oob_pending.is_empty():
		resolve_pending_oob()
		return
	if _moved_pen_uids.is_empty():
		# Stalemate under the backstop: the flight never meaningfully moved.
		_phase = PHASE_ROUND_OVER
		_round_over = true
		_loser_uid = _flicked_pen
		_winner_uid = _other_player(_flicked_pen)
	else:
		begin_turn()

## Hard forfeit timeout (docs: 4-6 s). Called by Main each frame; accumulates
## delta only while a turn is in AIM. Once the active player has not flicked
## within forfeit_timeout, the OTHER player wins the round and the state parks
## in PHASE_ROUND_OVER (no auto-advance; Main's gate resumes on tap).
func forfeit_tick(delta: float) -> void:
	if _phase != PHASE_AIM:
		return
	_forfeit_elapsed += maxf(delta, 0.0)
	if _forfeit_elapsed >= _forfeit_timeout:
		_phase = PHASE_ROUND_OVER
		_round_over = true
		_loser_uid = current_player()
		_winner_uid = _other_player(current_player())

## UID of the active (current) player, or "" if no turn has begun.
func current_player() -> String:
	if _pens.is_empty() or _current_index < 0:
		return ""
	return _pens[_current_index]

## Defensive geometric helper: is a world-space point off the table?
## Only meaningful when a non-empty table_rect was passed at construction.
func is_outside_table(pos: Vector2) -> bool:
	return not _table_rect.has_point(pos)

func _all_pens_settled() -> bool:
	for pen in _pens:
		if not _settled_pen_uids.has(pen):
			return false
	return true

func _other_player(pen_uid: String) -> String:
	for pen in _pens:
		if pen != pen_uid:
			return pen
	return ""

## Serializable snapshot for the debug overlay + tests. All values are Variant
## types (String / float / int / bool / Vector2 / Rect2 / Array) safe for a
## Dictionary passed across scripts or to a HUD.
func state() -> Dictionary:
	return {
		"pens": _pens,
		"current_player": current_player(),
		"player_index": _current_index,
		"phase": _phase,
		"forfeit_timeout": _forfeit_timeout,
		"forfeit_elapsed": _forfeit_elapsed,
		"flicked_pen": _flicked_pen,
		"last_impulse": _last_impulse,
		"settled_pens": _settled_pen_uids,
		"moved_pens": _moved_pen_uids,
		"oob_pending": _oob_pending,
		"resolve_elapsed": _resolve_elapsed,
		"winner": _winner_uid,
		"loser": _loser_uid,
		"round_winner": _winner_uid,
		"round_over": _round_over,
		"table_rect": _table_rect,
	}
