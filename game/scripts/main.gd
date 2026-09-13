extends Node2D
class_name Main
## Phase 0.5 wiring-only controller for pen-fight (extended Phase 1a with a
## feel layer + debug overlay).
##
## Owns no physics. Per the build contract it only connects:
##   AimInput.flick_ready(dir, power) -> TurnState.on_flick -> active PenBody.apply_flick
##   PenBody.settled            -> TurnState.on_settled
##   PenBody.out_of_bounds      -> TurnState.on_out_of_bounds
## and prints a verdict line once a round is decided (GAME_OVER / FORFEIT).
## Phase 1a adds: Feel (trauma shake + hit-stop) and DebugOverlay (debug-build
## contact/velocity text), both driven from here AFTER TurnState decides.
## TurnState and AimInput are Agent C's classes; PenBody is Agent A's; feel.gd
## and debug_overlay.gd are Agent B's (this file).

@onready var pen_red: PenBody = $PenRed as PenBody
@onready var pen_blue: PenBody = $PenBlue as PenBody

var turn_state: TurnState = null
var aim_input: AimInput = null

## Phase 1a feel layer + debug overlay (Agent B).
var feel: Feel = null
var overlay: DebugOverlay = null

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

	turn_state.begin_turn()


func _process(delta: float) -> void:
	# Feel layer ticks every frame regardless of turn_state state, so the
	# hit-stop frame counter always completes and trauma never freezes mid-shake.
	if feel != null:
		feel.process_frame(delta)
	if turn_state == null:
		return
	turn_state.forfeit_tick(delta)
	if turn_state.state().get("phase", "") == TurnState.PHASE_AIM:
		_sync_aim_zone()
	_check_game_over()


func _on_flick_ready(direction: Vector2, power: float) -> void:
	if turn_state == null:
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
## has left AIM/IN_FLIGHT for a terminal phase (GAME_OVER / FORFEIT), so it can
## never run mid-resolution. Forfeit reuses the same gate: forfeit_tick() decides
## synchronously in _process, and _check_game_over() (below) calls this after.
func _trigger_ceremony(hit_frames: int, shake_amount: float) -> void:
	if _ceremony_fired or feel == null:
		return
	var phase: String = str(turn_state.state().get("phase", "")) if turn_state != null else ""
	if phase != TurnState.PHASE_GAME_OVER and phase != TurnState.PHASE_FORFEIT:
		return
	_ceremony_fired = true
	feel.hit_stop(hit_frames)
	feel.shake(shake_amount)


func _check_game_over() -> void:
	if _game_over_printed:
		return
	var st: Dictionary = turn_state.state()
	var phase: String = str(st.get("phase", ""))
	if phase != TurnState.PHASE_GAME_OVER and phase != TurnState.PHASE_FORFEIT:
		return
	var winner: String = str(st.get("winner", "unknown"))
	var loser: String = str(st.get("loser", "unknown"))
	print("[GAME OVER] %s wins the round (loser: %s, phase: %s)." % [winner, loser, phase])
	_game_over_printed = true
	# Forfeit resolves synchronously inside forfeit_tick() above — by the time we
	# get here the outcome is decided. If an OOB already fired the ceremony this
	# is a no-op (guarded once per round). A gentler beat for a time-out than an
	# impact, but the acceptance gate (shake/hit-stop fire on round resolve) needs
	# the forfeit path — the only one testable without input — to also exercise it.
	if phase == TurnState.PHASE_FORFEIT:
		_trigger_ceremony(3, 0.4)
