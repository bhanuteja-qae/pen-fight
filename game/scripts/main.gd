extends Node2D
class_name Main
## Phase 1b wiring controller for pen-fight (turn-transition gate, ceremony
## skip, debug autoplay harness). Extended from the Phase 1a feel layer.
##
## Owns no physics. Per the build contract it only connects:
##   AimInput.flick_ready(dir, power) -> TurnState.on_flick -> active PenBody.apply_flick
##   PenBody.settled            -> TurnState.on_settled
##   PenBody.out_of_bounds      -> TurnState.on_out_of_bounds
## and prints a verdict line once a round is decided (ROUND_OVER).
## Phase 1a adds: Feel (trauma shake + hit-stop) and DebugOverlay (debug-build
## contact/velocity text), both driven from here AFTER TurnState decides.
## Phase 1b adds: the hard turn-transition gate (docs §3.5 #1) — TurnGate is a
## full-screen tap-to-continue CanvasLayer overlay driven by Main. The gate
## shows once per turn handoff ("<Player>'s turn — tap to continue") after a
## settle auto-advances to the next player, and once per decided round
## ("<Winner> wins — tap to restart"). While the gate is up, _input_locked
## blocks _on_flick_ready so a player can never flick on the wrong turn. The
## ceremony stays post-decision and is skippable on tap (docs §3.5 #7). Debug
## builds with PENFIGHT_AUTOPLAY=1 arm Agent B's AutoFlick to drive rounds
## headlessly.

@onready var pen_red: PenBody = $PenRed as PenBody
@onready var pen_blue: PenBody = $PenBlue as PenBody

var turn_state: TurnState = null
var aim_input: AimInput = null

## Phase 1a feel layer + debug overlay (Agent B).
var feel: Feel = null
var overlay: DebugOverlay = null

## Hard turn-transition gate overlay (docs §3.5 #1): created in _ready and
## driven from here. Self-contained CanvasLayer — no TurnState/PenBody refs.
var turn_gate: TurnGate = null
## Debug autoplay harness (AutoFlick), created only in debug builds with
## PENFIGHT_AUTOPLAY=1. Kept as a member so a re-armed round can schedule the
## next flick after the gate tap restarts the game.
var _auto_flick: AutoFlick = null
## True while the gate is up: _on_flick_ready ignores all flicks, so a player
## can never flick on the wrong turn or mid-handoff.
var _input_locked: bool = false
## Guards the gate against double-showing (once per turn handoff / decided round).
var _gate_showing: bool = false
## The player whose current turn has already been gated+acknowledged. The gate
## re-appears only when a NEW player's AIM turn begins (settle auto-advance).
var _acknowledged_player: String = ""

var _game_over_printed: bool = false
## Guards the ceremony (shake/hit-stop) so it fires exactly once per decided
## round, no matter which path decided it (OOB or forfeit).
var _ceremony_fired: bool = false

const FORFEIT_TIMEOUT: float = 4.0
## World-space table rect; must match the Table node geometry in main.tscn.
const TABLE_RECT: Rect2 = Rect2(-512.0, -256.0, 1024.0, 512.0)


func _ready() -> void:
	turn_state = TurnState.new([pen_red.pen_id, pen_blue.pen_id], FORFEIT_TIMEOUT, TABLE_RECT)
	aim_input = AimInput.new()
	add_child(aim_input)
	aim_input.flick_ready.connect(_on_flick_ready)

	for pen: PenBody in [pen_red, pen_blue]:
		pen.settled.connect(turn_state.on_settled)
		pen.out_of_bounds.connect(turn_state.on_out_of_bounds)
		# Connected AFTER the TurnState resolver above so this handler always
		# runs once the win outcome is already decided (docs §3.2) — the
		# ceremony below is a reaction to a settled result, never part of
		# resolution.
		pen.out_of_bounds.connect(_on_out_of_bounds)

	feel = Feel.new()
	add_child(feel)
	overlay = DebugOverlay.new()
	add_child(overlay)
	overlay.set_pens([pen_red, pen_blue])

	# Hard turn-transition gate (docs §3.5 #1): a CanvasLayer drawn above the
	# world but below the debug overlay. Mouse taps are handled by the gate
	# itself; Main reacts to `tapped`.
	turn_gate = TurnGate.new()
	add_child(turn_gate)
	turn_gate.tapped.connect(_on_gate_tapped)

	# Debug autoplay harness (Agent B's AutoFlick): headless multi-round driver
	# for the orchestrator. Debug build + PENFIGHT_AUTOPLAY=1 only — never in
	# normal play. Agent B implements the class; this hook uses its contract API.
	if OS.is_debug_build() and OS.get_environment(&"PENFIGHT_AUTOPLAY") == "1":
		_auto_flick = AutoFlick.new()
		add_child(_auto_flick)
		_auto_flick.setup(self)
		# Knockout-scale impulses, not human power [0,1]: impulse 1 -> ~1 px/s
		# (measured via tests/impulse_probe.gd), so human-scale flicks can never
		# leave the table and autoplay rounds stall at the turn gate. 2e4..1.2e5
		# gives 20k..120k px/s — reliably off-table in a few physics frames.
		_auto_flick.set_random_power(20000.0, 120000.0, randi())
		# Contract wiring (phase1b-contract §Agent F): Main connects the signal
		# and handles it exactly like _on_flick_ready minus the drag math. The
		# harness only emits; without this connection autoplay flicks are inert
		# (rounds would resolve by forfeit, never by knockout).
		_auto_flick.auto_flick_requested.connect(_on_auto_flick_requested)
		_auto_flick.arm(1.2)

	turn_state.begin_turn()
	# The very first turn is the game opening, not a settle handoff — the gate
	# would be noise here, and the no-input forfeit acceptance path needs the
	# first AIM turn to tick its timer (a gated first turn would pause forfeit
	# forever). Pre-acknowledge the starting player so no gate shows yet.
	_acknowledged_player = turn_state.current_player()


