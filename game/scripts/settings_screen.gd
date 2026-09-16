extends CanvasLayer
class_name SettingsScreen
## The settings sheet — a ruled binder-paper page lying on the classroom desk.
##
## Geometry is taken from Claude's design mockup, assets/design/mockups/
## settings.html (a 1600x800 SVG poster: classroom backdrop, two showcase pens,
## and the sheet centred at (800,430) rotated -1.2 deg). Values below are the
## mockup's own card coordinates, unrotated, origin at the sheet's centre:
##
##   sheet         536 x 428, corner radius 4, fill #f4efe2, shadow (+9,+14) 42%
##   ruled lines   14 lines, x -244..244, first at y -150, spacing 27
##   margin rule   vertical, x -196, #d9707f, 1.4 px, 70%
##   punch holes   x -238, y -120 / 0 / +120, r 9
##   title         "Settings", x -150, baseline y -158, 44 px, #22304d, bold
##   rows          labels x -150, 21 px; baselines -90, -36, +18, +72, +126
##   toggles       64 x 30 pill, rx 15, x 180..244, top = baseline - 19
##   values        right-aligned at x 244, 19 px, #4a5a78
##   BACK          150 x 52, rx 5, #22304d, 22 px label #f4efe2, bottom-left
##
## Two deliberate differences from the mockup, both called out in code below:
##   1. the sheet is 482 tall, not 428 — one extra ruled row, because a hot-seat
##      game needs a pen row PER PLAYER where the mockup's single-player framing
##      had one "My pen" row;
##   2. the toggles use the conventional switch (knob left = off, right = on,
##      filled pill = on). The mockup draws the ON knob centred in a filled pill
##      and the OFF knob inset in an outline, which reads ambiguously on a phone.
##
## The screen owns no game state: it reads a SettingsStore, renders it, and
## emits intents (row_pressed / closed). Main applies them and calls refresh().

signal row_pressed(row: int)
signal closed

enum Row { SOUND, HAPTICS, SHAKE, MATCH_LENGTH, PEN_RED, PEN_BLUE }

const SHEET_W := 536.0
const SHEET_H := 482.0
const SHEET_TILT_DEG := -1.2

const ROW_BASELINES: Array[float] = [124.0, 178.0, 232.0, 286.0, 340.0, 394.0]
const ROW_LABEL_X := 118.0
const VALUE_RIGHT_X := 512.0
const VALUE_LEFT_X := 300.0
const TOGGLE_LEFT := 448.0
const TOGGLE_W := 64.0
const TOGGLE_H := 30.0
const TOGGLE_TOP_DY := -19.0
const KNOB_R := 11.0
const HOLE_X := 30.0
## Three punch holes, evenly distributed down the page. (Four, aligned to the
## row rhythm instead, read as bullet points next to rows rather than as binder
## holes - a fidelity note from the mockup comparison.)
const HOLE_YS: Array[float] = [94.0, 241.0, 388.0]
const HOLE_R := 9.0
const RULE_X0 := 24.0
const RULE_X1 := 512.0
const RULE_Y0 := 64.0
const RULE_DY := 27.0
const RULE_COUNT := 16
const MARGIN_RULE_X := 72.0
## Title top: the mockup's 44 px "Settings" ink starts 26 px below the page top
## (measured on the rendered mockup, 1:1). A Godot Label carries extra leading
## above the glyphs, so the control sits 11 px higher to land the ink in the same
## place — the value was measured against the mockup, not guessed.
const TITLE_POS := Vector2(118.0, 11.0)
const BACK_RECT := Rect2(108.0, 418.0, 150.0, 52.0)
const HIT_TOP_DY := -26.0
const HIT_BOTTOM_DY := 10.0

const PAPER := Color("f4efe2")
const INK := Color("22304d")
const VALUE_COLOR := Color("4a5a78")
const RULE_COLOR := Color("a9bdd4")
const MARGIN_COLOR := Color("d9707f")
const HOLE_COLOR := Color("241f1a")
const SCRIM := Color(0, 0, 0, 0.42)
const ENTRY_SIZE := Vector2(46, 46)

var _store: SettingsStore = null
## Placeholders only: Main pushes the real names with set_player_names() — the
## design on the table, never the red/blue slot id. Kept in step with
## Main.DEFAULT_SKINS so a sheet that has not been pushed yet still agrees
## with the art.
var _p1_name: String = "Sharpie"
var _p2_name: String = "Bic"
var _scrim: ColorRect = null
var _sheet: Control = null
var _labels: Array[Label] = []
var _values: Array[Label] = []
var _entry: Button = null
var _pills: Control = null


