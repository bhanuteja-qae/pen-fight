extends Node2D
class_name Main
## Phase 1b wiring controller for pen-fight (turn-transition gate, ceremony
## skip, debug autoplay harness). Extended from the Phase 1a feel layer.
##
## Owns no physics. Per the build contract it only connects:
##   AimInput.flick_ready(dir, power) -> Main._submit_shot(ShotCommand) -> TurnState + PenBody
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
## blocks _submit_shot so a player can never flick on the wrong turn. The
## ceremony stays post-decision and is skippable on tap (docs §3.5 #7). Debug
## builds with PENFIGHT_AUTOPLAY=1 arm Agent B's AutoFlick to drive rounds
## headlessly.

@onready var pen_red: PenBody = $PenRed as PenBody
@onready var pen_blue: PenBody = $PenBlue as PenBody

var turn_state: TurnState = null
var aim_input: AimInput = null
## Immutable snapshot for the active game session. Runtime shot intake stays
## closed until this has been built successfully.
var active_match_config: MatchConfig = null

const DIRECTION_EPSILON: float = 0.001

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

## Player settings (persisted) + the sheet that edits them, + haptics. The
## store is the single source of truth; Main applies every value here so the
## screen stays a pure view (see _apply_settings / _on_setting_row).
var settings_store: SettingsStore = null
var settings_screen: SettingsScreen = null
var haptics: Haptics = null
## Round wins this match, keyed by pen_id, and whether the match is decided.
## A round win is counted when a round resolves; the match ends at
## settings_store.rounds_to_win() and a tap starts a fresh match.
var _round_wins: Dictionary = {"red": 0, "blue": 0}
var _match_over: bool = false
## Debug autoplay harness (AutoFlick), created only in debug builds with
## PENFIGHT_AUTOPLAY=1. Kept as a member so a re-armed round can schedule the
## next flick after the gate tap restarts the game.
var _auto_flick: AutoFlick = null
## True while the gate is up: _submit_shot rejects all commands, so a player
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

## Idle (no-input) forfeit backstop. 15 s: long enough that a thinking player
## is never punished (old 4 s read as a spontaneous game-over — "tap to
## restart"), short enough that an AFK opponent in hot-seat is noticed. The
## anti-stall job (weak/fishy flicks never moving a pen) is carried by the
## stalemate forfeit in turn_state.gd, NOT this timer — this is purely "how
## long may a turn sit unattended before we end it". [TUNE — playtest]
const FORFEIT_TIMEOUT: float = 15.0
## World-space table rect; must match the TableBounds node geometry in main.tscn.
## Phase 1d resize: table_bounds is now 1180x640 centered on the origin
## (was 1120x600 — the 30 px/side growth is blocked-by-the-contract watch item
## QA-6: this constant and the scene MUST agree).
const TABLE_RECT: Rect2 = Rect2(-590.0, -320.0, 1180.0, 640.0)

## Every pen texture is authored at 540 px wide and drawn at PEN_SPRITE_SCALE,
## which lands the slim pens on 180x11 px and the marker on 180x15 px on
## screen — the physics capsule (PenBody half_len 85 + radius 5) is 180x10, so
## the art can overhang it slightly; the capsule itself never changes. The
## skins are real pens scaled into the game: a skin swap can never resize the
## pen, because the scale is applied by set_pen_skin() rather than left to
## each skin's own sprite.
## Regenerate the art with: game/assets/generate_pens_nb2.py --set models
const PEN_SPRITE_SCALE: float = 1.0 / 3.0

