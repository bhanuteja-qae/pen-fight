extends SceneTree
class_name SkinShot
## QA capture tool: renders the real scene once per pen-skin pairing and saves
## engine-side frames (no X11 grab, no camera roll), so the pen art can be
## graded and measured at true in-game pixel scale.
##
## Also prints each pen's expected screen position, so the analyser can crop
## exactly where the pen is without guessing.
##
## Run (cwd = game/) - NOTE: no --headless! --headless uses the dummy rendering
## driver, where Viewport.get_texture().get_image() is ALWAYS null and
## RenderingServer.frame_post_draw never fires. Run it against a real X display
## under software rendering instead:
##   DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --path . \
##     --script res://tests/skin_shot.gd
## Writes /tmp/skin_frames/<a>_<b>.png

const PAIRINGS := [
	["bic", "jotter"],
	["jotter", "sharpie"],
	["sharpie", "uniball"],
	["uniball", "bic"],
]
const OUT_DIR := "/tmp/skin_frames"

var _main: Node = null


func _init() -> void:
	call_deferred("_go")


## Grab the root viewport image. Two traps here:
##  * Viewport.get_texture().get_image() returns null until the render target has
##    actually been drawn - a handful of frames is not enough (measured: null at
##    4 process frames, fine at ~30+), so wait generously and retry;
##  * RenderingServer.frame_post_draw NEVER fires under --headless (the dummy
##    renderer never draws), so awaiting it hangs the test forever. Never use it
##    in this project's headless tooling.
func _grab() -> Image:
	for attempt in range(12):
		for i in range(25):
			await process_frame
		var img: Image = root.get_texture().get_image()
		if img != null:
			return img
		print("  (viewport image still null after ~%d frames)" % ((attempt + 1) * 25))
	return null


func _go() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	# WARM-UP: under software rendering the root viewport returns a null image
	# until the first full draw completes, which takes a couple of hundred
	# frames for this scene (measured) - wait it out explicitly.
	for i in range(200):
		await process_frame
	print("warm-up done, image null? ", root.get_texture().get_image() == null)

	for pair in PAIRINGS:
		var a: String = pair[0]
		var b: String = pair[1]
		var ok_a: bool = _main.set_pen_skin("red", a)
		var ok_b: bool = _main.set_pen_skin("blue", b)
		if not ok_a or not ok_b:
			print("SKIN SHOT FAILED: set_pen_skin(%s/%s) rejected" % [a, b])
			quit(1)
			return
		var img: Image = await _grab()
		if img == null:
			print("SKIN SHOT FAILED: viewport image was null (%s/%s)" % [a, b])
			quit(1)
			return
		var path := "%s/%s_%s.png" % [OUT_DIR, a, b]
		img.save_png(path)
		# reference frame with the pens hidden: differencing the two gives the
		# pen's EXACT on-screen silhouette, which is how the sprite is checked
		# against the physics capsule (180x10) rather than eyeballed.
		var red_sprite: Sprite2D = _main.get("pen_red").get_node("Sprite2D")
		var blue_sprite: Sprite2D = _main.get("pen_blue").get_node("Sprite2D")
		red_sprite.visible = false
		blue_sprite.visible = false
		var ref_img: Image = await _grab()
		if ref_img != null:
			ref_img.save_png(path.replace(".png", "_nopen.png"))
		red_sprite.visible = true
		blue_sprite.visible = true
		var red = _main.get("pen_red")
		var blue = _main.get("pen_blue")
		print("captured %s  red_world=%s blue_world=%s canvas_origin=%s"
			% [path, str(red.global_position), str(blue.global_position),
			   str(root.get_canvas_transform().origin)])
	quit(0)
