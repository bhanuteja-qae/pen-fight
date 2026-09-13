extends SceneTree
## Probe: given an impulse magnitude M applied to the active pen as a central
## impulse on the default-mass (1.0) RigidBody2D, what linear velocity does the
## pen gain? Calibrates AutoFlick's random power range so autoplay flicks
## actually leave the table (docs/RESEARCH.md §4 tuning).
## Run: godot --headless --path game --script res://tests/impulse_probe.gd

const IMPULSES: Array = [1.0, 10.0, 100.0, 1000.0, 10000.0, 100000.0, 1000000.0]

var _pen: PenBody = null
var _idx: int = 0
var _fire_frames_left: int = 0
var _measure_frames_left: int = 0
var _done: bool = false

func _init() -> void:
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	_pen = _find_pen(main, "red")
	if _pen == null:
		print("probe: no red pen found")
		quit(1)
		return
	physics_frame.connect(_on_physics_frame)

func _on_physics_frame() -> void:
	if _done:
		return
	if _measure_frames_left > 0:
		_measure_frames_left -= 1
		if _measure_frames_left == 0:
			var vel: Vector2 = _pen.linear_velocity
			print("impulse=%10.0f -> speed=%10.1f px/s" % [IMPULSES[_idx], vel.length()])
			_idx += 1
			if _idx >= IMPULSES.size():
				_done = true
				print("probe done")
				quit(0)
				return
			_pen.reset()
		return
	if _fire_frames_left > 0:
		_fire_frames_left -= 1
		return
	# Fire the next impulse. apply_flick queues it; the physics state applies it
	# on the next _integrate_forces.
	var mag: float = IMPULSES[_idx]
	_pen.apply_flick(Vector2.RIGHT, mag)
	_fire_frames_left = 2
	_measure_frames_left = 3

func _find_pen(node: Node, id: String) -> PenBody:
	var body := node as PenBody
	if body != null and body.pen_id == id:
		return body
	for child in node.get_children():
		var f := _find_pen(child, id)
		if f != null:
			return f
	return null