## Pen skin selection (Phase 1c): each player picks a pen DESIGN to play with.
## Only two pens are ever on the table — the extra designs are preference
## options, not extra players. Each skin carries its own shadow so the
## silhouette can never drift from the pen, and its own display NAME so the
## gate and the verdict can only ever name the pen that is actually in the
## scene (docs/design/core-loop.md finding 4). Names stay words that match
## the art — never "Red"/"Blue", which would contradict the CVD-safe naming
## the sprites were chosen for.
const PEN_SKINS: Dictionary = {
	"bic": {
		"name": "Bic",
		"pen": "res://assets/pen_bic.png",
		"shadow": "res://assets/pen_bic_shadow.png",
	},
	"jotter": {
		"name": "Jotter",
		"pen": "res://assets/pen_jotter.png",
		"shadow": "res://assets/pen_jotter_shadow.png",
	},
	"sharpie": {
		"name": "Sharpie",
		"pen": "res://assets/pen_sharpie.png",
		"shadow": "res://assets/pen_sharpie_shadow.png",
	},
	"uniball": {
		"name": "Signo",
		"pen": "res://assets/pen_uniball.png",
		"shadow": "res://assets/pen_uniball_shadow.png",
	},
}
## The design each slot plays when nothing is stored — and the fallback when a
## stored design no longer exists (see _apply_settings).
const DEFAULT_SKINS: Dictionary = {"red": "sharpie", "blue": "bic"}
var _player_skins: Dictionary = DEFAULT_SKINS.duplicate()


## Pick the pen design for a player (e.g. set_pen_skin("blue", "jotter")).
## Applies immediately to that player's pen sprite AND its shadow, and forces
## the shared footprint scale — so every design draws at its authored
## thickness (slim pens 180x11, the marker 180x15 px on screen).
## Returns false if the player or skin is unknown.
func set_pen_skin(player: String, skin: String) -> bool:
	if not _player_skins.has(player) or not PEN_SKINS.has(skin):
		return false
	_player_skins[player] = skin
	var entry: Dictionary = PEN_SKINS[skin]
	var sprite := _pen_sprite_node(player)
	if sprite != null:
		sprite.texture = load(entry["pen"]) as Texture2D
		sprite.scale = Vector2(PEN_SPRITE_SCALE, PEN_SPRITE_SCALE)
	var shadow := _pen_shadow_node(player)
	if shadow != null:
		shadow.texture = load(entry["shadow"]) as Texture2D
		shadow.scale = Vector2(PEN_SPRITE_SCALE, PEN_SPRITE_SCALE)
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


## The pen's drop shadow sprite (swapped with the skin so silhouette and pen
## always match).
func _pen_shadow_node(player: String) -> Sprite2D:
	match player:
		"red":
			return $PenRed/Shadow
		"blue":
			return $PenBlue/Shadow
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
		# Contract wiring (#6): AutoFlick emits a complete ShotCommand
		# (source="harness") at fire time; it connects to the same _submit_shot
		# boundary as human input. Without this connection autoplay flicks are
		# inert (rounds would resolve by forfeit, never by knockout).
		_auto_flick.auto_flick_requested.connect(_submit_shot)
		_auto_flick.arm(1.2)

	# Player settings: load, apply (skins/mute/shake), then build the sheet that
	# edits them. The env-var skin override stays LAST so an explicit
	# PENFIGHT_SKIN_<PLAYER> still wins for QA captures.
	settings_store = SettingsStore.new()
	settings_store.load_from_disk()
	haptics = Haptics.new()
	settings_screen = SettingsScreen.new()
	add_child(settings_screen)
	settings_screen.bind(settings_store, _display_name("red"), _display_name("blue"))
	settings_screen.row_pressed.connect(_on_setting_row)
	settings_screen.closed.connect(_on_settings_closed)

	turn_state.begin_turn()
	# Skin selection: apply env overrides AFTER the sprites exist but before
	# the first frame renders, so PENFIGHT_SKIN_<PLAYER>=sharpie shows from t=0.
	_apply_default_skins()
	# Applied after the env override so a saved preference is what a real player
	# gets, while an explicit PENFIGHT_SKIN_* still wins for QA.
	_apply_settings()
	_build_legacy_match_config()
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
	# The forfeit clock and the flick path are suspended under the gate AND
	# under the settings sheet: a player reading settings must not lose a round
	# to the idle timer, and a tap on the sheet must never flick a pen.
	if not _gate_showing and not settings_open():
		turn_state.forfeit_tick(delta)
	# OOB verdict + in-flight backstop (review QA-3/QA-2): buffered OOB events
	# are resolved on a frame boundary (so a same-tick double-OOB sees both pens
	# and the FLICKER loses), and IN_FLIGHT has a hard 8s clock so a creeping
	# pen can never hang the round forever.
	turn_state.resolve_pending_oob()
	turn_state.resolve_tick(delta)
	var st: Dictionary = turn_state.state()
	var phase: String = str(st.get("phase", ""))
	# Hard turn-transition gate: input is locked outside AIM so a player can
	# never flick on the wrong turn; the gate overlay drives the handoff.
	aim_input.input_locked = phase != TurnState.PHASE_AIM or settings_open()
	# Resolve the round BEFORE building the gate prompt: _check_game_over() is
	# what counts the round for the match, and the prompt quotes that score. It
	# must run first or the gate shows the previous round's score and never
	# updates (the gate only shows once per handoff, by design).
	_check_game_over()
	if not _gate_showing and not settings_open():
		_update_gate(st, phase)
	if phase == TurnState.PHASE_AIM:
		_sync_aim_zone()
		_feed_aim_overlay()
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
	if event is InputEventKey:
		var kb: InputEventKey = event
		if kb.pressed and (kb.keycode == KEY_ESCAPE or kb.physical_keycode == KEY_ESCAPE):
			# Escape opens the settings sheet, or closes it if it is already up.
			get_viewport().set_input_as_handled()
			if settings_open():
				settings_screen.close()
			else:
				open_settings()
			return
	if turn_state == null or not _gate_showing:
		return
	if event is InputEventKey:
		var kb: InputEventKey = event
		if kb.pressed and (kb.keycode == KEY_F or kb.physical_keycode == KEY_F):
			get_viewport().set_input_as_handled()
			_on_gate_tapped()


