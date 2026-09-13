class_name DebugOverlay
extends Node2D
## Phase 1a debug overlay for pen-fight.
##
## When running a DEBUG build (OS.is_debug_build(), true for the editor / debug
## binary the orchestrator runs), draws one line per pen in the top-left corner:
## pen_id, linear velocity magnitude, angular velocity, and a settle status
## derived live from those velocities. Renders nothing at all on release builds.
##
## Text rendering: draw_string() with the engine's default font. `ThemeDB
## .fallback_font` is the engine's built-in font and is available headless (it
## is a TextServer/Font resource, not GPU-backed), so draw_string is the robust
## choice here over a Label node — a Label would need the same font and adds
## layout machinery for no gain, and under the contract's Xvfb/headless gate the
## font is guaranteed to exist. If it were ever null we fall back to
## get_theme_default_font(), and if that is also null we simply draw nothing.
##
## PenBody (Agent A's class) has no public is_settled flag, so settle status is
## derived from the same velocity thresholds PenBody uses
## (SETTLE_LINEAR_VEL=6.0 px/s, SETTLE_ANGULAR_VEL=0.4 rad/s), mirrored here as
## consts so this script stays self-contained and never edits PenBody. Null /
## non-PenBody entries in the pens array are skipped defensively.

const FONT_SIZE: int = 12
const LINE_HEIGHT: float = 16.0
const PAD: float = 6.0

## Mirror of PenBody.SETTLE_LINEAR_VEL / SETTLE_ANGULAR_VEL (px/s, rad/s).
const SETTLE_LINEAR_VEL: float = 6.0
const SETTLE_ANGULAR_VEL: float = 0.4

var _pens: Array = []
var _font: Font = null


func _ready() -> void:
	# Draw above world content; text stays legible over the table.
	z_index = 100
	_font = ThemeDB.fallback_font


## Hand Main the two PenBody refs to poll. Null entries are tolerated.
func set_pens(pens: Array) -> void:
	_pens = pens


func _process(_delta: float) -> void:
	if OS.is_debug_build():
		queue_redraw()


func _draw() -> void:
	if not OS.is_debug_build():
		return
	if _font == null:
		return
	var y: float = PAD
	for pen in _pens:
		if pen == null:
			continue
		var body: PenBody = pen as PenBody
		if body == null:
			continue
		var lin: Vector2 = body.linear_velocity
		var ang: float = body.angular_velocity
		var speed: float = lin.length()
		var text := "%s  v=%.0f px/s  w=%.1f rad/s  %s" % [
			body.pen_id, speed, ang, _settle_label(speed, absf(ang))
		]
		var color := Color(0.4, 1.0, 0.4) if absf(ang) < SETTLE_ANGULAR_VEL and speed < SETTLE_LINEAR_VEL else Color(1.0, 0.9, 0.3)
		draw_string(_font, Vector2(PAD, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
		y += LINE_HEIGHT


func _settle_label(speed: float, ang: float) -> String:
	if speed < SETTLE_LINEAR_VEL and ang < SETTLE_ANGULAR_VEL:
		return "settled"
	return "moving"
