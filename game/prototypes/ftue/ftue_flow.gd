class_name FtueFlow
extends MainLoop
## Wave 1, wayfinder ticket #12: pure-logic first-minute FTUE beat sequence
## (binding contract: docs/prototypes/CONTRACTS-ftue.md). NO nodes, NO scene
## deps, NO timers of its own — the host feeds `tick(delta)` and owns every
## rendering decision, every rival/progression rule and every asset. Construct
## with no arguments and drive it entirely through the methods below; `beat`
## is read-only for consumers — only `_set_beat()` in this file assigns it.
##
## Beat sequence (taps are host taps; the FTUE itself requires none)
## -----------------------------------------------------------------
##   start_first_minute(mode, ruleset)
##     mode == "solo"        -> RIVAL_CHOICE
##     else ruleset == "pen_powers" -> TRADEOFF
##     else                  -> TEACH
##
##   RIVAL_CHOICE --skip()/idle--> TRADEOFF (pen_powers) | TEACH (classic)
##   TRADEOFF     --on_tradeoff_acknowledged()--> TEACH      [sticky on idle]
##   TEACH        --skip()/idle--> FIRST_SHOT                [dies on any drag]
##   FIRST_SHOT   --on_first_shot_committed()--> PLAY        [sticky on idle]
##   ANY beat     --on_drag_started()--> PLAY
##   ANY teach beat --skip()--> PLAY
##
## Every beat is a NON-GATING overlay on a live AIM turn: the player can grab
## the pen and flick at any moment in any beat, and doing so clears the beat
## (CONTRACTS-ftue.md: "no beat may be required to complete before the player
## can drag"). Nothing in this module can lock input, because it never owns
## input — see the invariants block below.
##
## Pinned invariants (each one test-enforced by ftue_flow_test.gd)
## --------------------------------------------------------------
##  1. `start_first_minute("hot_seat", ...)` never enters RIVAL_CHOICE; "solo"
##     may (and does, as its first beat).
##  2. A teach beat can never block a legal flick: `on_drag_started()` clears
##     the teach immediately, from any beat, and it never re-arms within the
##     same player turn. Re-arming is impossible by construction: the only
##     call that arms a beat is `start_first_minute()`, and that is the host's
##     turn/rematch boundary. `tick()` is guarded by `_grabbed`.
##  3. No beat other than PLAY may be active once `on_first_shot_committed()`
##     has fired (double-flick included).
##  4. TRADEOFF appears only when `ruleset == "pen_powers"`. Any other string —
##     including near-misses like "Pen Powers" or "pen powers" — resolves to
##     Classic and cannot produce a TRADEOFF beat.
##  5. Launch-to-first-flick budget: <= 3 taps from BOOT to a live AIM turn,
##     and the FTUE's own required-tap cost is 0
##     (`TAPS_REQUIRED_BEFORE_FIRST_FLICK`). The three taps are the app flow's
##     (BOOT -> HOME -> MODE -> live AIM, docs/prototypes/app-flow/FLOW.md);
##     this module adds none.
##
## Why `extends MainLoop` and not `extends RefCounted`
## ---------------------------------------------------
## The pinned gate runs this file directly:
##   godot --headless --path game --script res://prototypes/ftue/ftue_flow.gd
## and requires exit 0 with no script errors. Godot only accepts a file in
## that position if it can serve as a main loop: `RefCounted` fails with
## "Can't load the script ... as it doesn't inherit from SceneTree or
## MainLoop" (exit 1 — measured, Wave 1 probe). MainLoop is a bare Object: it
## creates no Window and touches no scene tree, unlike SceneTree, so the
## module stays exactly what the contract asks for (pure logic, no nodes, no
## scene deps). It is never initialized as a main loop by any consumer — the
## test preloads it and calls `.new()`. `_process()` exists only so the
## smoke-run exits 0 on its first frame instead of looping forever, and it
## never touches `beat`. MainLoop is not reference-counted, so ftue_flow_test
## frees every instance it creates.

## The pinned beat set, in pinned order (CONTRACTS-ftue.md).
enum Beat { TEACH, FIRST_SHOT, RIVAL_CHOICE, TRADEOFF, PLAY }

## Emitted only when `beat` actually changes value (a no-op call emits nothing).
signal beat_changed(from: Beat, to: Beat)

## Game Mode tokens (CONTEXT.md: Game Mode and Ruleset are different axes).
const MODE_HOT_SEAT := "hot_seat"
const MODE_SOLO := "solo"
## Ruleset tokens (CONTEXT.md: Classic is the default Ruleset).
const RULESET_CLASSIC := "classic"
const RULESET_PEN_POWERS := "pen_powers"

