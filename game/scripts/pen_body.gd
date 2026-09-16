class_name PenBody
extends RigidBody2D
## A single pen token on the table.
##
## Owns no game rules: it is a physics body that reports three facts — the flick
## that started a flight, the flight settling, and going out of bounds. Main /
## TurnState own the rules and wire against the contract signals below.

# --- Contract interface (docs/phase05-contract.md) ------------------------------
signal settled(pen_uid: String)
signal flicked(pen_uid: String, impulse: Vector2)
signal out_of_bounds(pen_uid: String)
signal moved(pen_uid: String)
## Contact impact for the audio agent (consumer wired by the orchestrator):
## emitted throttled while the body reports a contact AND linear speed exceeds
## IMPACT_MIN_SPEED. impact_speed is the current linear velocity magnitude.
signal impact(pen_uid: String, impact_speed: float)

## "red" or "blue" — set per instance in main.tscn ({{PENS}}).
@export var pen_id: String = "red"
## Global reset target. If left at Vector2.ZERO, the spawn spot is captured in
## _ready() so reset() always restores the pen to where it started.
@export var start_position: Vector2 = Vector2.ZERO

# --- Tuning ---------------------------------------------------------------------
## Settle: emit `settled` once velocity magnitude and angular speed stay below
## these for SETTLE_DEBOUNCE seconds of continuous quiet (contract: ~0.25 s).
const SETTLE_LINEAR_VEL := 6.0       # px/s
const SETTLE_ANGULAR_VEL := 0.4      # rad/s
const SETTLE_DEBOUNCE := 0.25        # s

## A pen counts as having "actually moved" this turn above this speed
## (docs/ART_AND_FEEL_SPEC.md §7): a settled turn where NO pen ever exceeded it
## is a stalemate -> the flicking player forfeits (prevents tickle-flick
## stalling forever, since the timeout-forfeit only guards no-input slow play).
const MOVED_LINEAR_VEL := 25.0       # px/s

## Converts a 0..1 flick power fraction into a real fireable impulse.
## Derived per docs/ART_AND_FEEL_SPEC.md §8: with mass 1.0 and effective linear
## damp ~2.1, distance ≈ impulse/(mass×damp) → full power ≈ 1600 travels ~70%
## of the 1120px table. Tune damp FIRST, then this (spec §8.3).
const MAX_IMPULSE := 1600.0

## Conservative fallback extents if the pen has no CollisionShape2D to read.
## Matches the ART_AND_FEEL_SPEC geometry: CapsuleShape2D radius 5, height 180
## (central segment 180 - 2*5 = 170 -> half-len 85). The scene normally
## supplies the shape; these only keep OOB geometry defined before resolution.
const DEFAULT_PEN_RADIUS := 5.0
const DEFAULT_PEN_HALF_LEN := 85.0

## A few px of extra slack beyond the radius inset in the geometric OOB test:
## absorb solver jitter at the boundary (endpoints may sit up to
## radius+tolerance past the rect before out_of_bounds fires). [TUNE]
const OOB_TOLERANCE_PX := 8.0

## Impact signal thresholds: a hit is reportable when the body reports a
## contact AND its linear speed exceeds IMPACT_MIN_SPEED; emit at most once
## per IMPACT_TICK_INTERVAL physics ticks — 12 ticks ~= 50 ms at the 240 Hz
## rate, matching the old 3-ticks-at-60-Hz cadence. [TUNE]
const IMPACT_MIN_SPEED := 60.0
const IMPACT_TICK_INTERVAL := 12

## Give the table-resolution retry a ~2 s window at 240 Hz (480 ticks), then
## safely disable OOB detection (a missing table should never false-trigger an
## instant loss).
const TABLE_RESOLVE_MAX_ATTEMPTS := 480

# --- Internal state --------------------------------------------------------------
var _in_flight := false
var _settled_emitted := false
var _oob_emitted := false
var _quiet_time := 0.0
var _moved_emitted := false
var _pending_impulse := Vector2.ZERO
## Local-space point where the pending impulse lands (torque arm). Vector2.ZERO
## = centre hit (pure slide, no spin). Populated by apply_flick from the grab
## contact offset; consumed in _integrate_forces.
var _pending_impulse_local_pos := Vector2.ZERO
## Throttle counter for the `impact` signal: count down/wrap every
## IMPACT_TICK_INTERVAL physics ticks of sustained hard contact. Cleared in
## apply_flick / reset / _ready so no stale throttle carries between flights.
var _impact_throttle_ticks := 0

