extends SceneTree
class_name StateShots
## QA capture: labeled frames of the REAL game in each UX state, so "how does it
## look right now" can be answered from pixels instead of from the node tree.
##
## Run (cwd = game/, and NOT --headless — the dummy renderer hands back a null
## viewport image):
##   DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --path . \
##     --script res://tests/state_shots.gd
## Writes /tmp/state_shots/<label>.png and prints one line per shot.
##
## The autoplay harness (PENFIGHT_AUTOPLAY=1) is deliberately NOT used here: its
## auto-tap dismisses every gate inside the same _process tick that raised it, so
## a gate frame can never be observed. This script drives the human path instead
## — inject a real touch drag, then tap each gate itself — and idles out the
## FORFEIT_TIMEOUT (15s) between turns, which is what makes a fast match over.
##
## Shots taken:
##   01_aim_idle        fresh AIM turn, no drag -> idle turn cue
##   02_aim_drag        live touch drag (real AimInput path) -> aim overlay
##   03_shot_released   the instant after release -> pen in flight
##   gate_NN            every gate the match actually raises, in order
##   match_over         the match-over gate (carries the durable series line)

const OUT_DIR := "/tmp/state_shots"
const DRAG_PULL_PX := 130.0
const MAX_WALL_FRAMES := 60 * 240   # 240s of simulated time, hard stop

## PENFIGHT_SHOTS_MAX_GATES: stop after this many gate shots (0 = until match
## over). Shortens a full-best-of-5 capture to ~20s for iteration and for
## diagnosing exit-time warnings that only print once the run ends.
var _max_gates: int = 0

var _main: Node = null
var _gate_showing_prev := false
var _gate_count := 0


func _init() -> void:
	call_deferred("_go")


## Grab the root viewport image; the render target needs real frames under
## llvmpipe before it hands back anything (measured: null earlier on).
func _grab() -> Image:
	for attempt in range(12):
		for i in range(20):
			await process_frame
		var img: Image = root.get_texture().get_image()
		if img != null:
			return img
	return null


func _shot(label: String) -> void:
	var img: Image = await _grab()
	if img == null:
		print("SHOT FAILED (null viewport image): %s" % label)
		return
	var path := "%s/%s.png" % [OUT_DIR, label]
	img.save_png(path)
	print("shot %s  phase=%s gate=%s" % [label, _phase(), str(_main.get("_gate_showing"))])


func _phase() -> String:
	return str(_main.get("turn_state").state().get("phase", ""))


func _gate_showing() -> bool:
	return bool(_main.get("_gate_showing"))


func _gate_label() -> String:
	var gate: Node = _main.get("turn_gate")
	var lbl: Label = gate.get("_label") as Label
	return "" if lbl == null else lbl.text


## Mechanical check on the gate prompt: every rendered line must fit inside the
## inset viewport width. This is the regression gate for the clipped match-over
## banner (measured 1276 px wide on a 1280 viewport before the fix) — a pixel
## bbox comparison alone cannot tell "fits" from "clipped edge-to-edge".
func _gate_fit_report() -> String:
	var gate: Node = _main.get("turn_gate")
	var lbl: Label = gate.get("_label") as Label
	if lbl == null:
		return "FIT UNKNOWN (no gate label)"
	var font: Font = lbl.get_theme_font("font")
	if font == null:
		return "FIT UNKNOWN (no font)"
	var fs: int = lbl.get_theme_font_size("font_size")
	var limit: float = root.get_visible_rect().size.x - 2.0 * 32.0
	var widest := 0.0
	var lines: PackedStringArray = lbl.text.split("\n")
	for line in lines:
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return "%s  lines=%d widest=%.1f limit=%.1f font_size=%d" % [
		"FIT OK" if widest <= limit else "FIT FAIL", lines.size(), widest, limit, fs]


func _screen_of(world_pos: Vector2) -> Vector2:
	return root.get_canvas_transform() * world_pos


func _touch_world(index: int, pressed: bool, world_pos: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = _screen_of(world_pos)
	root.push_input(ev, true)


func _drag_world(index: int, world_pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = _screen_of(world_pos)
	root.push_input(ev, true)


func _await_aim(max_frames: int) -> bool:
	for i in range(max_frames):
		await physics_frame
		if _phase() == "AIM" and _main.get("_active_pen") != null:
			return true
	return false


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_max_gates = int(OS.get_environment("PENFIGHT_SHOTS_MAX_GATES"))
	var packed: PackedScene = load("res://scenes/main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	for i in range(220):      # the first full llvmpipe draw is slow
		await process_frame
	print("warm-up done  phase=%s" % _phase())

	# --- 1. idle AIM turn, with the turn cue up -----------------------------
	if await _await_aim(240):
		await _shot("01_aim_idle")

	# --- 2/3. one real slingshot: mid-drag, then in flight -------------------
	var pen: Node2D = _main.call("_active_pen")
	if pen != null:
		var press: Vector2 = pen.global_position
		var pull: Vector2 = press - Vector2(DRAG_PULL_PX, -DRAG_PULL_PX * 0.55)
		_touch_world(0, true, press)
		_drag_world(0, (press + pull) * 0.5)
		_drag_world(0, pull)
		await _shot("02_aim_drag")
		_touch_world(0, false, pull)
		for i in range(3):
			await process_frame
		await _shot("03_shot_released")

	# --- 4. every gate the match raises, until match over -------------------
	var frames := 0
	while frames < MAX_WALL_FRAMES:
		await process_frame
		frames += 1
		var showing := _gate_showing()
		if showing and not _gate_showing_prev:
			_gate_count += 1
			var over := bool(_main.get("_match_over"))
			var label := "match_over" if over else "gate_%02d" % _gate_count
			await _shot(label)
			print("   gate text: %s   (match_over=%s)" % [_gate_label(), str(over)])
			print("   %s" % _gate_fit_report())
			if over:
				break
			if _max_gates > 0 and _gate_count >= _max_gates:
				print("stopping early: PENFIGHT_SHOTS_MAX_GATES=%d" % _max_gates)
				break
			# Acknowledge exactly like a human tap does (TurnGate.tapped path).
			await process_frame
			_main.call("_on_gate_tapped")
		_gate_showing_prev = _gate_showing()
	print("done: %d gate shots, %d frames" % [_gate_count, frames])
	# Explicit teardown rather than relying on SceneTree cleanup order. Note: the
	# "1 ObjectDB instance was leaked at exit" warning is NOT this node — it is the
	# audio pool's AudioStreamGeneratorPlayback (scripts/audio.gd); identified with
	# --verbose, still present with Main freed, and recorded for #13.
	_main.free()
	await process_frame
	quit(0)
