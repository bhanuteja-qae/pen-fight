extends Node2D
class_name Main
## Phase 0.5 wiring-only controller for pen-fight.
##
## Owns no physics. Per the build contract it only connects:
##   AimInput.flick_ready(dir, power) -> TurnState.on_flick -> active PenBody.apply_flick
##   PenBody.settled            -> TurnState.on_settled
##   PenBody.out_of_bounds      -> TurnState.on_out_of_bounds
## and prints a verdict line once a round is decided (GAME_OVER / FORFEIT).
## TurnState and AimInput are Agent C's classes; PenBody is Agent B's.

@onready var pen_red: PenBody = $PenRed as PenBody
@onready var pen_blue: PenBody = $PenBlue as PenBody

var turn_state: TurnState = null
var aim_input: AimInput = null

var _game_over_printed: bool = false

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

	turn_state.begin_turn()


func _process(delta: float) -> void:
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
