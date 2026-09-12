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


## Build a complete full-screen overlay root: a full-rect, click-blocking Control
## that owns a scrollable centred column ready for screen content. Optional
## translucent scrim dims whatever sits behind it (menus over gameplay). Returns
## `{panel, box, scrim}` so callers can style the backdrop or drop into the box.
## This is the single scaffold every floating screen should mount through.
static func overlay(parent: Control, dim: float = 0.0) -> Dictionary:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(panel)
	var scrim: ColorRect = null
	if dim > 0.0:
		scrim = ColorRect.new()
		scrim.color = Color(0.05, 0.02, 0.01, clampf(dim, 0.0, 1.0))
		scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
		scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(scrim)
	var box := center_box(panel)
	return {"panel": panel, "box": box, "scrim": scrim}

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
	result.add_theme_font_override("font", UiTheme.bold_font)
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


## A high-emphasis gold action button (the single strongest CTA on a screen).
## Dark text on gold keeps the contrast legible and reads instantly as "do this".
static func primary(text: String, parent: Node, font_size: int, min_size: Vector2 = Vector2(260, 104)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(maxf(min_size.x, 220), maxf(min_size.y, UiTheme.TOUCH_MIN))
	b.add_theme_font_size_override("font_size", font_size)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var ink := Color(0.12, 0.06, 0.02)
	b.add_theme_stylebox_override("normal", UiTheme.skin("btn_gold.png", 56, 26))
	b.add_theme_stylebox_override("hover", UiTheme.skin("btn_gold.png", 56, 26, Color(1.12, 1.05, 0.85)))
	b.add_theme_stylebox_override("pressed", UiTheme.skin("btn_gold.png", 56, 26, Color(0.78, 0.62, 0.32)))
	b.add_theme_color_override("font_color", ink)
	b.add_theme_color_override("font_hover_color", ink)
	b.add_theme_color_override("font_pressed_color", Color(0.25, 0.16, 0.03))
	parent.add_child(b)
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
	AudioManager.play_sfx(cue, -8.0)


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


## A labelled catalogue picker: a raised card with a section title, a touch-sized
## OptionButton and a description line. Returns a handle so callers can populate
## the dropdown and bind description text. Used by every "choose one of N"
## selection screen so they all look and behave identically.
static func select_card(parent: Node, title_text: String) -> Dictionary:
	var body := card(parent)
	UiFactory.title(title_text, body, 22)
	var option := OptionButton.new()
	option.custom_minimum_size.y = UiTheme.TOUCH_MIN
	option.mouse_filter = Control.MOUSE_FILTER_STOP
	body.add_child(option)
	var desc := UiFactory.label("", body, 20)
	return {"body": body, "option": option, "desc": desc}


static func focus_first(panel: Control) -> void:
	for child in panel.find_children("*", "BaseButton", true, false):
		if child.is_visible_in_tree() and not child.disabled and child.focus_mode != Control.FOCUS_NONE:
			child.grab_focus()
			return


# ---------------------------------------------------------------------------
# Reusable chrome primitives — the shared visual vocabulary every screen is
# composed from, so screens stay consistent without re-defining their own look.
# ---------------------------------------------------------------------------

## A short uppercase accent "eyebrow" line that labels a screen or section.
static func kicker(text: String, parent: Node, color: Color = UiTheme.CYAN,
		font_size: int = 18) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_font_override("font", UiTheme.bold_font)
	l.modulate = color
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## A crisp centered accent divider (gold by default) used to anchor hero
## typography above body content.
static func hairline(parent: Node, color: Color = UiTheme.GOLD,
		thickness: int = 2, width: float = 180.0) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = color
	rule.custom_minimum_size = Vector2(width, thickness)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)
	return rule


## Standard full-screen hero: optional eyebrow, a title (returned so callers can
## rename / re-tint it) and an optional muted subtitle. Keeps the typography of
## every floating menu (pause, status, settings, armory, summary) identical.
static func screen_header(parent: Node, eyebrow: String = "", title_text: String = "",
		title_size: int = 34, subtitle: String = "") -> Dictionary:
	var out: Dictionary = {}
	if not eyebrow.is_empty():
		out["kicker"] = kicker(eyebrow, parent)
	if not title_text.is_empty():
		var t := UiFactory.title(title_text, parent, title_size)
		out["title"] = t
	if not subtitle.is_empty():
		var s := UiFactory.label(subtitle, parent, 20)
		s.modulate = UiTheme.MUTED
		out["subtitle"] = s
	return out


## A ready-to-wire status gauge (ProgressBar 0..1) in the design-system metre
## style. Callers bind its value; tint per meter (health / stamina / xp / …).
static func gauge(parent: Node, color: Color, height: float = 16.0) -> ProgressBar:
	var meter := ProgressBar.new()
	meter.custom_minimum_size.y = height
	meter.max_value = 1
	meter.show_percentage = false
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(UiTheme.RADIUS_SM)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	fill.content_margin_left = 0
	fill.content_margin_right = 0
	meter.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.02, 0.01, 0.92)
	bg.border_color = UiTheme.EDGE_SOFT
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(UiTheme.RADIUS_SM)
	bg.content_margin_top = 0
	bg.content_margin_bottom = 0
	meter.add_theme_stylebox_override("background", bg)
	parent.add_child(meter)
	return meter


## A labelled metric block (a header line above a gauge) that panels reuse for
## health / stamina / level bars without re-arranging rows by hand.
static func metric(parent: Node, caption: String, color: Color,
		initial_value := 0.0) -> Dictionary:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 3)
	parent.add_child(box)
	var cap := Label.new()
	cap.text = caption
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cap.autowrap_mode = TextServer.AUTOWRAP_OFF
	cap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cap.add_theme_font_size_override("font_size", 15)
	cap.modulate = Color.WHITE
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cap)
	var bar := gauge(box, color)
	bar.value = initial_value
	return {"container": box, "caption": cap, "bar": bar}

