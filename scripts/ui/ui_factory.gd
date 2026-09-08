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
		margin.add_theme_constant_override("margin_" + side, UiTheme.SPACE_L)
	scroll.add_child(margin)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", UiTheme.SPACE_M)
	center.add_child(box)
	var fit := func() -> void:
		# Narrow (portrait) screens use the full width minus gutters; wide screens
		# cap the measure so lines stay readable instead of stretching.
		box.custom_minimum_size.x = clampf(
			panel.size.x - UiTheme.SPACE_L * 2, 240, maxf(panel.size.x * 0.62, 560)
		)
	panel.resized.connect(fit)
	fit.call_deferred()
	return box

static func title(text: String, parent: Node, font_size: int) -> Label:
	var result := label(text, parent, font_size)
	result.add_theme_font_override("font", UiTheme.BOLD)
	return result

static func button(text: String, parent: Node, font_size: int, min_size: Vector2 = Vector2(220, UiTheme.TOUCH_MIN)) -> Button:
	var b := Button.new()
	b.text = text
	# Never emit a control below the Android touch-target floor.
	b.custom_minimum_size = Vector2(min_size.x, maxf(min_size.y, UiTheme.TOUCH_MIN))
	b.add_theme_font_size_override("font_size", font_size)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(b)
	# Every factory button acknowledges its press acoustically (previously the
	# ui_confirm/ui_back cues existed but had zero call sites, so the whole UI
	# was silent). Resolve through the tree so headless/test contexts stay safe.
	b.pressed.connect(func() -> void: UiFactory.play_press(b.text))
	return b


## Shared press tick for factory buttons AND hand-built buttons (upgrade cards,
## armory rows, dialogs). Back/dismiss-style captions get `ui_back`, everything
## else gets `ui_confirm`. Failure-safe: silence when audio is unavailable.
static func play_press(caption: String) -> void:
	var cue := &"ui_back" if _is_back_caption(caption) else &"ui_confirm"
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return
	var audio := loop.root.get_node_or_null("AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.call("play_sfx", cue, -8.0)


static func _is_back_caption(caption: String) -> bool:
	var upper := caption.to_upper()
	for token in ["BACK", "RETURN", "QUIT", "CANCEL", "LEAVE", "SKIP", "GOT IT", "MAIN MENU", "CLOSE"]:
		if upper.contains(token):
			return true
	return false

static func check(text: String, parent: Node, initial: bool, on_toggle: Callable, font_size: int) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = initial
	c.custom_minimum_size.y = UiTheme.TOUCH_MIN
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
	body.add_theme_constant_override("separation", UiTheme.SPACE_S)
	panel.add_child(body)
	return body

static func focus_first(panel: Control) -> void:
	for child in panel.find_children("*", "BaseButton", true, false):
		if child.is_visible_in_tree() and not child.disabled and child.focus_mode != Control.FOCUS_NONE:
			child.grab_focus()
			return

## Hardened: validate factory product.
func _validated_product(p: Node) -> bool:
	return p != null and is_instance_valid(p)