## Adapt the currently shipped hot-seat settings into the frozen match contract.
## Model IDs deliberately pass through from _player_skins; the domain registry,
## not Main, owns which IDs are valid.
func _build_legacy_match_config(requested_seed: int = 0) -> bool:
	if settings_store == null:
		push_error("Main: cannot build MatchConfig without SettingsStore")
		active_match_config = null
		return false
	var red_model: String = str(_player_skins.get("red", ""))
	var blue_model: String = str(_player_skins.get("blue", ""))
	var red: Participant = Participant.create(
		"red", "local_player", _display_name("red"), "human",
		red_model, "control", "")
	var blue: Participant = Participant.create(
		"blue", "local_player", _display_name("blue"), "human",
		blue_model, "control", "")
	if red == null or blue == null:
		push_error("Main: cannot build MatchConfig from active pen model IDs")
		active_match_config = null
		return false
	active_match_config = MatchConfig.create(
		"hot_seat", "classic", settings_store.match_length, requested_seed,
		[red, blue])
	if active_match_config == null:
		push_error("Main: active MatchConfig validation failed")
		return false
	return true


## The sole runtime/session boundary that commits Flick intent to game state and
## physics. Producers build ShotCommand values and stop here.
func _submit_shot(cmd: ShotCommand) -> bool:
	# Resolve and validate the complete operation before either downstream write.
	if (active_match_config == null or turn_state == null
			or not is_inside_tree() or is_queued_for_deletion()):
		return _reject_shot("no active game session", cmd)
	if cmd == null:
		return _reject_shot("missing ShotCommand", cmd)

	var slot: String = cmd.slot()
	if not ShotCommand.SLOTS.has(slot):
		return _reject_shot("unknown slot", cmd)
	if active_match_config.participant_for_slot(slot) == null:
		return _reject_shot("slot is not in the active match", cmd)
	var pen: PenBody = _pen_for_slot(slot)
	if pen == null:
		return _reject_shot("active slot has no live PenBody", cmd)

	if not ShotCommand.SOURCES.has(cmd.source()):
		return _reject_shot("unknown source", cmd)
	var direction: Vector2 = cmd.direction()
	if (not is_finite(direction.x) or not is_finite(direction.y)
			or direction == Vector2.ZERO):
		return _reject_shot("direction is not finite and nonzero", cmd)
	var direction_length: float = direction.length()
	if not is_finite(direction_length) or absf(direction_length - 1.0) > DIRECTION_EPSILON:
		return _reject_shot("direction is not unit length", cmd)
	var power: float = cmd.power()
	if not is_finite(power) or power < 0.0 or power > 1.0:
		return _reject_shot("power is outside 0..1", cmd)
	var contact_offset: float = cmd.contact_offset()
	if not is_finite(contact_offset) or contact_offset < -1.0 or contact_offset > 1.0:
		return _reject_shot("contact_offset is outside -1..1", cmd)

	var state: Dictionary = turn_state.state()
	if str(state.get("phase", "")) != TurnState.PHASE_AIM:
		return _reject_shot("TurnState is not in AIM", cmd)
	if str(state.get("current_player", "")) != slot:
		return _reject_shot("slot is not the active participant", cmd)
	if _input_locked or _gate_showing or settings_open() or _match_over:
		return _reject_shot("shot intake is closed", cmd)
	if _active_pen() != pen or not pen.is_inside_tree() or pen.is_queued_for_deletion():
		return _reject_shot("active PenBody is not ready", cmd)

	turn_state.on_flick(direction * power)
	pen.apply_flick(direction, power, contact_offset)
	return true


