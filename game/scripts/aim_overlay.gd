class_name AimOverlay
extends Node2D
## Aim interface overlay for pen-fight (Phase 1d, docs/UI_AND_PHYSICS_PLAN.md §4
## + assets/design/aim-ui.png).
##
## Everything is anchored on the pen and drawn with the primitive CanvasItem
## draw API + draw_string (ThemeDB.fallback_font), exactly like debug_overlay.gd
## — headless-safe (TextServer/Font resources, no realtime-UI nodes).
##
## Elements (all anchored on the pen):
##   - grab marker ring  on the barrel at the grab point (drawn from the moment
##     a drag starts, before any power builds) — "where you hold the pen"
##   - pull band         grab point -> finger, dashed, dim (the gesture)
##   - launch cone       grab point along the launch direction, translucent
##     0.5 -> 0.04 alpha down its length with a slight outward taper, drawn at
##     its FULL extent so the player sees the whole reachable range. NO
##     trajectory prediction — heading + power only (spec forbids prediction).
##   - power fill        warmer fill inside the cone up to the current power,
##     with a boundary tick at the fill's tip
##   - MAX tick          dashed tick where MAX_IMPULSE clamps (the ceiling),
##     with a small "MAX" label
##   - spin arc          curved arrow near the pen: curl direction =
##     sign(r x J) (the way the pen will actually spin, same sign Godot's
##     angular velocity uses), weight scales with predicted |omega| and the
##     arc vanishes for axial drag (r x J ~= 0) — teaches the corner flick by
##     absence
##   - finger marker     dim ring + dot at the live fingertip (mockup parity)
##
## Z-order (spec §4): pens draw OVER the translucent UI, the grab ring reads ON
## the pen. The world nodes (table sprite, pen sprites) all sit at z_index 0,
## where sibling order decides docking, so _ready() re-inserts this node into
## its parent's child list just BEFORE the first PenBody: above the table,
## below both pen sprites. The ring's slight perpendicular offset off the
## barrel lets it read on top of the pen (the contract's pragmatic option).
##
## No-op when idle: _draw() returns immediately unless show_drag() has been
## fed a live drag since the last clear(). Main drives it per frame with
## set_pen(pen) + show_drag(aim_input.get_drag_info()) and clear() on reset.
##
## PREDICTION BOUNDARY (design pillar 2 — "Unassisted Geometry", see
## docs/design/design-pillars.md): the overlay may show the player what their OWN
## grip is doing — heading, power, and the spin the grab offset will produce —
## and must NEVER show what the shot will DO: no predicted path, no endpoint, no
## prior-shot ghost trail, no bank line. The spin arc is inside the line because
## it reads out the player's input; the launch cone's open far end exists for the
## same reason ("reads as direction, not predicted path"). A change that draws
## where the pen will END UP crosses the line and deletes the skill expression
## this game is built on. If you are adding to the overlay, re-read this first.

const FONT_SIZE: int = 11

# --- Launch cone / power fill (mockup numbers, docs §4) -------------------------
## Full-power cone length (px) — where MAX_IMPULSE clamps. [TUNE]
const CONE_MAX_LEN := 188.0
## Cone half-width at the grab point and at its far end (slight outward taper).
const CONE_HALF_W_NEAR := 11.0
const CONE_HALF_W_FAR := 26.0
## Translucent alpha along the cone: bright at the pen, near-invisible at the tip.
const CONE_ALPHA_NEAR := 0.5
const CONE_ALPHA_FAR := 0.04
## The warmer power fill sits this many px inside the hull.
const FILL_INSET := 2.0

# --- Pull band -------------------------------------------------------------------
const BAND_HALF_W_NEAR := 9.0
const BAND_HALF_W_FAR := 5.0

# --- Grab ring -------------------------------------------------------------------
const RING_RADIUS := 14.0
const RING_DOT_RADIUS := 3.0
## Perpendicular nudge off the barrel so the ring reads ON the pen despite the
## overlay layer sitting beneath the pen sprites. [TUNE]
const RING_OFFSET := 5.0