# Table bounds, resolved lazily (robust to the exact node names in main.tscn).
var _table_rect := Rect2()
var _table_rect_valid := false
var _table_resolve_attempts := 0

# Pen geometry in body-local space, read once from the pen's CollisionShape2D.
var _shape_local_t := Transform2D.IDENTITY
var _pen_radius := DEFAULT_PEN_RADIUS
var _pen_half_len := DEFAULT_PEN_HALF_LEN


func _ready() -> void:
	# Keep the body awake so the settle debounce always runs to completion. The
	# engine's own sleep uses looser angular thresholds and could put the body to
	# sleep (stopping _integrate_forces) while the pen is still visibly spinning,
	# which would end the turn early. Two bodies never sleeping is negligible.
	can_sleep = false

	if start_position == Vector2.ZERO:
		start_position = global_position

	_read_pen_shape()
	_try_resolve_table()

	_impact_throttle_ticks = 0


# --- Public API ------------------------------------------------------------------

## Start a flight. `impulse_dir` is the aim direction, `power` its magnitude.
## The impulse is queued and applied through the physics state on the next
## _integrate_forces call — never a position teleport (contract: set velocity
## via physics state).
##
## Power arrives as a 0..1 drag fraction (human slingshot AND AutoFlick both
## emit this shape). MAX_IMPULSE converts that fraction into a real fireable
## impulse: power 1.0 travels ~70% of a 1120px table with mass 1.0 / damp ~2.1
## (docs/ART_AND_FEEL_SPEC.md §8: impulse ≈ distance × mass × damp).
##
## `contact_offset` is the grab point along the pen's barrel as a fraction of
## half-length (-1 = tip, 0 = centre, 1 = cap end). real pen-fight physics: an
## off-centre grab with a drag direction SKEW to the barrel spins the pen as it
## slides (torque = r × F); a centred grab is a clean slide. 0.0 = centre hit.
func apply_flick(impulse_dir: Vector2, power: float, contact_offset: float = 0.0) -> void:
	_in_flight = true
	_settled_emitted = false
	_oob_emitted = false
	_moved_emitted = false
	_quiet_time = 0.0
	_pending_impulse = impulse_dir * power * MAX_IMPULSE
	_pending_impulse_local_pos = Vector2.RIGHT * clampf(contact_offset, -1.0, 1.0) * _pen_half_len
	_impact_throttle_ticks = 0
	flicked.emit(pen_id, _pending_impulse)


## Restore the pen to start_position with zero linear/angular velocity.
func reset() -> void:
	_in_flight = false
	_settled_emitted = false
	_oob_emitted = false
	_moved_emitted = false
	_quiet_time = 0.0
	_pending_impulse = Vector2.ZERO
	_impact_throttle_ticks = 0
	global_position = start_position
	rotation = 0.0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	sleeping = false
	# Teleport while physics interpolation is on: snap the interpolation window
	# so the pen does not visually glide back to its start position.
	reset_physics_interpolation()


## Debug/soak-test accessors (used by Main's autoplay stall detector).
func is_in_flight_test() -> bool:
	return _in_flight


func is_out_of_bounds_test() -> bool:
	return _oob_emitted


## Geometry accessors for AimInput's capsule grab test (barrel half-length and
## radius as resolved from the scene's CollisionShape2D).
func get_half_len() -> float:
	return _pen_half_len


func get_radius() -> float:
	return _pen_radius


## Ground-truth flag for PhysicsDirectBodyState2D.apply_impulse's position
## frame. CONFIRMED by the two-position torque probe (tests/torque_arm_probe.gd):
## the position is an OFFSET FROM THE BODY ORIGIN IN GLOBAL ORIENTATION —
## a vector, not a world point (Godot docs class_physicsdirectbodystate2d:
## "position is the offset from the body origin in global coordinates").
## The pre-fix _to_world() used get_global_transform() * local_pos, which adds
## global_position (translation) to the arm — measured 8.6x spin difference
## between two table positions. basis_xform applies rotation only.
## Do not change without re-running the probe.
const APPLY_IMPULSE_WORLD_TRANSLATION: bool = false


## Local -> global-orientation offset (rotation applied, translation dropped).
## apply_impulse(impulse, position) wants the offset from the body origin in
## global coordinates — a vector. get_global_transform() * v would include
## the body's world position (the bug); basis_xform() is rotation only.
func _to_world(local_pos: Vector2) -> Vector2:
	if APPLY_IMPULSE_WORLD_TRANSLATION:
		return get_global_transform() * local_pos
	return get_global_transform().basis_xform(local_pos)