func _process(delta: float) -> void:
	# Feel layer ticks every frame regardless of turn_state state, so the
	# hit-stop frame counter always completes and trauma never freezes mid-shake.
	if feel != null:
		feel.process_frame(delta)
	if turn_state == null:
		return
	# Forfeit clock runs only while the gate is NOT up: a settle handoff gate
	# ("<Player>'s turn — tap") must not burn the next player's timeout while
	# they are being asked to tap-to-continue.
	if not _gate_showing:
		turn_state.forfeit_tick(delta)
	var st: Dictionary = turn_state.state()
	var phase: String = str(st.get("phase", ""))
	# Hard turn-transition gate: input is locked outside AIM so a player can
	# never flick on the wrong turn; the gate overlay drives the handoff.
	aim_input.input_locked = phase != TurnState.PHASE_AIM
	if not _gate_showing:
		_update_gate(st, phase)
	if phase == TurnState.PHASE_AIM:
		_sync_aim_zone()
	_check_game_over()


## TurnGate input: a mouse tap anywhere dismisses the gate and resumes. The F
## key does the same (ceremony skip, docs §3.5 #7), preserving the pre-gate
## behavior. Mouse events are handled by TurnGate's own _unhandled_input, so
## this only forwards the keyboard path.
func _unhandled_input(event: InputEvent) -> void:
	if turn_state == null or not _gate_showing:
		return
	if event is InputEventKey:
		var kb: InputEventKey = event
		if kb.pressed and (kb.keycode == KEY_F or kb.physical_keycode == KEY_F):
			get_viewport().set_input_as_handled()
			_on_gate_tapped()


func _on_flick_ready(direction: Vector2, power: float) -> void:
	# Gate: never apply a flick while the turn-transition gate is up, even if
	# the phase is AIM (a settle handoff waits for the tap-to-continue).
	if _input_locked:
		return
	if turn_state == null:
		return
	# AimInput is locked when not AIM, so this is defensive — but on_flick()
	# no-ops while locked/ROUND_OVER and the pen must not get an impulse either.
	if str(turn_state.state().get("phase", "")) != TurnState.PHASE_AIM:
		return
	# AimInput gives a slingshot pull vector (direction + power). TurnState
	# records the impulse; the active pen receives direction+power for physics.
	turn_state.on_flick(direction * power)
	var pen := _active_pen()
	if pen != null:
		pen.apply_flick(direction, power)


func _active_pen() -> PenBody:
	match turn_state.state().get("current_player", ""):
		"red":
			return pen_red
		"blue":
			return pen_blue
		_:
			return null


## AutoFlick.auto_flick_requested -> this. Mirrors _on_flick_ready minus the
## slingshot drag math: AutoFlick already emits a full direction*power impulse.
## Duplicate-routing guard: the same AIM/current-player checks as the human
## path, so even if another consumer also connected the signal, exactly one
## application can land.
func _on_auto_flick_requested(player: String, impulse: Vector2) -> void:
	if _input_locked:
		return
	if turn_state == null:
		return
	var st: Dictionary = turn_state.state()
	if str(st.get("phase", "")) != TurnState.PHASE_AIM:
		return
	if str(st.get("current_player", "")) != player:
		return
	turn_state.on_flick(impulse)
	var pen := _active_pen()
	if pen != null:
		pen.apply_flick(impulse.normalized(), impulse.length())


## Keep AimInput's drag zone centered on the active pen each AIM frame.
func _sync_aim_zone() -> void:
	var pen := _active_pen()
	if pen != null:
		aim_input.set_active_zone(pen.global_position, 110.0)