# ---------------------------------------------------------------- inner drawing
## The paper page: draws every static element itself and hosts the interactive
## children. Kept as an inner class so the drawing constants stay adjacent to the
## layout constants above.
class Sheet:
	extends Control

	var screen: SettingsScreen = null

	const PAPER_TEXTURE := "res://assets/settings_paper.png"

	func _init(screen_ref: SettingsScreen) -> void:
		screen = screen_ref
		custom_minimum_size = Vector2(SettingsScreen.SHEET_W, SettingsScreen.SHEET_H)
		size = custom_minimum_size
		pivot_offset = size * 0.5
		rotation = deg_to_rad(SettingsScreen.SHEET_TILT_DEG)

	func _draw() -> void:
		# Page shadow only (mockup: offset +9,+14, black 42 %). The paper itself -
		# including the ruled lines, the margin rule and the punch holes - is a
		# texture, because the holes must CUT THROUGH to the desk behind: drawing
		# can only add pixels, never erase them. See
		# assets/generate_settings_paper.py.
		var shadow := StyleBoxFlat.new()
		shadow.bg_color = Color(0, 0, 0, 0)
		shadow.shadow_color = Color(0, 0, 0, 0.42)
		shadow.shadow_size = 10
		shadow.shadow_offset = Vector2(9, 14)
		draw_style_box(shadow, Rect2(Vector2.ZERO, size))
		# NOTE: the page itself is a TextureRect NODE, not a draw_texture_rect()
		# call. Under this renderer the call put the page down as SOLID WHITE
		# (measured: 89 % of the sheet area #ffffff while the texture's own pixels
		# are #f4efe2), while draw_style_box/draw_line/draw_circle from the same
		# _draw() rendered correctly. A child node draws the same texture
		# pixel-exact - verified by sampling the frame.

		# (toggle pills live in PillLayer, not here: the page is a child node and
		# children draw ON TOP of their parent's own drawing, so anything drawn in
		# this _draw() would be hidden under the page.)


## The corner button that opens the sheet: a dark rounded tile with a drawn
## sliders glyph (three rules with knobs). Drawn rather than lettered, because a
## gear glyph is not guaranteed to exist in the fallback font on Android.
class EntryButton:
	extends Button

	func _init() -> void:
		custom_minimum_size = SettingsScreen.ENTRY_SIZE
		size = custom_minimum_size
		flat = true
		focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(SettingsScreen.INK, 0.88)
		sb.set_corner_radius_all(10)
		add_theme_stylebox_override("normal", sb)
		var hover := sb.duplicate() as StyleBoxFlat
		hover.bg_color = Color(SettingsScreen.INK, 1.0)
		add_theme_stylebox_override("hover", hover)
		add_theme_stylebox_override("pressed", hover)

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		var ink := SettingsScreen.PAPER
		for i in 3:
			var y: float = h * (0.28 + 0.22 * i)
			draw_line(Vector2(w * 0.22, y), Vector2(w * 0.78, y), Color(ink, 0.85), 2.0)
			# knob: left / right / middle, so it reads as sliders not a menu
			var kx: float = w * (0.34 if i == 0 else (0.66 if i == 1 else 0.5))
			draw_circle(Vector2(kx, y), 3.4, ink)


# ------------------------------------------------------------------- lifecycle

func _ready() -> void:
	layer = 60
	visible = false
	_scrim = ColorRect.new()
	_scrim.color = SCRIM
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow taps meant for the table
	add_child(_scrim)

	_sheet = Sheet.new(self)
	add_child(_sheet)
	_build_paper()
	_build_rows()

	_entry = EntryButton.new()
	_entry.pressed.connect(open)
	add_child(_entry)

	get_viewport().size_changed.connect(_relayout)
	_relayout()


## The toggle pills, drawn in their own layer ABOVE the page texture but below
## the labels: a Control's children always draw over its own _draw(), so the
## pills cannot live in Sheet._draw() once the page is a child node.
class PillLayer:
	extends Control

	var screen: SettingsScreen = null

	func _init(screen_ref: SettingsScreen) -> void:
		screen = screen_ref
		custom_minimum_size = Vector2(SettingsScreen.SHEET_W, SettingsScreen.SHEET_H)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if screen == null or screen._store == null:
			return
		var on: Array[bool] = screen.toggle_states()
		for r in 3:
			var top: float = SettingsScreen.ROW_BASELINES[r] + SettingsScreen.TOGGLE_TOP_DY
			var pill := Rect2(SettingsScreen.TOGGLE_LEFT, top,
				SettingsScreen.TOGGLE_W, SettingsScreen.TOGGLE_H)
			var sb := StyleBoxFlat.new()
			if on[r]:
				sb.bg_color = SettingsScreen.INK
				sb.set_corner_radius_all(int(SettingsScreen.TOGGLE_H / 2.0))
				draw_style_box(sb, pill)
				draw_circle(Vector2(pill.position.x + pill.size.x - 15.0,
					pill.position.y + pill.size.y * 0.5), SettingsScreen.KNOB_R,
					SettingsScreen.PAPER)
			else:
				sb.bg_color = Color(0, 0, 0, 0)
				sb.border_color = SettingsScreen.INK
				sb.set_border_width_all(2)
				sb.set_corner_radius_all(int(SettingsScreen.TOGGLE_H / 2.0))
				draw_style_box(sb, pill)
				draw_circle(Vector2(pill.position.x + 15.0,
					pill.position.y + pill.size.y * 0.5), SettingsScreen.KNOB_R,
					SettingsScreen.INK)


