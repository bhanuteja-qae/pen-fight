class_name TurnGate
extends CanvasLayer
## Hard turn-transition gate (docs §3.5 #1): a full-screen tap-to-continue
## overlay shown between turns and on a decided round, so a hot-seat player
## can never flick on the wrong turn.
##
## Self-contained presentation only — NO references to TurnState / PenBody /
## AimInput. Main drives it (show_prompt / hide) and reacts to `tapped`.
## Built from plain Control nodes (ColorRect + Label) that render identically
## under the headless / Xvfb acceptance runs: the engine's default Label font
## is a TextServer resource that exists headless, so no asset is needed.
##
## CanvasLayer placement: layer 1 is the base canvas layer, so the dim rect
## sorts by z_index against world content — above the table/pens (z ~0) and
## below the debug overlay (z 100), per the contract.

signal tapped

## Design font size for the prompt. Long prompts (the match-over line, which
## carries the durable series) measured 1276 px wide at 44 px on a 1280-wide
## viewport — clipped edge-to-edge. Rather than shrink the normal round prompts,
## show_prompt() keeps this size when it fits and steps down only when it does
## not, so short prompts are unchanged and long ones stay readable.
const FONT_SIZE: int = 44
const FONT_SIZE_MIN: int = 18
const FONT_SIZE_STEP: int = 2
## Never let glyphs touch the screen edge (also the autowrap width budget).
const SIDE_MARGIN: float = 32.0

var _dim: ColorRect = null
var _label: Label = null


func _ready() -> void:
	layer = 1
	# Full-screen dim. mouse_filter IGNORE so the click passes through the GUI
	# system to this node's _unhandled_input instead of being swallowed.
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.z_index = 50
	add_child(_dim)
	# Centered prompt text on top of the dim.
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Inset both edges so nothing is ever drawn flush against the screen edge.
	_label.offset_left = SIDE_MARGIN
	_label.offset_right = -SIDE_MARGIN
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Word-aware wrap is the safety net for any prompt longer than the inset
	# width; explicit "\n" in the copy is how multi-part prompts are separated.
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.z_index = 51
	add_child(_label)
	visible = false


## Show the gate with the given prompt text (e.g. "Red's turn — tap to continue").
func show_prompt(text: String) -> void:
	_label.text = text
	_fit_font_to_width()
	visible = true


## Largest size at or below FONT_SIZE at which EVERY line of the prompt fits the
## inset width. Without this, the match-over prompt ("… tap for a rematch
## (series: …)") overflowed a 1280-wide viewport and was cut at both ends, and
## it degrades further on narrower logical viewports — the project stretches
## with window/stretch/aspect=keep_height, so a tall phone's logical width is
## far below 1280.
func _fit_font_to_width() -> void:
	if _label == null:
		return
	var font: Font = _label.get_theme_font("font")
	if font == null:
		return
	var limit: float = maxf(64.0, get_viewport().get_visible_rect().size.x - 2.0 * SIDE_MARGIN)
	var size: int = FONT_SIZE
	while size > FONT_SIZE_MIN:
		if _widest_line(font, size) <= limit:
			break
		size -= FONT_SIZE_STEP
	_label.add_theme_font_size_override("font_size", size)


## Rendered width of the prompt's widest explicit line at the given size.
func _widest_line(font: Font, size: int) -> float:
	var widest := 0.0
	for line in _label.text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	return widest


## The size the prompt is currently rendered at (QA/tests read this).
func prompt_font_size() -> int:
	return _label.get_theme_font_size("font_size") if _label != null else 0


## Hide the gate. NOTE: named dismiss() not hide() — CanvasLayer already has a
## native hide() and GDScript treats the override as a parse error
## ("Warning treated as error"). Same visible-toggle semantics.
func dismiss() -> void:
	visible = false


## Any press (mouse or touch) dismisses the gate and reports it. The press is
## marked handled so it can't also start a flick drag while the gate is up.
## Touch-first (Phase 1d): the roll is played on a phone, so a finger tap must
## dismiss it just like a mouse click. Emulation guards keep one physical
## gesture from firing twice (Android synthesizes mouse events from touch by
## default; the desktop does the reverse).
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		if Input.is_emulating_mouse_from_touch():
			return  # this is the synthesized copy of a real finger tap
		var mb: InputEventMouseButton = event
		if mb.pressed:
			get_viewport().set_input_as_handled()
			dismiss()
			tapped.emit()
	elif event is InputEventScreenTouch:
		if Input.is_emulating_touch_from_mouse():
			return  # this is the synthesized copy of a real mouse click
		var st: InputEventScreenTouch = event
		if st.pressed:
			get_viewport().set_input_as_handled()
			dismiss()
			tapped.emit()
