class_name UiFactory
extends RefCounted
## Responsive widget construction. Base sizes are scaled by the root, live.

static func font_scaled(base: int) -> int:
	return base

static func make_panel(parent: Control, panel_name: String) -> Control:
	var panel := Control.new()
	panel.name = panel_name
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(panel)
	panel.visible = false
	return panel

static func center_box(panel: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var fit := func() -> void:
		box.custom_minimum_size.x = clampf(panel.size.x - 64, 240, 820)
	panel.resized.connect(fit)
	fit.call_deferred()
	return box

static func title(text: String, parent: Node, font_size: int) -> Label:
	var result := label(text, parent, font_size)
	result.add_theme_font_override("font", UiTheme.BOLD)
	return result

static func button(text: String, parent: Node, font_size: int, min_size: Vector2 = Vector2(220, 56)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(b)
	return b

static func check(text: String, parent: Node, initial: bool, on_toggle: Callable, font_size: int) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = initial
	c.custom_minimum_size.y = 56
	c.add_theme_font_size_override("font_size", font_size)
	c.toggled.connect(on_toggle)
	parent.add_child(c)
	return c

static func label(text: String, parent: Node, font_size: int = 20) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

static func card(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var body := VBoxContainer.new()
	panel.add_child(body)
	return body

static func focus_first(panel: Control) -> void:
	for child in panel.find_children("*", "BaseButton", true, false):
		if child.is_visible_in_tree() and not child.disabled and child.focus_mode != Control.FOCUS_NONE:
			child.grab_focus()
			return