## Fired by PenBody.out_of_bounds AFTER TurnState.on_out_of_bounds has already
## resolved the winner geometrically (docs §3.2) — connection order guarantees
## this. The ceremony is a reaction to the DECIDED outcome, never part of it.
func _on_out_of_bounds(_pen_uid: String) -> void:
	_trigger_ceremony(4, 0.6)


## Fire shake + hit-stop exactly once per decided round. Only acts once TurnState
## has parked a decided round in PHASE_ROUND_OVER, so it can never run
## mid-resolution. Forfeit reuses the same gate: forfeit_tick() decides
## synchronously in _process, and _check_game_over() (below) calls this after.
func _trigger_ceremony(hit_frames: int, shake_amount: float) -> void:
	if _ceremony_fired or feel == null:
		return
	var phase: String = str(turn_state.state().get("phase", "")) if turn_state != null else ""
	if phase != TurnState.PHASE_ROUND_OVER:
		return
	_ceremony_fired = true
	feel.hit_stop(hit_frames)
	feel.shake(shake_amount)


func _check_game_over() -> void:
	if _game_over_printed:
		return
	var st: Dictionary = turn_state.state()
	var phase: String = str(st.get("phase", ""))
	if phase != TurnState.PHASE_ROUND_OVER:
		return
	var winner: String = str(st.get("winner", "unknown"))
	var loser: String = str(st.get("loser", "unknown"))
	print("[GAME OVER] %s wins the round (loser: %s, phase: %s)." % [winner, loser, phase])
	_game_over_printed = true
	# An OOB resolves via the signal path, which already fired the impact beat
	# (_trigger_ceremony(4, 0.6)) before this ran. A forfeit resolves
	# synchronously inside forfeit_tick() above with no signal, so if the
	# ceremony has not fired yet this is the forfeit path — a gentler beat for
	# a time-out, but the acceptance gate (shake/hit-stop fire on round
	# resolve) needs it to also exercise the ceremony.
	if not _ceremony_fired:
		_trigger_ceremony(3, 0.4)


## Drive the turn-transition gate (docs §3.5 #1). Shows it exactly once per
## turn handoff (a settle auto-advanced to a new player's AIM) and once per
## decided round (OOB winner or forfeit). Guarded by _gate_showing so the
## per-frame call can never double-show.
func _update_gate(st: Dictionary, phase: String) -> void:
	var cur: String = str(st.get("current_player", ""))
	if phase == TurnState.PHASE_AIM and cur != "" and cur != _acknowledged_player:
		# A round settled with both pens on the table and TurnState auto-
		# advanced to the next player — gate their turn before they can flick.
		_show_gate("%s's turn — tap to continue" % _display_name(cur))
	elif phase == TurnState.PHASE_ROUND_OVER:
		# Decided round (OOB winner or forfeit): final prompt. The tap restarts
		# the game with the winner going first.
		_show_gate("%s wins — tap to restart" % _display_name(str(st.get("winner", "unknown"))))


## Raise the gate: lock flick routing, remember it's showing, hand the prompt
## to the overlay. No TurnState writes here — presentation only.
func _show_gate(text: String) -> void:
	_gate_showing = true
	_input_locked = true
	turn_gate.show_prompt(text)


## TurnGate.tapped (or F key): acknowledge the handoff and resume.
## - Turn handoff (AIM): unlock, remember this player is gated, sync the zone.
## - Decided round (ROUND_OVER): reset both pens, begin the next round with the
##   winner first (ceremony skip: feel.reset() clears any hit-stop freeze).
## _input_locked is cleared so the active player can flick immediately.
func _on_gate_tapped() -> void:
	if turn_state == null or not _gate_showing:
		return
	_gate_showing = false
	_input_locked = false
	turn_gate.dismiss()
	var phase: String = str(turn_state.state().get("phase", ""))
	if phase == TurnState.PHASE_ROUND_OVER:
		# Ceremony skip (docs §3.5 #7): reset() restores time_scale and clears
		# the shake/camera offset — idempotent, safe to call mid hit-stop.
		if feel != null:
			feel.reset()
		for pen: PenBody in [pen_red, pen_blue]:
			pen.reset()
		# Fresh round: re-arm the once-per-round verdict + ceremony guards.
		_game_over_printed = false
		_ceremony_fired = false
		turn_state.continue_to_next_round()
		# Autoplay driver: schedule the next random flick for the new round so
		# PENFIGHT_AUTOPLAY=1 keeps driving rounds without human input.
		if _auto_flick != null:
			_auto_flick.arm(1.2)
	# The gate was just acknowledged for this turn — the player can flick now.
	_acknowledged_player = turn_state.current_player()
	_sync_aim_zone()


## Human-readable player name for the gate prompt ("red" -> "Red").
func _display_name(pen_id: String) -> String:
	return pen_id.capitalize()