# --- Physics ----------------------------------------------------------------------

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not _table_rect_valid:
		_try_resolve_table()

	if _pending_impulse != Vector2.ZERO:
		# Off-centre flick: apply the impulse at the grab offset (rotation-only
		# transform) so an axis-skew drag produces torque — pen slides AND
		# spins, real pen-fight. Always use apply_impulse: with a ZERO offset
		# it is algebraically identical to apply_central_impulse, and skipping
		# the exact-float `== Vector2.ZERO` branch avoids a computed-vector
		# equality hazard (review of main at 76aad79).
		state.apply_impulse(_pending_impulse, _to_world(_pending_impulse_local_pos))
		_pending_impulse = Vector2.ZERO
		_pending_impulse_local_pos = Vector2.ZERO

	_update_settle(state)
	_update_oob(state)
	_update_impact(state)


## Settle detector: velocity magnitude + angular speed below threshold for
## ~0.25 s of continuous quiet -> emit `settled` once per flight. Also emits
## `moved` once per flight the first time linear speed exceeds MOVED_LINEAR_VEL
## (docs/ART_AND_FEEL_SPEC.md §7 stalemate rule — TurnState uses it to
## distinguish a real exchange from a tickle-flick).
func _update_settle(state: PhysicsDirectBodyState2D) -> void:
	if not _in_flight or _settled_emitted or _oob_emitted:
		return
	var lin_v: Vector2 = state.get_linear_velocity()
	if not _moved_emitted and lin_v.length() >= MOVED_LINEAR_VEL:
		_moved_emitted = true
		moved.emit(pen_id)
	var lin_sq := lin_v.length_squared()
	var ang := absf(state.get_angular_velocity())
	if lin_sq < SETTLE_LINEAR_VEL * SETTLE_LINEAR_VEL and ang < SETTLE_ANGULAR_VEL:
		_quiet_time += state.get_step()
		if _quiet_time >= SETTLE_DEBOUNCE:
			_settled_emitted = true
			settled.emit(pen_id)
	else:
		_quiet_time = 0.0


## Out-of-bounds detector. Runs every tick regardless of who was flicked, so a
## defender's pen knocked off the table is also caught. Emits once per out-flight.
func _update_oob(state: PhysicsDirectBodyState2D) -> void:
	if _oob_emitted or not _table_rect_valid:
		return
	if _any_part_outside(state):
		_oob_emitted = true
		out_of_bounds.emit(pen_id)


## Impact detector (audio agent): emit `impact` throttled to ~1 per
## IMPACT_TICK_INTERVAL physics ticks while the body reports a live contact
## AND its linear speed clears IMPACT_MIN_SPEED. Runs every tick regardless of
## who was flicked, so a defender rammed by the flicker's pen also reports.
func _update_impact(state: PhysicsDirectBodyState2D) -> void:
	if state.get_contact_count() <= 0:
		return
	var lin_speed: float = state.get_linear_velocity().length()
	if lin_speed <= IMPACT_MIN_SPEED:
		return
	_impact_throttle_ticks += 1
	if _impact_throttle_ticks < IMPACT_TICK_INTERVAL:
		return
	_impact_throttle_ticks = 0
	impact.emit(pen_id, lin_speed)


## Geometric "any part off" test (contract §3.2): a capsule is fully on the
## table iff both world-space endpoints of its central segment lie inside the
## table rect shrunk by the capsule radius. Out of bounds = that stops
## holding. The radius inset is relaxed by OOB_TOLERANCE_PX, so solver jitter
## at the edge does not false-trigger: endpoints may sit up to
## radius+tolerance past the rect before out_of_bounds fires. The verdict
## stays geometric capsule-extent — never centre-of-mass.
func _any_part_outside(state: PhysicsDirectBodyState2D) -> bool:
	var body_t: Transform2D = state.get_transform()
	var shape_t: Transform2D = body_t * _shape_local_t
	var p1: Vector2 = shape_t * Vector2(0.0, _pen_half_len)
	var p2: Vector2 = shape_t * Vector2(0.0, -_pen_half_len)
	var inner: Rect2 = _table_rect.grow(-(_pen_radius + OOB_TOLERANCE_PX))
	return not (inner.has_point(p1) and inner.has_point(p2))


# --- Pen geometry / table discovery ------------------------------------------------