# --- Spin arc --------------------------------------------------------------------
const SPIN_ARC_RADIUS := 60.0
const SPIN_ARC_SPAN_DEG := 100.0
## Arc midpoint sits this many degrees behind the launch direction (mockup
## parity: clear of the pull band / finger cluster). [TUNE]
const SPIN_ARC_TWIST_DEG := 36.0
const SPIN_ARC_SEGMENTS := 14
## Predicted |omega| that maps to a full-weight arc. = 50 rad/s at a full-power
## tip grab at the new scale (docs §3 physics card: r=85, J=1600, I=2700).
const SPIN_MAX_OMEGA := 50.0
## Arc vanishes below this predicted |omega| (rad/s) — makes axial drag and
## centre grabs read as "no spin" even at high power (r x J ~= 0).
const SPIN_VANISH_OMEGA := 2.5

# --- Colors (from aim-ui.html) -----------------------------------------------------
const COLOR_CONN_NEAR := Color(0.74, 0.83, 1.00, CONE_ALPHA_NEAR)   # #bcd4ff
const COLOR_CONN_FAR := Color(0.56, 0.71, 0.96, CONE_ALPHA_FAR)     # #8fb4f5
const COLOR_FILL_NEAR := Color(1.00, 0.90, 0.70, 0.45)              # #ffe6b4
const COLOR_FILL_FAR := Color(1.00, 0.70, 0.28, 0.45)               # #ffb347
const COLOR_BAND := Color(0.92, 0.95, 1.00)                          # #eaf2ff
const COLOR_RING := Color(0.92, 0.95, 1.00)                          # #eaf2ff
const COLOR_SPIN := Color(0.62, 0.91, 0.77)                          # #9fe8c4
const COLOR_MAX := Color(1.00, 0.50, 0.60)                           # #ff8098
const COLOR_FINGER := Color(0.66, 0.77, 1.00)                        # #a8c8ff

var _pen: PenBody = null
var _font: Font = null
var _has_drag: bool = false
var _drag: Dictionary = {}
## Idle turn cue state (see show_turn).
var _turn_visible: bool = false
var _turn_label: String = ""


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_arrange_z()


## Z-order contract (§4): translucent UI under the pens, ring on top of the pen.
## The world is flat z_index 0 (table sprite, pen sprites — main.tscn), so
## sibling ORDER decides: re-insert this node right before the first PenBody
## in the parent's child list — above the table, beneath every pen sprite.
func _arrange_z() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var insert_at := -1
	for i in parent.get_child_count():
		var child := parent.get_child(i)
		if child is PenBody or String(child.name).begins_with("Pen"):
			insert_at = i
			break
	if insert_at < 0:
		return  # no pens in this parent: leave sibling order as-wired
	parent.move_child(self, insert_at)


## The pen everything anchors on. Re-draw so a pen change is picked up at once.
func set_pen(pen: PenBody) -> void:
	_pen = pen
	queue_redraw()


## Feed the live gesture state (AimInput.get_drag_info()). An empty dict or one
## with dragging == false is treated as "clear" — the overlay is a no-op when
## there is no active drag.
func show_drag(info: Dictionary) -> void:
	if info.is_empty() or not info.get("dragging", false):
		clear()
		return
	_drag = info
	_has_drag = true
	queue_redraw()


## Drop all drag state: anything already drawn disappears next frame.
func clear() -> void:
	if _has_drag or not _drag.is_empty():
		_drag = {}
		_has_drag = false
		queue_redraw()


## Idle turn cue (review, UX-1/UX-2): during AIM with NO drag, highlight the
## active pen so whose-turn is legible at a glance (the mockup's "YOUR FLICK"
## banner + pen highlight; full 3-cue system — edge glow + opponent chip — is
## roadmap UI, this is the minimal in-code slice). `label` is glyph-safe plain
## text (e.g. "Sharpie" / "Bic" — the design on the table). Drawn only when
## no drag is active; a
## show_drag() call overrides it until clear().
func show_turn(label: String) -> void:
	if _pen == null:
		return
	_turn_label = label
	_turn_visible = true
	queue_redraw()


## Clear the idle turn cue (round over / gate up).
func clear_turn() -> void:
	if not _turn_visible:
		return
	_turn_visible = false
	_turn_label = ""
	queue_redraw()


## True while an idle turn cue is visible.
func is_turn_visible() -> bool:
	return _turn_visible


