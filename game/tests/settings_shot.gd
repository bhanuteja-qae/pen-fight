extends SceneTree
class_name SettingsShot
## QA capture: render the settings sheet in the real game and save the frame, so
## the screen can be compared against design/mockups/settings.html (and its
## render, mock-settings.png) rather than eyeballed.
##
## NOTE: no --headless. The dummy renderer returns a null viewport image and
## never fires frame_post_draw; this must run against a real (Xvfb) display.
##   DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --path . \
##     --script res://tests/settings_shot.gd
## Writes /tmp/settings_shot.png and /tmp/settings_shot_closed.png

var _main: Node = null


func _init() -> void:
	call_deferred("_go")


func _grab() -> Image:
	for attempt in range(12):
		for i in range(25):
			await process_frame
		var img: Image = root.get_texture().get_image()
		if img != null:
			return img
	return null


func _go() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	for i in range(200):          # warm-up: the first full draw under llvmpipe is slow
		await process_frame
	print("warm-up done, image null? ", root.get_texture().get_image() == null)

	var closed: Image = await _grab()
	if closed != null:
		closed.save_png("/tmp/settings_shot_closed.png")
		print("captured closed-state frame (the entry button must be visible)")

	_main.call("open_settings")
	var opened: Image = await _grab()
	if opened == null:
		print("SETTINGS SHOT FAILED: viewport image null")
		quit(1)
		return
	opened.save_png("/tmp/settings_shot.png")
	var screen: SettingsScreen = _main.get("settings_screen")
	print("captured settings sheet  open=%s  sheet_pos=%s  viewport=%s"
		% [str(screen.is_open()), str(screen.get("_sheet").position),
		   str(root.get_visible_rect().size)])
	quit(0)
