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
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 44)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.z_index = 51
	add_child(_label)
	visible = false


## Show the gate with the given prompt text (e.g. "Red's turn — tap to continue").
func show_prompt(text: String) -> void:
	_label.text = text
	visible = true


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
