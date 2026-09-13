class_name AutoFlick
extends Node
## Phase 1b deterministic auto-flick harness (docs/phase1b-contract.md — Agent F).
##
## Lets a headless test / CI script drive the game to a REAL knockout (a pen
## leaving the table) instead of only the forfeit path. Scripted flicks route
## through the SAME path a human flick takes — TurnState records the impulse,
## and the active PenBody + Feel fire identically — by emitting
## `auto_flick_requested`; Main connects that signal and handles it exactly
## like `_on_flick_ready` minus the slingshot drag math.
##
## `enabled` defaults to false so normal play runs are completely untouched:
## nothing is scheduled or emitted until a test (or Main's debug autoplay hook)
## arms the harness.
##
## Legacy autoplay surface for Main's PENFIGHT_AUTOPLAY=1 debug hook: `setup`,
## `set_random_power` and `arm` are thin wrappers over the same signal path, so
## one AutoFlick serves both the deterministic test harness and the autoplay
## driver. (The old polling multi-round driver from the Phase 1a draft was
## replaced by this signal-based scheduler per the Phase 1b contract.)

signal auto_flick_requested(player: String, impulse: Vector2)

## Master switch. Normal runs leave this false and AutoFlick is inert.
var enabled: bool = false

# -- legacy autoplay surface (Main's PENFIGHT_AUTOPLAY debug hook) -----------------
var _main: Node = null
var _rng := RandomNumberGenerator.new()
var _min_power: float = 0.5
var _max_power: float = 1.0

## Point the harness at the Main node it should drive, and arm it. Only called
## from Main's debug autoplay path, so this is where `enabled` turns on.
func setup(main: Node) -> void:
	_main = main
	enabled = true

## Configure the random power range used by arm(). A seed >= 0 makes the
## autoplay sequence reproducible across runs.
func set_random_power(min_power: float, max_power: float, seed: int = -1) -> void:
	_min_power = minf(min_power, max_power)
	_max_power = maxf(min_power, max_power)
	if seed >= 0:
		_rng.seed = seed

## Schedule one random-direction / random-power flick for the CURRENT active
## player after delay_sec. The active player is resolved at FIRE time (not
## schedule time) so it is independent of when the caller arms it relative to
## turn_state.begin_turn(). Re-arming for a fresh round is the caller's job.
func arm(delay_sec: float) -> void:
	if not enabled:
		return
	if delay_sec <= 0.0:
		_fire_for_current_player()
		return
	if get_tree() == null:
		return
	var timer: SceneTreeTimer = get_tree().create_timer(delay_sec)
	timer.timeout.connect(_fire_for_current_player)

# -- contract API ----------------------------------------------------------------
## Schedule a scripted flick for `player` after delay_sec (0 or negative fires
## immediately). `impulse` is a full direction * power vector — the same shape
## TurnState records from a human flick (AimInput emits direction + power;
## Main records direction * power).
func schedule_flick(player: String, impulse: Vector2, delay_sec: float) -> void:
	if not enabled:
		return
	if delay_sec <= 0.0:
		fire_now(player, impulse)
		return
	if get_tree() == null:
		push_warning("AutoFlick.schedule_flick: node not inside the scene tree — flick not scheduled")
		return
	var timer: SceneTreeTimer = get_tree().create_timer(delay_sec)
	timer.timeout.connect(_on_scheduled_flick.bind(player, impulse))

## Fire a scripted flick right now for `player`. Validates that the pen exists
## in the scene tree (defensive: a missing pen logs a warning and no-ops), then
## emits `auto_flick_requested` so the connected consumer (Main, or a test)
## routes it through the human-flick path.
func fire_now(player: String, impulse: Vector2) -> void:
	if not enabled:
		return
	if get_tree() == null:
		push_warning("AutoFlick.fire_now: node not inside the scene tree — flick not fired")
		return
	if _find_pen(player) == null:
		push_warning("AutoFlick.fire_now: no PenBody found for player '%s' — flick not fired" % player)
		return
	if auto_flick_requested.get_connections().is_empty():
		push_warning(
			"AutoFlick.fire_now: auto_flick_requested has no connected consumer — "
			+ "Main must connect it (handle it like _on_flick_ready minus drag math)"
		)
	auto_flick_requested.emit(player, impulse)

func _on_scheduled_flick(player: String, impulse: Vector2) -> void:
	if enabled:
		fire_now(player, impulse)

func _fire_for_current_player() -> void:
	if not enabled:
		return
	var player := _current_player()
	if player == "":
		push_warning("AutoFlick.arm: no active player at fire time — flick not scheduled")
		return
	var direction := Vector2.from_angle(_rng.randf_range(0.0, TAU))
	var power := _rng.randf_range(_min_power, _max_power)
	fire_now(player, direction * power)

func _current_player() -> String:
	if _main == null:
		return ""
	var turn_state: Variant = _main.get("turn_state")
	if turn_state == null:
		return ""
	var snapshot: Dictionary = turn_state.state()
	return str(snapshot.get("current_player", ""))

## Find the PenBody whose pen_id matches `player`, walking the whole scene tree
## from the root (no assumption about exact node names in main.tscn).
func _find_pen(player: String) -> PenBody:
	return _search_pens(get_tree().get_root(), player)

func _search_pens(node: Node, player: String) -> PenBody:
	var body := node as PenBody
	if body != null and body.pen_id == player:
		return body
	for child in node.get_children():
		var found := _search_pens(child, player)
		if found != null:
			return found
	return null
