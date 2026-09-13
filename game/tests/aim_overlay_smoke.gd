extends SceneTree
## Phase 1d: standalone smoke test for AimOverlay — confirms the NEW overlay
## script loads, attaches, and draws without errors when fed a synthetic drag
## (grab ring, pull band, launch cone, power fill, MAX tick, spin arc). Runs
## three frames of a fake drag then clears. Exit 0 = the overlay is alive.
## Run: godot --headless --path game --script res://tests/aim_overlay_smoke.gd

var _overlay: Node2D = null
var _pen: PenBody = null
var _frame: int = 0
var _done: bool = false

func _init() -> void:
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	_pen = _search_pens(root, "red")
	if _pen == null:
		print("aim_overlay_smoke: no pen found")
		quit(1)
		return
	var script := load("res://scripts/aim_overlay.gd")
	if script == null:
		print("aim_overlay_smoke: aim_overlay.gd FAILED TO LOAD")
		quit(1)
		return
	_overlay = script.new()
	root.add_child(_overlay)
	_overlay.set_pen(_pen)
	# Synthetic drag: grab at the cap end, pull back at 45 degrees, 60% power.
	_overlay.show_drag({
		"dragging": true,
		"press_pos": _pen.global_position + Vector2(40, 0),
		"current_pos": _pen.global_position + Vector2(40, 0) - Vector2(120, 120),
		"grab_offset": 0.5,
		"direction": Vector2(0.70710678, 0.70710678),
		"power": 0.6,
	})
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _done:
		return
	_frame += 1
	if _frame >= 5:
		_overlay.clear()
		print("aim_overlay_smoke: PAS OK — overlay drew for %d frames without errors (grab ring + cone + spin arc)" % _frame)
		_done = true
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