## The page background: a TextureRect rather than a draw call (see the note in
## Sheet._draw). Added first so it sits behind every label and hit area.
func _build_paper() -> void:
	var paper := TextureRect.new()
	paper.texture = load(Sheet.PAPER_TEXTURE) as Texture2D
	paper.position = Vector2.ZERO
	paper.size = Vector2(SHEET_W, SHEET_H)
	paper.stretch_mode = TextureRect.STRETCH_SCALE
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(paper)
	_sheet.move_child(paper, 0)
	_pills = PillLayer.new(self)
	_sheet.add_child(_pills)


## Row labels + value readouts + hit areas: created once, only text and state
## change afterwards (refresh()).
func _build_rows() -> void:
	var titles := ["Sound", "Haptics", "Screen shake", "Match length",
		"%s's pen", "%s's pen"]
	for r in ROW_BASELINES.size():
		var baseline: float = ROW_BASELINES[r]
		var text: String = titles[r]
		if r == Row.PEN_RED:
			text = text % _p1_name
		elif r == Row.PEN_BLUE:
			text = text % _p2_name
		var lbl := _make_label(text, 21, INK)
		lbl.position = Vector2(ROW_LABEL_X, baseline - 17.0)
		_sheet.add_child(lbl)
		_labels.append(lbl)

		var val := _make_label("", 19, VALUE_COLOR)
		val.position = Vector2(VALUE_LEFT_X, baseline - 15.0)
		val.size = Vector2(VALUE_RIGHT_X - VALUE_LEFT_X, 24)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_sheet.add_child(val)
		_values.append(val)

		var hit := Button.new()
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.position = Vector2(RULE_X0, baseline + HIT_TOP_DY)
		hit.size = Vector2(RULE_X1 - RULE_X0, HIT_BOTTOM_DY - HIT_TOP_DY)
		var clear := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "focus"]:
			hit.add_theme_stylebox_override(state, clear)
		hit.pressed.connect(func() -> void: row_pressed.emit(r))
		_sheet.add_child(hit)

	var back := Button.new()
	back.text = "BACK"
	back.focus_mode = Control.FOCUS_NONE
	back.position = BACK_RECT.position
	back.size = BACK_RECT.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = INK
	sb.set_corner_radius_all(5)
	back.add_theme_stylebox_override("normal", sb)
	back.add_theme_stylebox_override("hover", sb)
	back.add_theme_stylebox_override("pressed", sb)
	back.add_theme_color_override("font_color", PAPER)
	back.add_theme_color_override("font_hover_color", PAPER)
	back.add_theme_color_override("font_pressed_color", PAPER)
	back.add_theme_font_size_override("font_size", 22)
	back.pressed.connect(close)
	_sheet.add_child(back)

	var title := _make_label("Settings", 44, INK, true)
	title.position = TITLE_POS
	_sheet.add_child(title)


func _make_label(text: String, px: int, color: Color, bold: bool = false) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", px)
	lbl.add_theme_color_override("font_color", color)
	if bold:
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		fv.variation_embolden = 0.55
		lbl.add_theme_font_override("font", fv)
	return lbl


## Centre the sheet in the CURRENT logical viewport: the project stretches with
## keep_height, so on a wider-than-16:9 phone the logical width exceeds 1280 and
## a hardcoded centre would sit off-centre.
func _relayout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_scrim.size = vp
	_scrim.position = Vector2.ZERO
	_sheet.position = ((vp - Vector2(SHEET_W, SHEET_H)) * 0.5).round()
	_entry.position = (vp - ENTRY_SIZE - Vector2(16, 16)).round()


# ------------------------------------------------------------------------ state

## Snapshot of the three toggles, for the sheet's drawing pass.
func toggle_states() -> Array[bool]:
	if _store == null:
		return [true, true, true]
	return [_store.sound_on, _store.haptics_on, _store.screen_shake_on]


## Push store values into the labels and repaint. Main calls this after applying
## a change; the screen itself never mutates the store.
func refresh() -> void:
	if _store == null:
		return
	_values[Row.MATCH_LENGTH].text = _store.match_length_label()
	_labels[Row.PEN_RED].text = "%s's pen" % _p1_name
	_labels[Row.PEN_BLUE].text = "%s's pen" % _p2_name
	_values[Row.PEN_RED].text = _store.pen_red.capitalize()
	_values[Row.PEN_BLUE].text = _store.pen_blue.capitalize()
	_sheet.queue_redraw()
	if _pills != null:
		_pills.queue_redraw()


func open() -> void:
	visible = true
	_entry.visible = false
	_relayout()
	refresh()


func close() -> void:
	visible = false
	_entry.visible = true
	closed.emit()


func is_open() -> bool:
	return visible


## Wire the screen to a store and the two player display names.
func bind(store: SettingsStore, p1_name: String, p2_name: String) -> void:
	_store = store
	_p1_name = p1_name
	_p2_name = p2_name
	refresh()
