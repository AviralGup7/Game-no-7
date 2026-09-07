class_name UiFactory
extends RefCounted

## Shared UI widget builders, extracted from ui_root. All-static; every builder
## takes its parent and returns the created control. Font sizes scale with the
## text_scale setting (read live from SaveManager at build time).


static func font_scaled(base: int) -> int:
	var settings := SaveManager.get_settings()
	return int(round(base * settings.text_scale))


static func make_panel(parent: Control, panel_name: String) -> Control:
	var panel := Control.new()
	panel.name = panel_name
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	panel.visible = false
	return panel


static func center_box(panel: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	return box


static func title(text: String, parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


static func button(text: String, parent: Node, font_size: int, min_size: Vector2 = Vector2(260, 54)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(b)
	return b


static func check(text: String, parent: Node, initial: bool, on_toggle: Callable, font_size: int) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = initial
	c.add_theme_font_size_override("font_size", font_size)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.toggled.connect(on_toggle)
	parent.add_child(c)
	return c


static func label(text: String, parent: Node, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l