func _read_pen_shape() -> void:
	var shape_node := _find_any_shape_node(self)
	if shape_node == null:
		push_warning("PenBody(%s): no CollisionShape2D found; using fallback extents" % pen_id)
		return
	_shape_local_t = shape_node.transform
	var s: Shape2D = shape_node.shape
	if s is CapsuleShape2D:
		var capsule := s as CapsuleShape2D
		_pen_radius = capsule.radius
		_pen_half_len = maxf(capsule.height * 0.5 - _pen_radius, 0.0)
	elif s is CircleShape2D:
		_pen_radius = (s as CircleShape2D).radius
		_pen_half_len = 0.0
	else:
		push_warning("PenBody(%s): unsupported shape %s; using fallback extents" % [pen_id, s.get_class()])


func _try_resolve_table() -> void:
	if _table_rect_valid or _table_resolve_attempts >= TABLE_RESOLVE_MAX_ATTEMPTS:
		return
	_table_resolve_attempts += 1
	var table_node := _resolve_table_node()
	if table_node == null:
		if _table_resolve_attempts >= TABLE_RESOLVE_MAX_ATTEMPTS:
			push_warning("PenBody(%s): no table node found; OOB detection disabled (safe default)" % pen_id)
		return
	_table_rect = _rect_from_node(table_node)
	_table_rect_valid = true


## Discover the table node without depending on main.tscn's exact naming:
## 1. a node named like "Table" that carries a RectangleShape2D,
## 2. any node named like "Table",
## 3. as a last resort, any RectangleShape2D in the scene.
func _resolve_table_node() -> Node2D:
	var root := get_tree().get_root()
	var hit := _search_table(root, true)
	if hit == null:
		hit = _search_table(root, false)
	if hit == null:
		hit = _search_any_rect_shape(root)
	return hit


func _search_table(node: Node, require_rect_shape: bool) -> Node2D:
	var is_table_named: bool = String(node.name).to_lower().contains("table")
	if node is Node2D and node != self and is_table_named \
			and (not require_rect_shape or _find_rect_shape_node(node) != null):
		return node as Node2D
	for child in node.get_children():
		if child == self:
			continue
		var found := _search_table(child, require_rect_shape)
		if found != null:
			return found
	return null


func _search_any_rect_shape(node: Node) -> Node2D:
	if node is CollisionShape2D and node.shape is RectangleShape2D:
		return node as Node2D
	for child in node.get_children():
		if child == self:
			continue
		var found := _search_any_rect_shape(child)
		if found != null:
			return found
	return null


func _find_rect_shape_node(node: Node) -> CollisionShape2D:
	if node is CollisionShape2D and node.shape is RectangleShape2D:
		return node
	for child in node.get_children():
		var found := _find_rect_shape_node(child)
		if found != null:
			return found
	return null


func _find_any_shape_node(node: Node) -> CollisionShape2D:
	if node is CollisionShape2D and node.shape != null:
		return node
	for child in node.get_children():
		var found := _find_any_shape_node(child)
		if found != null:
			return found
	return null


func _rect_from_node(table_node: Node2D) -> Rect2:
	var rect_shape := _find_rect_shape_node(table_node)
	if rect_shape != null:
		return _rect_from_rect_shape(rect_shape)
	var any_shape := _find_any_shape_node(table_node)
	if any_shape != null:
		return _rect_from_any_shape(any_shape)
	# Last resort: guess a rect centered on the node (only keeps OOB geometry
	# defined instead of crashing — a real table always carries a shape).
	var vs := get_viewport_rect().size
	push_warning("PenBody(%s): table '%s' has no collision shape; using guessed rect" % [pen_id, table_node.name])
	return Rect2(table_node.global_position - vs * 0.4, vs * 0.8)


func _rect_from_rect_shape(shape_node: CollisionShape2D) -> Rect2:
	var size: Vector2 = (shape_node.shape as RectangleShape2D).size
	var t: Transform2D = shape_node.global_transform
	var half := size * 0.5
	var r := Rect2(t * Vector2(-half.x, -half.y), Vector2.ZERO)
	r = r.expand(t * Vector2(half.x, -half.y))
	r = r.expand(t * Vector2(half.x, half.y))
	r = r.expand(t * Vector2(-half.x, half.y))
	return r


func _rect_from_any_shape(shape_node: CollisionShape2D) -> Rect2:
	var t: Transform2D = shape_node.global_transform
	if shape_node.shape is CircleShape2D:
		var radius: float = (shape_node.shape as CircleShape2D).radius
		return Rect2(t.origin - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0))
	return Rect2(t.origin, Vector2(64.0, 64.0))
