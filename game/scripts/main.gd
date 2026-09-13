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

## Phase 1d: aim overlay (grab ring, launch cone, spin arc) and audio manager
## (bus-based SFX). Created in _ready from the NEW scripts; driven from here.
var aim_overlay: AimOverlay = null
var audio_mgr: AudioManager = null

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
## Autoplay: the player a flick is currently armed for — re-arm only when the
## AIM turn hands to a NEW player (a same-player re-arm would stack timers).
var _autoplay_armed_player: String = ""
## Autoplay soak-test: accumulated seconds spent OUTSIDE the AIM phase (see the
## stall detector in _process). Zeroed whenever AIM is reached.
var _autoplay_outside_aim: float = 0.0
## Autoplay soak-test: after this many consecutive non-AIM seconds, log the
## full machine state (the 100-round soak found stalls the 20-round gate
## missed — a stall must be diagnosable, not silent).
const AUTOPLAY_STALL_SECONDS: float = 5.0

const FORFEIT_TIMEOUT: float = 4.0
## World-space table rect; must match the TableBounds node geometry in main.tscn.
## Spec coordinate contract (docs/ART_AND_FEEL_SPEC.md §1): playfield
## Rect2(80,60,1120,600) in viewport coords = centered at (0,0): x -560..560,
## y -300..300.
const TABLE_RECT: Rect2 = Rect2(-560.0, -300.0, 1120.0, 600.0)

## Pen skin selection (Phase 1c): each player picks a pen DESIGN to play with.
## Only two pens are ever on the table — the third sprite is a preference
## option, not a third player. Skins map pen_id -> asset path; the scene,
## physics, and TurnState still use exactly two pens.
const PEN_SKINS: Dictionary = {
	"red": "res://assets/pen_red_v4.png",
	"blue": "res://assets/pen_blue_v4.png",
	"green": "res://assets/pen_green_v4.png",
}
var _player_skins: Dictionary = {"red": "red", "blue": "blue"}


## Pick the pen design for a player (e.g. set_pen_skin("blue", "green")).
## Applies immediately to that player's Sprite2D. Returns false if the player
## or skin is unknown.
func set_pen_skin(player: String, skin: String) -> bool:
	if not _player_skins.has(player) or not PEN_SKINS.has(skin):
		return false
	_player_skins[player] = skin
	var sprite := _pen_sprite_node(player)
	if sprite != null:
		sprite.texture = load(PEN_SKINS[skin]) as Texture2D
	return true


## Apply any PENFIGHT_SKIN_<PLAYER> env overrides (debug/autoplay convenience).
func _apply_default_skins() -> void:
	for player: String in _player_skins.keys():
		var env_key := "PENFIGHT_SKIN_" + player.to_upper()
		var env_skin := OS.get_environment(env_key)
		if env_skin != "" and PEN_SKINS.has(env_skin):
			set_pen_skin(player, env_skin)


func _pen_sprite_node(player: String) -> Sprite2D:
	match player:
		"red":
			return $PenRed/Sprite2D
		"blue":
			return $PenBlue/Sprite2D
		_:
			return null