## Pinned budget: BOOT -> a live AIM turn in <= 3 taps (CONTRACTS-ftue.md).
const TAP_BUDGET_BOOT_TO_LIVE_AIM := 3
## The FTUE's own required-tap cost before a legal flick. Zero by design:
## every beat is a non-gating overlay on an already-live AIM turn.
const TAPS_REQUIRED_BEFORE_FIRST_FLICK := 0
## Seconds of *no input at all* before a non-gating card relaxes into the next
## cue. 4 s: short enough that the first minute keeps moving for a player who
## is reading rather than tapping, long enough that it never fires while
## someone is mid-thought. It does NOT gate anything — the drag path stays
## live for the whole dwell, and the drag cancels the timer's effect for the
## rest of the turn.
const IDLE_ADVANCE_SECONDS := 4.0
## Cue strings are capped so no layout can be handed a string that cannot fit
## the logical viewport (prompt/label fit rule, commit 4573676:
## `window/stretch/aspect = keep_height`, so a tall phone's logical width is
## well under 1280 — never assume 1280 and never hardcode a pixel width).
const MAX_CUE_CHARS := 48

const CUE_TEACH := "GRAB THE PEN - PULL BACK - LET GO"
const CUE_FIRST_SHOT := "FIRST FLICK - PULL BACK, LET GO"
const CUE_RIVAL_CHOICE := "PICK YOUR RIVAL"
const CUE_TRADEOFF := "PEN POWERS - READ YOUR PEN'S TRADEOFF"

## Read-only for consumers: only `_set_beat()` below assigns it. PLAY doubles
## as the resting value meaning "no first-minute beat is active".
var beat: Beat = Beat.PLAY

var _mode: String = MODE_HOT_SEAT
var _ruleset: String = RULESET_CLASSIC
## True from start_first_minute() until the host starts a new first minute;
## it only gates tick()/visible_cue(), never the drag path.
var _running: bool = false
## True once the player has grabbed the pen this first minute. Guarantees the
## idle timer can never re-arm or advance a teach the player is already acting
## on ("never re-arms within the same player turn").
var _grabbed: bool = false
var _first_shot_committed: bool = false
var _dwell: float = 0.0
var _smoke_reported: bool = false


## Begin (or restart) the first minute. Called by the host at the moment the
## player commits to a Game Mode — the same tap that enters the live AIM turn
## (see CONTRACTS-ftue.md tap budget). Both arguments are host-supplied; this
## module stores them only to pick the beat chain and never renders, scores or
## persists anything from them.
##
## Unknown/free-form values resolve to the safe defaults (Hot Seat / Classic)
## rather than erroring, which is what keeps invariants 1 and 4 strict: no
## unrecognised string can smuggle in RIVAL_CHOICE or TRADEOFF.
func start_first_minute(mode: String, ruleset: String) -> void:
	_mode = _normalize_mode(mode)
	_ruleset = _normalize_ruleset(ruleset)
	_running = true
	_grabbed = false
	_first_shot_committed = false
	_dwell = 0.0
	_set_beat(_first_beat())


## The inline teach dies the instant the player grabs the pen — from any beat,
## including the pre-flick cards, and even if the beat is already PLAY (the
## grab is always honoured, so a host can call this unconditionally on
## pointer-down). Never re-arms: see invariant 2.
func on_drag_started() -> void:
	_grabbed = true
	_dwell = 0.0
	if beat != Beat.PLAY:
		_set_beat(Beat.PLAY)


## The first flick of the session has been committed. This is the end of the
## first minute as far as the FTUE is concerned: only PLAY may remain, and a
## second call (double-flick) is a strict no-op. The module never inspects the
## flick's result — the physical result is authoritative (CONTEXT.md, Flick).
func on_first_shot_committed() -> void:
	_first_shot_committed = true
	_grabbed = true
	_dwell = 0.0
	if beat != Beat.PLAY:
		_set_beat(Beat.PLAY)


## TRADEOFF -> TEACH, and only from TRADEOFF. The tradeoff card is the one
## beat that waits for an explicit acknowledgement instead of relaxing on
## idle, because it is the pre-flick disclosure of both pens' fixed, visible
## strengths and costs (docs/prototypes/pen-profiles/DECISION.md). It is not a
## gate either: a drag is honoured from TRADEOFF like from every other beat,
## and skip() dismisses the card.
func on_tradeoff_acknowledged() -> void:
	if beat != Beat.TRADEOFF:
		return
	_dwell = 0.0
	_set_beat(_next_after(Beat.TRADEOFF))