func _reject_shot(reason: String, cmd: ShotCommand = null) -> bool:
	var slot: String = cmd.slot() if cmd != null else "<missing>"
	var source: String = cmd.source() if cmd != null else "<missing>"
	push_warning("ShotCommand rejected: %s (slot=%s source=%s)" % [reason, slot, source])
	return false


func _pen_for_slot(slot: String) -> PenBody:
	match slot:
		"red":
			return pen_red if pen_red != null and pen_red.pen_id == "red" else null
		"blue":
			return pen_blue if pen_blue != null and pen_blue.pen_id == "blue" else null
		_:
			return null


## AimInput.flick_ready -> this. Thin human adapter (#6): build the contract
## command and submit it through the single session boundary _submit_shot.
## Phase/lock/pen checks and the state+physics commit live there; this holds
## no second shot path. Feedback fires only after an accepted commit, never on
## a rejection (MATCH-CONTRACT §"One atomic submission boundary").
func _on_flick_ready(direction: Vector2, power: float, contact_offset: float) -> void:
	if turn_state == null:
		return
	var cmd: ShotCommand = ShotCommand.create(
		str(turn_state.state().get("current_player", "")), direction, power,
		contact_offset, "human")
	if not _submit_shot(cmd):
		return
	if haptics != null:
		haptics.flick(power)
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


## Keep AimInput's grab zone on the active pen's capsule each AIM frame.
func _sync_aim_zone() -> void:
	var pen := _active_pen()
	if pen != null:
		aim_input.set_active_pen(pen)


## Phase 1d: feed the aim overlay per-frame. The overlay draws the grab ring,
## pull band, launch cone + power fill + MAX tick, and spin arc from the
## CURRENT drag gesture (touch or mouse); idle when nothing is being dragged.
## Also drives the IDLE turn cue (review UX-1): during AIM with no drag the
## active pen is highlighted ("YOUR FLICK" banner) so whose-turn is legible;
## cleared whenever the gate is up or the round is over.
func _feed_aim_overlay() -> void:
	if aim_overlay == null:
		return
	var pen := _active_pen()
	if pen == null or _gate_showing:
		aim_overlay.clear_turn()
		aim_overlay.clear()
		return
	aim_overlay.set_pen(pen)
	var info: Dictionary = aim_input.get_drag_info()
	if info.is_empty() or not info.get("dragging", false):
		# Idle AIM: show whose turn it is (overlay draws cue only when the
		# live gesture is absent — a started drag overrides it automatically).
		aim_overlay.clear()
		aim_overlay.show_turn(_display_name(str(turn_state.state().get("current_player", ""))))
	else:
		aim_overlay.clear_turn()
		aim_overlay.show_drag(info)