func _ready() -> void:
	turn_state = TurnState.new([pen_red.pen_id, pen_blue.pen_id], FORFEIT_TIMEOUT, TABLE_RECT)
	aim_input = AimInput.new()
	add_child(aim_input)
	aim_input.flick_ready.connect(_on_flick_ready)

	for pen: PenBody in [pen_red, pen_blue]:
		pen.settled.connect(turn_state.on_settled)
		pen.moved.connect(turn_state.on_pen_moved)
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

	# Phase 1d: aim overlay + audio. The overlay is a plain Node2D that draws
	# the aim UI (grab ring, launch cone, spin arc) anchored on the active pen;
	# Main feeds it per-frame drag info via show_drag(). AudioManager owns the
	# SFX buses and synthesized impact/flick sounds; Main routes pen impacts
	# and flicks into it. Both tolerate headless/no-device boxes gracefully.
	aim_overlay = AimOverlay.new()
	add_child(aim_overlay)
	audio_mgr = AudioManager.new()
	add_child(audio_mgr)
	for pen: PenBody in [pen_red, pen_blue]:
		pen.impact.connect(_on_pen_impact)

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
		# Human-scale power 0.5..1.0: apply_flick multiplies by MAX_IMPULSE
		# internally, so a fraction here = a real fireable impulse (~800..1600,
		# travelling ~40-70 % of the table). Older absolute ranges (2e4..1.2e5)
		# were pre-MAX_IMPULSE and double-scale today (3.2e7..1.9e8 -> instant
		# off-table ejects every round).
		_auto_flick.set_random_power(0.5, 1.0, randi())
		# Contract wiring (phase1b-contract §Agent F): Main connects the signal
		# and handles it exactly like _on_flick_ready minus the drag math. The
		# harness only emits; without this connection autoplay flicks are inert
		# (rounds would resolve by forfeit, never by knockout).
		_auto_flick.auto_flick_requested.connect(_on_auto_flick_requested)
		_auto_flick.arm(1.2)

	turn_state.begin_turn()
	# Skin selection: apply env overrides AFTER the sprites exist but before
	# the first frame renders, so PENFIGHT_SKIN_<PLAYER>=green shows from t=0.
	_apply_default_skins()
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
		_feed_aim_overlay()
	_check_game_over()
	# Autoplay driver: keep rounds coming without a human.
	# 1) Auto-tap ANY showing gate — a decided round's ROUND_OVER gate AND a
	#    settle-handoff gate (both pens stayed on -> next player's turn). Random
	#    flicks miss; without this the game parks forever at the settle gate.
	# 2) On a fresh AIM turn (player changed), re-arm the next flick.
	if _auto_flick != null and _auto_flick.enabled:
		if _gate_showing:
			_on_gate_tapped()
		var cur: String = str(st.get("current_player", ""))
		if phase == TurnState.PHASE_AIM and cur != "" and cur != _autoplay_armed_player:
			_autoplay_armed_player = cur
			_auto_flick.arm(1.0)
		# Soak-test stall detector (autoplay only): a functioning loop cycles
		# through AIM frequently. If we sit outside AIM for STALL_THRESHOLD
		# seconds, print the full machine state instead of silently idling —
		# that pinpoints soak-only bugs (settle edge, gate deadlock, missed
		# handoff) that the 20-round gate never triggers.
		_autoplay_outside_aim += delta if phase != TurnState.PHASE_AIM else -_autoplay_outside_aim
		_autoplay_outside_aim = maxf(_autoplay_outside_aim, 0.0)
		if _autoplay_outside_aim >= AUTOPLAY_STALL_SECONDS:
			print("[AUTOPLAY STALL] phase=%s cur=%s armed=%s gate=%s pens red=(%s) blue=(%s)" % [
				phase, cur, _autoplay_armed_player, _gate_showing,
				_dbg_pen(pen_red), _dbg_pen(pen_blue)])
			_autoplay_outside_aim = 0.0


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


func _on_flick_ready(direction: Vector2, power: float, contact_offset: float) -> void:
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
	# AimInput gives a slingshot pull vector (direction + power) plus the grab
	# offset along the barrel. TurnState records the impulse; the active pen
	# receives direction+power+contact for physics (off-centre grabs spin).
	turn_state.on_flick(direction * power)
	var pen := _active_pen()
	if pen != null:
		pen.apply_flick(direction, power, contact_offset)
	# Whoosh tick on release (SFX). The sound layer never gates the game.
	if audio_mgr != null:
		audio_mgr.play_flick(power)
	# The flick left AIM: clear the aim overlay so no stale UI lingers.
	if aim_overlay != null:
		aim_overlay.clear()


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
func _on_auto_flick_requested(player: String, impulse: Vector2, contact_offset: float = 0.0) -> void:
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
		pen.apply_flick(impulse.normalized(), impulse.length(), contact_offset)


## Keep AimInput's grab zone on the active pen's capsule each AIM frame.
func _sync_aim_zone() -> void:
	var pen := _active_pen()
	if pen != null:
		aim_input.set_active_pen(pen)


## Phase 1d: feed the aim overlay per-frame. The overlay draws the grab ring,
## pull band, launch cone + power fill + MAX tick, and spin arc from the
## CURRENT drag gesture (touch or mouse); idle when nothing is being dragged.
func _feed_aim_overlay() -> void:
	if aim_overlay == null:
		return
	var pen := _active_pen()
	if pen == null:
		aim_overlay.clear()
		return
	aim_overlay.set_pen(pen)
	aim_overlay.show_drag(aim_input.get_drag_info())


## PenBody.impact -> a layered thud on the SFX bus (per pen-pen / pen-table
## contact). The sound layer is presentation over the already-settled physics;
## a dead audio device degrades to a logged warning inside AudioManager.
func _on_pen_impact(_pen_uid: String, impact_speed: float) -> void:
	if audio_mgr != null:
		audio_mgr.play_impact(impact_speed)


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


## Autoplay soak-test: compact pen state for the stall log.
## "v=<px/s> oob=<bool> inflight=<bool>".
func _dbg_pen(pen: PenBody) -> String:
	var v: float = pen.linear_velocity.length()
	return "v=%.1f oob=%s inflight=%s" % [v, pen.is_out_of_bounds_test(), pen.is_in_flight_test()]