## One-tap dismiss. From a teach beat (TEACH / FIRST_SHOT) it is the escape
## the contract pins: the rest of the first minute is cancelled and the module
## rests in PLAY. From a pre-flick card (RIVAL_CHOICE / TRADEOFF) it dismisses
## that card and moves to the next beat — the pinned API has no other method
## that can clear those two, and a card that could not be dismissed by tap
## would be the gate this contract forbids. From PLAY it is a strict no-op
## (no signal), so a host may wire one "SKIP" control unconditionally.
func skip() -> void:
	if beat == Beat.PLAY:
		return
	_dwell = 0.0
	match beat:
		Beat.TEACH, Beat.FIRST_SHOT:
			_set_beat(Beat.PLAY)
		_:
			_set_beat(_next_after(beat))


## Idle / auto-advance only. Never blocks input, never moves a beat the player
## is already acting on, and never re-arms a teach. Advances at most ONE beat
## per call, so a stalled host frame can never fast-forward the whole first
## minute. Non-positive deltas are ignored (a paused host may feed 0.0).
##
## TEACH -> FIRST_SHOT and RIVAL_CHOICE -> next relax on idle. FIRST_SHOT waits
## for the real flick and TRADEOFF waits for its acknowledgement: both are
## sticky, and neither can strand the player because the drag is live
## throughout.
func tick(delta: float) -> void:
	if not _running or delta <= 0.0:
		return
	if beat == Beat.PLAY or _grabbed:
		return
	_dwell += delta
	if _dwell < IDLE_ADVANCE_SECONDS:
		return
	_dwell = 0.0
	match beat:
		Beat.TEACH, Beat.RIVAL_CHOICE:
			_set_beat(_next_after(beat))
		_:
			pass


## The single line of FTUE copy the host may show for the current beat — ""
## when nothing should be shown (PLAY, or before the first minute starts). The
## host owns placement, type scale and the actual card body; this is the cue
## string only, capped at MAX_CUE_CHARS so it can always fit a computed
## viewport width.
func visible_cue() -> String:
	if not _running:
		return ""
	match beat:
		Beat.TEACH:
			return CUE_TEACH
		Beat.FIRST_SHOT:
			return CUE_FIRST_SHOT
		Beat.RIVAL_CHOICE:
			return CUE_RIVAL_CHOICE
		Beat.TRADEOFF:
			return CUE_TRADEOFF
		_:
			return ""


## Engine main-loop hook, present ONLY so that the pinned smoke gate
## (`--script res://prototypes/ftue/ftue_flow.gd`) exits 0 on its first frame
## instead of spinning forever. No consumer runs this module as a main loop,
## and this function never reads or writes the beat. See the class doc comment.
func _process(_delta: float) -> bool:
	if not _smoke_reported:
		_smoke_reported = true
		print("ftue_flow: load smoke OK (beat=%s, cue=%s)" % [Beat.keys()[beat], visible_cue()])
	return true


func _set_beat(to: Beat) -> void:
	if to == beat:
		return
	var from := beat
	beat = to
	## Every beat change restarts the idle dwell: each card gets its own full
	## window, and an idle timer can never accumulate across cards.
	_dwell = 0.0
	beat_changed.emit(from, to)


func _first_beat() -> Beat:
	if _mode == MODE_SOLO:
		return Beat.RIVAL_CHOICE
	if _ruleset == RULESET_PEN_POWERS:
		return Beat.TRADEOFF
	return Beat.TEACH


func _next_after(current: Beat) -> Beat:
	match current:
		Beat.RIVAL_CHOICE:
			return Beat.TRADEOFF if _ruleset == RULESET_PEN_POWERS else Beat.TEACH
		Beat.TRADEOFF:
			return Beat.TEACH
		Beat.TEACH:
			return Beat.FIRST_SHOT
		_:
			return Beat.PLAY


## Exact-token resolution after lowercasing and trimming whitespace. Anything
## unrecognised falls back to the safe default (Hot Seat / Classic).
func _normalize_mode(mode: String) -> String:
	var m := mode.strip_edges().to_lower()
	return MODE_SOLO if m == MODE_SOLO else MODE_HOT_SEAT


func _normalize_ruleset(ruleset: String) -> String:
	var r := ruleset.strip_edges().to_lower()
	return RULESET_PEN_POWERS if r == RULESET_PEN_POWERS else RULESET_CLASSIC
