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

## Conservative fallback extents if the pen has no CollisionShape2D to read.
## Matches the 96x20 v2 sprite geometry: CapsuleShape2D radius 10, height 76
## (central segment 76 - 2*10 = 56 -> half-len 28).
const DEFAULT_PEN_RADIUS := 10.0
const DEFAULT_PEN_HALF_LEN := 28.0

## Give the table-resolution retry a ~2 s window at 60 Hz, then safely disable
## OOB detection (a missing table should never false-trigger an instant loss).
const TABLE_RESOLVE_MAX_ATTEMPTS := 120

# --- Internal state --------------------------------------------------------------
var _in_flight := false
var _settled_emitted := false
var _oob_emitted := false
var _quiet_time := 0.0
var _pending_impulse := Vector2.ZERO

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


# --- Public API ------------------------------------------------------------------

## Start a flight. `impulse_dir` is the aim direction, `power` its magnitude.
## The impulse is queued and applied through the physics state on the next
## _integrate_forces call — never a position teleport (contract: set velocity
## via physics state).
func apply_flick(impulse_dir: Vector2, power: float) -> void:
	_in_flight = true
	_settled_emitted = false
	_oob_emitted = false
	_quiet_time = 0.0
	_pending_impulse = impulse_dir * power
	flicked.emit(pen_id, _pending_impulse)


## Restore the pen to start_position with zero linear/angular velocity.
func reset() -> void:
	_in_flight = false
	_settled_emitted = false
	_oob_emitted = false
	_quiet_time = 0.0
	_pending_impulse = Vector2.ZERO
	global_position = start_position
	rotation = 0.0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	sleeping = false
	# Teleport while physics interpolation is on: snap the interpolation window
	# so the pen does not visually glide back to its start position.
	reset_physics_interpolation()


# --- Physics ----------------------------------------------------------------------

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not _table_rect_valid:
		_try_resolve_table()

	if _pending_impulse != Vector2.ZERO:
		state.apply_central_impulse(_pending_impulse)
		_pending_impulse = Vector2.ZERO

	_update_settle(state)
	_update_oob(state)


## Settle detector: velocity magnitude + angular speed below threshold for
## ~0.25 s of continuous quiet -> emit `settled` once per flight.
func _update_settle(state: PhysicsDirectBodyState2D) -> void:
	if not _in_flight or _settled_emitted or _oob_emitted:
		return
	var lin_sq := state.get_linear_velocity().length_squared()
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


## Geometric "any part off" test (contract §3.2): a capsule is fully on the
## table iff both world-space endpoints of its central segment lie inside the
## table rect shrunk by the capsule radius. Out of bounds = that stops holding.
func _any_part_outside(state: PhysicsDirectBodyState2D) -> bool:
	var body_t: Transform2D = state.get_transform()
	var shape_t: Transform2D = body_t * _shape_local_t
	var p1: Vector2 = shape_t * Vector2(0.0, _pen_half_len)
	var p2: Vector2 = shape_t * Vector2(0.0, -_pen_half_len)
	var inner: Rect2 = _table_rect.grow(-_pen_radius)
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