func _draw() -> void:
	if _pen == null:
		return
	if not _has_drag:
		_draw_turn_cue()
		return
	var grab: Vector2 = _grab_point(float(_drag.get("grab_offset", 0.0)))
	var current: Vector2 = _drag.get("current_pos", Vector2.ZERO)
	var direction: Vector2 = _drag.get("direction", Vector2.ZERO)
	var power: float = clampf(float(_drag.get("power", 0.0)), 0.0, 1.0)

	# The gesture comes first (dim), the consequence over it (translucent),
	# the ring last so it stays crisp at the grab point.
	_draw_pull_band(grab, current)
	_draw_finger(current)
	if direction != Vector2.ZERO and power > 0.0:
		_draw_launch_cone(grab, direction)
		_draw_power_fill(grab, direction, power)
		_draw_max_tick(grab, direction)
		_draw_spin_arc(float(_drag.get("grab_offset", 0.0)), direction, power)
	_draw_grab_ring(grab)


## Idle whose-turn cue (review UX-1): a dashed oval around the active pen plus
## a "YOUR FLICK" banner near it — the minimal in-code slice of the mockup's
## 3-cue system, shown between AIM turns so the hot-seat question ("is it my
## turn?") never goes unanswered. Overridden the moment a drag starts.
const TURN_OVAL_RADIUS := 46.0
const TURN_OVAL_DASH := 6.0
const TURN_OVAL_COLOR := Color(0.92, 0.95, 1.0, 0.55)
const TURN_BANNER_TEXT := "YOUR FLICK"
const TURN_BANNER_COLOR := Color(0.92, 0.95, 1.0)

func _draw_turn_cue() -> void:
	if not _turn_visible or _turn_label == "":
		return
	var center: Vector2 = _pen.global_position
	_dashed_oval(center, TURN_OVAL_RADIUS, TURN_OVAL_DASH, TURN_OVAL_COLOR, 2.0)
	# Banner above-left of the pen so it does not sit under the player's hand.
	var banner_pos: Vector2 = center + Vector2(-TURN_OVAL_RADIUS * 0.7, -TURN_OVAL_RADIUS * 1.6)
	draw_string(_font, banner_pos, TURN_BANNER_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TURN_BANNER_COLOR)
	if _turn_label != "":
		draw_string(_font, banner_pos + Vector2(0.0, TURN_OVAL_RADIUS * 0.62),
			_turn_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(0.66, 0.77, 1.0))


func _dashed_oval(center: Vector2, radius: float, _dash: float, color: Color, width: float) -> void:
	var pts := PackedVector2Array([])
	var n := 40
	for i in range(n + 1):
		var ang := TAU * float(i) / float(n)
		pts.append(center + Vector2.from_angle(ang) * radius)
	# Emit alternating dash segments by walking the polyline.
	var on := true
	for seg in range(n):
		var a: Vector2 = pts[seg]
		var b: Vector2 = pts[(seg + 1) % n]
		if on:
			draw_line(a, b, color, width)
		on = not on


# --- Geometry helpers ---------------------------------------------------------------

## The pen's barrel axis in world space (its local +X; the scene capsule is
## rotated 90 deg so the barrel runs along X — see aim_input._contact_offset).
func _pen_axis() -> Vector2:
	return Vector2.RIGHT.rotated(_pen.global_rotation)


## World position of the grab point on the barrel: contact_offset in [-1, 1]
## along the barrel from the pen's origin, clamped like PenBody.apply_flick.
func _grab_point(offset: float) -> Vector2:
	var axis: Vector2 = _pen_axis()
	return _pen.global_position + axis * (clampf(offset, -1.0, 1.0) * _pen.get_half_len())


# --- Element drawers ------------------------------------------------------------------

## Ring on the barrel at the grab point. Drawn slightly off the barrel centerline
## (perpendicular nudge) so it is not swallowed by the pen sprite drawn above us.
func _draw_grab_ring(grab: Vector2) -> void:
	var perp: Vector2 = _pen_axis().orthogonal().normalized()
	var center: Vector2 = grab + perp * RING_OFFSET
	draw_circle(center, RING_RADIUS, Color(COLOR_RING, 0.16))
	draw_arc(center, RING_RADIUS, 0.0, TAU, 40, Color(COLOR_RING, 0.9), 2.0, true)
	draw_circle(center, RING_DOT_RADIUS, Color(COLOR_RING, 0.9))


