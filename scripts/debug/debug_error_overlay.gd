class_name DebugErrorOverlay
extends CanvasLayer
## Full-screen freeze overlay for debug mode. Owned and driven by the
## DebugErrorHandler autoload (never added to a scene): the handler freezes the
## tree, then shows the copyable report here. The overlay only presents text and
## emits button intents — clipboard, files, pause, and navigation all stay in
## the handler, which is the single place that can unfreeze the game.
##
## This script references no autoload, so it stays loadable in any harness; it
## is only ever instantiated by the handler at runtime.

signal copy_requested
signal save_requested
signal prev_requested
signal next_requested
signal resume_requested
signal restart_requested
signal menu_requested

const LAYER_ABOVE_ALL := 128

var _root: Control
var _counter_label: Label
var _text: TextEdit
var _feedback: Label
var _copy_button: Button
var _prev_button: Button
var _next_button: Button


func _ready() -> void:
	layer = LAYER_ABOVE_ALL
	# The tree is paused while this is visible; the overlay must keep running
	# and keep receiving input (buttons + Ctrl+C) regardless.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func _build() -> void:
	_root = Control.new()
	_root.name = "DebugFreezeRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Swallow every tap/click while frozen so no game input leaks through.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	_root.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var headline := UiFactory.title("DEBUG MODE — ERROR CAPTURED, GAME FROZEN", box, 24)
	headline.modulate = Color(1.0, 0.45, 0.4)
	var subtitle := UiFactory.label("Nothing crashed. COPY REPORT (or Ctrl+C) copies the whole block.", box, 16)
	subtitle.modulate = UiTheme.MUTED
	_counter_label = UiFactory.label("REPORT 1 OF 1", box, 16)
	_counter_label.modulate = UiTheme.CYAN
	_text = TextEdit.new()
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(0, 200)
	# Read-only but selectable: no virtual keyboard pops up on Android, and the
	# COPY REPORT button is the guaranteed copy path either way.
	_text.editable = false
	_text.context_menu_enabled = true
	_text.add_theme_font_size_override("font_size", 16)
	box.add_child(_text)
	_feedback = UiFactory.label("", box, 16)
	_feedback.modulate = UiTheme.GOLD
	_feedback.custom_minimum_size = Vector2(0, 24)
	var row_one := _row(box)
	_copy_button = _action(row_one, "COPY REPORT")
	_copy_button.pressed.connect(func() -> void: copy_requested.emit())
	var save_button := _action(row_one, "SAVE TO FILE")
	save_button.pressed.connect(func() -> void: save_requested.emit())
	var row_two := _row(box)
	_prev_button = _action(row_two, "< PREV")
	_prev_button.pressed.connect(func() -> void: prev_requested.emit())
	_next_button = _action(row_two, "NEXT >")
	_next_button.pressed.connect(func() -> void: next_requested.emit())
	var row_three := _row(box)
	var resume_button := _action(row_three, "RESUME GAME")
	resume_button.pressed.connect(func() -> void: resume_requested.emit())
	var restart_button := _action(row_three, "RESTART RUN")
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	var menu_button := _action(row_three, "MAIN MENU")
	menu_button.pressed.connect(func() -> void: menu_requested.emit())


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_M)
	parent.add_child(row)
	return row


func _action(parent: Control, caption: String) -> Button:
	var button := UiFactory.button(caption, parent, 20, Vector2(0, UiTheme.TOUCH_MIN))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	return button


## Present a report. `index`/`total` drive the counter + prev/next state.
func show_report(report_text: String, index: int, total: int) -> void:
	_text.text = report_text
	_counter_label.text = "REPORT %d OF %d" % [index + 1, maxi(total, 1)]
	var many := total > 1
	_prev_button.disabled = not many
	_next_button.disabled = not many
	show_feedback("")
	_root.visible = true
	var bar := _text.get_v_scroll_bar()
	if is_instance_valid(bar):
		bar.value = 0
	_copy_button.grab_focus()


func hide_overlay() -> void:
	_root.visible = false
	var viewport := get_viewport()
	if viewport != null:
		viewport.gui_release_focus()


func is_showing() -> bool:
	return _root != null and _root.visible


## One-line result of the last copy/save action ("COPIED ✓ (12.4 KB)" ...).
func show_feedback(message: String) -> void:
	if _feedback != null:
		_feedback.text = message


func _input(event: InputEvent) -> void:
	if not is_showing():
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_C and (key.ctrl_pressed or key.meta_pressed):
			copy_requested.emit()
			var viewport := get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()