## PenBody.impact -> a layered thud on the SFX bus (per pen-pen / pen-table
## contact). The sound layer is presentation over the already-settled physics;
## a dead audio device degrades to a logged warning inside AudioManager.
func _on_pen_impact(_pen_uid: String, impact_speed: float) -> void:
	if audio_mgr != null:
		audio_mgr.play_impact(impact_speed)
	if haptics != null:
		haptics.impact()


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
	# Count the round for the match (guarded by _game_over_printed above, so
	# exactly one increment per decided round) and decide the match.
	if _round_wins.has(winner):
		_round_wins[winner] = int(_round_wins[winner]) + 1
	var target: int = settings_store.rounds_to_win() if settings_store != null else 99
	_match_over = int(_round_wins.get(winner, 0)) >= target
	if _match_over and settings_store != null:
		# Durable series record (docs/design/feature-priorities.md item A1): the
		# one outcome that outlives the match, persisted immediately. Guarded by
		# _game_over_printed above, so a decided match is recorded exactly once.
		settings_store.record_match_win(winner)
	print("[GAME OVER] %s wins the round %d-%d (loser: %s, phase: %s).%s" % [
		_display_name(winner), int(_round_wins.get("red", 0)), int(_round_wins.get("blue", 0)),
		_display_name(loser), phase, "  MATCH OVER" if _match_over else ""])
	if _match_over:
		print("[SERIES] %s" % _series_line())
	_game_over_printed = true
	if haptics != null:
		haptics.knockout()
	# Ceremony strength follows HOW the round was decided: an OOB verdict
	# (including a same-tick double-OOB, now resolved on the frame boundary)
	# plays the impact beat; forfeits/backstops play a gentler beat. The
	# acceptance gate needs shake+hit-stop to fire on every round resolve.
	if not _ceremony_fired:
		_trigger_ceremony(4, 0.6) if turn_state.decided_by_oob() else _trigger_ceremony(3, 0.4)


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
		# Decided round (OOB winner or forfeit). The prompt carries the running
		# match score; the tap either continues the match — the next round starts
		# with whoever did not flick last, see TurnState.continue_to_next_round()
		# — or, once a player has reached rounds_to_win(), starts a fresh match.
		var winner: String = _display_name(str(st.get("winner", "unknown")))
		var score: String = "%d-%d" % [int(_round_wins.get("red", 0)), int(_round_wins.get("blue", 0))]
		if _match_over:
			# The match-over prompt is the one gate that carries the durable
			# series: the round score in `score` is about to be thrown away by the
			# rematch tap, the series is not (item A1). The series goes on its own
			# line — as a single line the combined prompt measured 1276 px wide
			# and was clipped at both screen edges.
			_show_gate("%s wins the match %s — tap for a rematch\n%s" % [winner, score, _series_line()])
		else:
			_show_gate("%s wins the round %s — tap to continue" % [winner, score])


## The durable series record, formatted for the match-over gate:
## "series: Sharpie 2, Bic 1". Reads the store; presentation only, no writes.
func _series_line() -> String:
	if settings_store == null:
		return "series unavailable"
	return "series: %s %d, %s %d" % [
		_display_name("red"), settings_store.matches_won_red,
		_display_name("blue"), settings_store.matches_won_blue]


## Raise the gate: lock flick routing, remember it's showing, hand the prompt
## to the overlay. No TurnState writes here — presentation only.
func _show_gate(text: String) -> void:
	_gate_showing = true
	_input_locked = true
	turn_gate.show_prompt(text)


## TurnGate.tapped (or F key): acknowledge the handoff and resume.
## - Turn handoff (AIM): unlock, remember this player is gated, sync the zone.
## - Decided round (ROUND_OVER): reset both pens, begin the next round with the
##   player who did not flick last (strict alternation — the round winner on a
##   self-OOB loss, the loser on a knockout; ceremony skip: feel.reset() clears
##   any hit-stop freeze).
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
		if _match_over:
			# Match decided: the tap starts a new match, not another round.
			_match_over = false
			_round_wins = {"red": 0, "blue": 0}
		turn_state.continue_to_next_round()
		# Autoplay driver: schedule the next random flick for the new round so
		# PENFIGHT_AUTOPLAY=1 keeps driving rounds without human input.
		if _auto_flick != null:
			_auto_flick.arm(1.2)
	# The gate was just acknowledged for this turn — the player can flick now.
	_acknowledged_player = turn_state.current_player()
	_sync_aim_zone()