## Dim tapered band from the grab point back to the finger, with a dashed axis
## line: the gesture being made.
func _draw_pull_band(grab: Vector2, current: Vector2) -> void:
	var seg: Vector2 = current - grab
	var total: float = seg.length()
	if total < 2.0:
		return
	var n: Vector2 = seg / total
	var perp: Vector2 = n.orthogonal().normalized()
	var pts := PackedVector2Array([
		grab + perp * BAND_HALF_W_NEAR,
		current + perp * BAND_HALF_W_FAR,
		current - perp * BAND_HALF_W_FAR,
		grab - perp * BAND_HALF_W_NEAR,
	])
	var cols := PackedColorArray([
		Color(COLOR_BAND, 0.40), Color(COLOR_BAND, 0.10),
		Color(COLOR_BAND, 0.10), Color(COLOR_BAND, 0.40),
	])
	draw_polygon(pts, cols)
	_dashed_line(grab, current, Color(COLOR_BAND, 0.30), 1.2, 6.0, 5.0)


## Translucent launch cone at its full extent (the whole reachable range — the
## power fill marks the current power inside it). 0.5 -> 0.04 alpha along the
## axis, slight outward taper, open far end. Heading + power only, no
## trajectory prediction.
func _draw_launch_cone(grab: Vector2, direction: Vector2) -> void:
	var dir: Vector2 = direction.normalized()
	var perp: Vector2 = dir.orthogonal().normalized()
	var tip: Vector2 = grab + dir * CONE_MAX_LEN
	var pts := PackedVector2Array([
		grab + perp * CONE_HALF_W_NEAR,
		tip + perp * CONE_HALF_W_FAR,
		tip - perp * CONE_HALF_W_FAR,
		grab - perp * CONE_HALF_W_NEAR,
	])
	var cols := PackedColorArray([COLOR_CONN_NEAR, COLOR_CONN_FAR, COLOR_CONN_FAR, COLOR_CONN_NEAR])
	draw_polygon(pts, cols)
	# Faint taper edges (open far end reads as direction, not predicted path).
	var edge := Color(0.81, 0.88, 1.0, 0.30)
	draw_line(grab + perp * CONE_HALF_W_NEAR, tip + perp * CONE_HALF_W_FAR, edge, 1.5, true)
	draw_line(grab - perp * CONE_HALF_W_NEAR, tip - perp * CONE_HALF_W_FAR, edge, 1.5, true)


## Warmer fill inside the cone up to the current power, with a bright boundary
## tick where the fill ends.
func _draw_power_fill(grab: Vector2, direction: Vector2, power: float) -> void:
	var dir: Vector2 = direction.normalized()
	var perp: Vector2 = dir.orthogonal().normalized()
	var len: float = CONE_MAX_LEN * power
	var w_far: float = lerpf(CONE_HALF_W_NEAR, CONE_HALF_W_FAR, power) - FILL_INSET
	var tip: Vector2 = grab + dir * len
	var pts := PackedVector2Array([
		grab + perp * (CONE_HALF_W_NEAR - FILL_INSET),
		tip + perp * w_far,
		tip - perp * w_far,
		grab - perp * (CONE_HALF_W_NEAR - FILL_INSET),
	])
	var cols := PackedColorArray([COLOR_FILL_NEAR, COLOR_FILL_FAR, COLOR_FILL_FAR, COLOR_FILL_NEAR])
	draw_polygon(pts, cols)
	draw_line(tip + perp * w_far, tip - perp * w_far, Color(1.0, 0.7, 0.28, 0.9), 2.5, true)


## Dashed tick at the MAX_IMPULSE clamp plus a small "MAX" label — the ceiling.
func _draw_max_tick(grab: Vector2, direction: Vector2) -> void:
	var dir: Vector2 = direction.normalized()
	var perp: Vector2 = dir.orthogonal().normalized()
	var tip: Vector2 = grab + dir * CONE_MAX_LEN
	_dashed_line(tip + perp * CONE_HALF_W_FAR, tip - perp * CONE_HALF_W_FAR, Color(COLOR_MAX, 0.8), 2.0, 4.0, 4.0)
	if _font != null:
		draw_string(_font, tip + dir * 10.0, "MAX", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(COLOR_MAX, 0.9))


