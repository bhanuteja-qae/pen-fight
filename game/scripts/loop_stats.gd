class_name LoopStats
extends RefCounted
## Session-cumulative tally of HOW each round was decided, plus the flick count.
##
## Why this exists: the core-loop re-check (docs/design/core-loop.md) found the
## loop's biggest unknown is invisible in the build — how often a round is
## decided by a collision (knockout / self-OOB) versus ending by itself
## (stalemate / idle forfeit / in-flight backstop). The Phase-1 human playtest
## gate can only answer "is this fun?" with numbers if the build reports them, so
## every decided round is recorded here and printed as ONE `[LOOP]` line at match
## over. Cumulative for the session on purpose: a best-of-3 match is too short to
## read on its own, so the LAST line of a playtest session is the session total.
##
## Pure logic — no Node, no scene tree, no physics — so it unit-tests headless
## (game/tests/loop_attribution_test.gd). Vocabulary matches TurnState's
## DECIDED_BY_* constants AND the prototype harness attribution
## (docs/prototypes/policy-bot/RIVAL-MATRIX.md) so shipped logs and prototype
## evidence are directly comparable.

## The known outcomes, in report order.
const KEYS: Array[String] = ["knockout", "self_oob", "stalemate", "idle", "backstop"]

var _rounds: int = 0
var _flicks: int = 0
var _counts: Dictionary = {}

func _init() -> void:
	for key in KEYS:
		_counts[key] = 0

## One decided round, by TurnState.DECIDED_BY_* value. An unrecognised value is
## counted under its own key rather than dropped, so a future TurnState outcome
## can never be silently invisible in the report.
func record_round(decided_by: String) -> void:
	var key: String = decided_by if not decided_by.is_empty() else "unknown"
	_counts[key] = int(_counts.get(key, 0)) + 1
	_rounds += 1

## One ACCEPTED shot (Main._submit_shot, after every validation passed).
## Shots per round is the loop's pacing number: many shots is the long exchange
## the design wants, one shot is the self-OOB case.
func record_flick() -> void:
	_flicks += 1

func rounds() -> int:
	return _rounds

func flicks() -> int:
	return _flicks

func count(decided_by: String) -> int:
	return int(_counts.get(decided_by, 0))

## Rounds a collision decided (either pen leaving the table) — the "did the
## physics decide it?" numerator.
func resolved_by_contact() -> int:
	return count("knockout") + count("self_oob")

## Share of decided rounds a collision decided. 0.0 before the first round.
func contact_share() -> float:
	if _rounds <= 0:
		return 0.0
	return float(resolved_by_contact()) / float(_rounds)

## Shots per decided round. 0.0 before the first round.
func shots_per_round() -> float:
	if _rounds <= 0:
		return 0.0
	return float(_flicks) / float(_rounds)

## Plain-data snapshot (Variant types only) for tests and the debug overlay.
func summary() -> Dictionary:
	var counts: Dictionary = {}
	for key in _counts.keys():
		counts[key] = int(_counts[key])
	return {
		"rounds": _rounds,
		"flicks": _flicks,
		"shots_per_round": shots_per_round(),
		"counts": counts,
		"contact": resolved_by_contact(),
		"contact_share": contact_share(),
	}

## The one line a playtest session is read from. Grep-able prefix, no prose.
func to_line() -> String:
	return "[LOOP] rounds=%d flicks=%d shots/round=%.2f knockout=%d self_oob=%d stalemate=%d idle=%d backstop=%d contact=%d (%.0f%%)" % [
		_rounds, _flicks, shots_per_round(),
		count("knockout"), count("self_oob"), count("stalemate"), count("idle"), count("backstop"),
		resolved_by_contact(), contact_share() * 100.0,
	]