## Apply every stored setting to the systems that own it. Called once at start
## and again after any row change, so the screen never reaches into audio/feel
## itself.
func _apply_settings() -> void:
	if settings_store == null:
		return
	for player: String in _player_skins.keys():
		if not set_pen_skin(player, settings_store.pen_for(player)):
			# A save written before the designs were renamed (amber/cobalt/
			# graphite/ivory), or any id that is not a design: put the slot on a
			# design that exists, so the art on the table and the name the gate
			# prints can never disagree (see legacy_skin_falls_back below).
			set_pen_skin(player, str(DEFAULT_SKINS[player]))
	if audio_mgr != null:
		audio_mgr.set_muted(not settings_store.sound_on)
	if feel != null:
		feel.enabled = settings_store.screen_shake_on
	if haptics != null:
		haptics.set_enabled(settings_store.haptics_on)
	if settings_screen != null:
		# The sheet names each player after the design that slot is playing, so
		# the rows follow a skin change instead of freezing on the default art
		# (item A2). bind() re-applies the names and refreshes the sheet.
		settings_screen.bind(settings_store, _display_name("red"), _display_name("blue"))


## A settings row was tapped. Mutates the store, re-applies it, persists, and
## repaints the sheet. Row order must match SettingsScreen.Row.
func _on_setting_row(row: int) -> void:
	if settings_store == null:
		return
	match row:
		SettingsScreen.Row.SOUND:
			settings_store.sound_on = not settings_store.sound_on
		SettingsScreen.Row.HAPTICS:
			settings_store.haptics_on = not settings_store.haptics_on
			# Confirm the new state by touch, so the toggle is felt, not just seen.
			haptics.knockout()
		SettingsScreen.Row.SHAKE:
			settings_store.screen_shake_on = not settings_store.screen_shake_on
		SettingsScreen.Row.MATCH_LENGTH:
			settings_store.match_length = settings_store.next_match_length()
		SettingsScreen.Row.PEN_RED:
			settings_store.set_pen("red", _next_design(settings_store.pen_red))
		SettingsScreen.Row.PEN_BLUE:
			settings_store.set_pen("blue", _next_design(settings_store.pen_blue))
	_apply_settings()
	settings_store.save_to_disk()


## Next pen design in the skin list (cycles), for the "My pen" rows.
func _next_design(current: String) -> String:
	var keys: Array = PEN_SKINS.keys()
	if keys.is_empty():
		return current
	var i: int = keys.find(current)
	return str(keys[(i + 1) % keys.size()]) if i >= 0 else str(keys[0])


func open_settings() -> void:
	if settings_screen == null or _gate_showing:
		return
	settings_screen.open()


func _on_settings_closed() -> void:
	_sync_aim_zone()


## True while the sheet is up: flicks and the forfeit clock are suspended, the
## same way the turn gate suspends them (a settings tap must never flick).
func settings_open() -> bool:
	return settings_screen != null and settings_screen.is_open()


## Human-readable player name for the gate prompt, the verdict, the turn cue and
## the settings rows. Must match what the player SEES on screen (review, UX-3:
## gate text must not contradict the art — CVD-hostile confusion otherwise), so
## the name follows the pen DESIGN that slot is actually playing rather than a
## fixed default: with four designs selectable, the old hardcoded map could
## name a pen that is not in the scene (docs/design/core-loop.md finding 4).
## Names stay words matching the art — never "Red"/"Blue". An unknown
## slot id falls back to its capitalised form.
func _display_name(pen_id: String) -> String:
	var skin: String = str(_player_skins.get(pen_id, ""))
	if PEN_SKINS.has(skin):
		return str(PEN_SKINS[skin].get("name", skin.capitalize()))
	return pen_id.capitalize()


## Autoplay soak-test: compact pen state for the stall log.
## "v=<px/s> oob=<bool> inflight=<bool>".
func _dbg_pen(pen: PenBody) -> String:
	var v: float = pen.linear_velocity.length()
	return "v=%.1f oob=%s inflight=%s" % [v, pen.is_out_of_bounds_test(), pen.is_in_flight_test()]
