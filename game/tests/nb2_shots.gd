extends SceneTree
class_name Nb2Shot
## NB2 skin mockup capture: swaps the NB2-generated skins (game/assets/nb2/)
## onto the REAL scene and saves engine-side frames at true in-game scale,
## exactly like tests/skin_shot.gd does for the shipped skins.
##
## Uses a DIRECT texture swap (not set_pen_skin) so nothing in the game has to
## know about the experiment; each swap mirrors what set_pen_skin does:
## texture + the shared 1/3 footprint scale, pen AND shadow together.
##
## Run (cwd = game/), NOTE: no --headless! --headless uses the dummy rendering
## driver where Viewport.get_texture().get_image() is always null:
##   ../tools/godot-run.sh --path . --script res://tests/nb2_shots.gd
## Writes frames to OUT_DIR (absolute, outside the repo).

const OUT_DIR := "/home/ubuntu/game-asset-model-research/nb2/frames"
const SCALE := Vector2(1.0 / 3.0, 1.0 / 3.0)
const PAIRINGS := [
	["amber", "cobalt"],
	["cobalt", "graphite"],
	["graphite", "ivory"],
	["ivory", "amber"],
]

var _main: Node = null


func _init() -> void:
	call_deferred("_go")


## Grab the root viewport image; retries because the render target returns
## null until a full draw has completed (same policy as skin_shot.gd).
func _grab() -> Image:
	for attempt in range(12):
		for i in range(25):
			await process_frame
		var img: Image = root.get_texture().get_image()
		if img != null:
			return img
		print("  (viewport image still null after ~%d frames)" % ((attempt + 1) * 25))
	return null


## Swap one player's pen to an NB2 design (pen + shadow, same scale).
func _apply(player: String, design: String) -> bool:
	var side := "Red" if player == "red" else "Blue"
	var sprite: Sprite2D = _main.get_node("Pen%s/Sprite2D" % side)
	var shadow: Sprite2D = _main.get_node("Pen%s/Shadow" % side)
	var pen_path := "res://assets/nb2/pen_%s.png" % design
	var sh_path := "res://assets/nb2/pen_%s_shadow.png" % design
	if not ResourceLoader.exists(pen_path) or not ResourceLoader.exists(sh_path):
		print("NB2 SHOT: missing %s / %s" % [pen_path, sh_path])
		return false
	sprite.texture = load(pen_path)
	sprite.scale = SCALE
	shadow.texture = load(sh_path)
	shadow.scale = SCALE
	return true


func _go() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	# WARM-UP: under software rendering the root viewport returns a null image
	# until the first full draw completes (measured: needs a couple of hundred
	# frames for this scene) - wait it out explicitly.
	for i in range(200):
		await process_frame
	print("warm-up done, image null? ", root.get_texture().get_image() == null)

	# 0) baseline: the game's default skins out of the box (sharpie vs bic)
	var img: Image = await _grab()
	if img == null:
		print("NB2 SHOT FAILED: viewport image null (baseline)")
		quit(1)
		return
	img.save_png("%s/00_defaults_sharpie_vs_bic.png" % OUT_DIR)

	# 1) each NB2 pairing, plus a no-pen reference frame so a diff yields the
	# pen's EXACT on-screen silhouette (checked against the 180x10 capsule).
	for idx in range(PAIRINGS.size()):
		var a: String = PAIRINGS[idx][0]
		var b: String = PAIRINGS[idx][1]
		if not _apply("red", a) or not _apply("blue", b):
			quit(1)
			return
		var shot: Image = await _grab()
		if shot == null:
			print("NB2 SHOT FAILED: viewport image null (%s/%s)" % [a, b])
			quit(1)
			return
		var path := "%s/%02d_nb2_%s_vs_%s.png" % [OUT_DIR, idx + 1, a, b]
		shot.save_png(path)
		var rs: Sprite2D = _main.get_node("PenRed/Sprite2D")
		var bs: Sprite2D = _main.get_node("PenBlue/Sprite2D")
		rs.visible = false
		bs.visible = false
		var ref: Image = await _grab()
		if ref != null:
			ref.save_png(path.replace(".png", "_nopen.png"))
		rs.visible = true
		bs.visible = true
		var red: Node2D = _main.get("pen_red")
		var blue: Node2D = _main.get("pen_blue")
		var ct := root.get_canvas_transform()
		print("captured %s  red_screen=%s rot=%s  blue_screen=%s rot=%s  canvas_origin=%s"
			% [path, str(ct * red.global_position), str(red.rotation),
			   str(ct * blue.global_position), str(blue.rotation), str(ct.origin)])
	quit(0)