## Curved arrow near the pen showing the predicted spin (docs §3): curl
## direction = sign(r x J) — the same sign Godot's angular velocity uses —
## weight scales with predicted |omega| = (r x J) / I, and it vanishes for
## axial drag (r x J ~= 0), teaching the corner flick by absence.
##   r = grab arm along the barrel (world frame)
##   J = direction * power * MAX_IMPULSE  (what apply_flick will receive)
##   I = m * L^2 / 12 with m = 1 (PenBody physics, docs §3 physics card)
func _draw_spin_arc(grab_offset: float, direction: Vector2, power: float) -> void:
	var axis: Vector2 = _pen_axis()
	var half: float = _pen.get_half_len()
	var len_px: float = half * 2.0
	var inertia: float = len_px * len_px / 12.0
	if inertia <= 0.0001:
		return  # degenerate pen (no barrel): nothing to predict
	var r_world: Vector2 = axis * (clampf(grab_offset, -1.0, 1.0) * half)
	var j_world: Vector2 = direction * power * PenBody.MAX_IMPULSE
	var cross := r_world.cross(j_world)
	var omega: float = cross / inertia  # predicted rad/s, signed
	if absf(omega) < SPIN_VANISH_OMEGA:
		return
	var weight: float = clampf(absf(omega) / SPIN_MAX_OMEGA, 0.0, 1.0)
	# Godot angle increases toward +Y (down on screen) = visually clockwise, so
	# positive cross (positive omega) curls clockwise, negative counter-clockwise.
	var dir_sign := -1.0 if cross < 0.0 else 1.0
	var mid_angle: float = direction.angle() - deg_to_rad(SPIN_ARC_TWIST_DEG)
	var pts := _arc_points(_pen.global_position, SPIN_ARC_RADIUS, mid_angle, deg_to_rad(SPIN_ARC_SPAN_DEG) * 0.5, dir_sign)
	var col := Color(COLOR_SPIN, 0.30 + 0.62 * weight)
	var width := 1.5 + 2.2 * weight
	draw_polyline(pts, col, width, true)
	_draw_arrowhead(pts, col, 5.0 + 5.0 * weight)


## Dim ring + dot at the live fingertip (mockup parity: "this is your finger").
func _draw_finger(current: Vector2) -> void:
	draw_arc(current, 13.0, 0.0, TAU, 32, Color(COLOR_FINGER, 0.50), 1.6, true)
	draw_circle(current, 2.6, Color(COLOR_RING, 0.8))


# --- Small drawing helpers -------------------------------------------------------------

## Arc sampled as a polyline; dir_sign +1 sweeps increasing angle (visual
## clockwise), -1 the other way — so the curl follows sign(r x J).
func _arc_points(center: Vector2, radius: float, mid_angle: float, half_span: float, dir_sign: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var a0: float = mid_angle - half_span
	for i in SPIN_ARC_SEGMENTS + 1:
		var t: float = float(i) / float(SPIN_ARC_SEGMENTS)
		var ang: float = a0 + (half_span * 2.0) * t * dir_sign
		pts.append(center + Vector2.from_angle(ang) * radius)
	return pts


## Filled V arrowhead at the last polyline point, pointing along travel.
func _draw_arrowhead(pts: PackedVector2Array, color: Color, size: float) -> void:
	if pts.size() < 2 or size <= 0.0:
		return
	var tip: Vector2 = pts[pts.size() - 1]
	var prev: Vector2 = pts[pts.size() - 2]
	var back: Vector2 = -(tip - prev).normalized()
	var p1: Vector2 = tip + back.rotated(0.45) * (size * 2.2)
	var p2: Vector2 = tip + back.rotated(-0.45) * (size * 2.2)
	draw_colored_polygon(PackedVector2Array([tip, p1, p2]), color)


## Draws a segment-dash line (dash px on, gap px off) from `from` to `to`.
func _dashed_line(from: Vector2, to: Vector2, color: Color, width: float, dash: float, gap: float) -> void:
	var seg: Vector2 = to - from
	var total: float = seg.length()
	if total < 1.0:
		return
	var n: Vector2 = seg / total
	var dist: float = 0.0
	while dist < total:
		var end: float = minf(dist + dash, total)
		draw_line(from + n * dist, from + n * end, color, width, true)
		dist = end + gap
