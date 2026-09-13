extends SceneTree
## Probe: does an off-centre flick (grab near the tip, drag at an angle to the
## barrel) produce ROTATION — and is PhysicsDirectBodyState2D.apply_impulse's
## position argument LOCAL or WORLD space? (docs/ART_AND_FEEL_SPEC.md [VERIFY]
## class question — the engine docs list both "apply_impulse(impulse, position)"
## and "apply_impulse(position, impulse)", so measure, don't guess.)
##
## Fires the red pen with contact_offset=+1.0 (cap end) and a drag direction
## SKEW to the barrel (45°). A centred hit gives no torque; the off-centre hit
## MUST give angular velocity for the "slide while rotating" feel.
## Run: godot --headless --path game --script res://tests/impulse_offset_probe.gd

const POWER: float = 1.0
const CONTACT: float = 1.0          # cap end
const FRAMES: int = 8

var _pen: PenBody = null
var _frame: int = 0
var _fired: bool = false
var _done: bool = false

func _init() -> void:
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	_pen = _search_pens(root, "red")
	if _pen == null:
		print("probe: no red pen found")
		quit(1)
		return
	print("probe: pen idle linear=%s angular=%.3f" % [_pen.linear_velocity, _pen.angular_velocity])
	physics_frame.connect(_on_physics_frame)

func _on_physics_frame() -> void:
	if _done:
		return
	_frame += 1
	if not _fired:
		_fired = true
		# 45° drag direction — skew to the barrel, so an off-centre contact
		# MUST transfer torque. (Vector2.RIGHT would be parallel -> no spin.)
		var dir := Vector2.RIGHT.rotated(deg_to_rad(45.0))
		_pen.apply_flick(dir, POWER, CONTACT)
		return
	if _frame >= FRAMES:
		_done = true
		var ang: float = _pen.angular_velocity
		var lin: float = _pen.linear_velocity.length()
		print("probe: after %d frames: linear=%.1f px/s angular=%.4f rad/s" % [_frame, lin, ang])
		print("probe: ROTATES=%s (want YES for an off-centre skew flick)" % ("YES" if absf(ang) > 0.1 else "NO"))
		print("probe: frame: %s" % ("LOCAL" if _pen.get_script_constant("APPLY_IMPULSE_LOCAL_FRAME") else "WORLD"))
		quit(0)

func _search_pens(node: Node, player: String) -> PenBody:
	var body := node as PenBody
	if body != null and body.pen_id == player:
		return body
	for child in node.get_children():
		var found := _search_pens(child, player)
		if found != null:
			return found
	return null