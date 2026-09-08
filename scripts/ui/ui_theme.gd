class_name UiTheme
extends RefCounted
## Shared, static skin. No animation or gameplay dependencies.

const INK := Color("0b111b")
const SURFACE := Color("152333")
const EDGE := Color("365269")
const TEXT := Color("edf4f7")
const MUTED := Color("b7c9d5")
const GOLD := Color("ffd37c")
const CYAN := Color("79dfeb")
const REGULAR := preload("res://assets/fonts/rajdhani/Rajdhani-Regular.ttf")
const BOLD := preload("res://assets/fonts/rajdhani/Rajdhani-Bold.ttf")

## Spacing scale — every panel/margin/separation in the UI is a multiple of it,
## so gaps stay consistent between screens.
const SPACE_S := 8
const SPACE_M := 16
const SPACE_L := 24
const RADIUS := 10
## Android accessibility floor for an interactive control.
const TOUCH_MIN := 88

static func box(color: Color, border: Color = EDGE, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(RADIUS)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func create(settings: SettingsData) -> Theme:
	var theme := Theme.new()
	theme.default_font = REGULAR
	theme.default_font_size = int(20 * settings.text_scale)
	var surface := Color.BLACK if settings.high_contrast else SURFACE
	var edge := Color.WHITE if settings.high_contrast else EDGE
	var disabled_bg := Color(INK.r, INK.g, INK.b, 0.85)
	for type in ["Button", "OptionButton", "CheckButton", "MenuButton", "LinkButton"]:
		theme.set_stylebox("normal", type, box(surface, edge))
		theme.set_stylebox("hover", type, box(Color("28465a"), CYAN))
		# Pressed state is deliberately loud: on touch there is no hover, so the
		# press flash is the only affordance confirming the tap registered.
		theme.set_stylebox("pressed", type, box(Color("3f6b86"), GOLD, 3))
		theme.set_stylebox("disabled", type, box(disabled_bg, Color(edge.r, edge.g, edge.b, 0.45)))
		theme.set_stylebox("focus", type, box(Color.TRANSPARENT, GOLD, 3))
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_disabled_color", type, MUTED)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_pressed_color", type, GOLD)
		theme.set_color("font_focus_color", type, Color.WHITE)
		theme.set_font("font", type, BOLD)
		theme.set_constant("outline_size", type, 0)
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "RichTextLabel", TEXT)
	theme.set_font("font", "Label", REGULAR)
	theme.set_font("font", "RichTextLabel", REGULAR)
	theme.set_font("font", "PopupMenu", REGULAR)
	var panel_box := box(surface, edge)
	panel_box.content_margin_left = SPACE_M
	panel_box.content_margin_right = SPACE_M
	panel_box.content_margin_top = SPACE_M
	panel_box.content_margin_bottom = SPACE_M
	theme.set_stylebox("panel", "PanelContainer", panel_box)
	theme.set_stylebox("panel", "PopupMenu", box(surface, edge))
	theme.set_stylebox("background", "ProgressBar", box(INK, edge))
	theme.set_stylebox("fill", "ProgressBar", box(CYAN, CYAN, 0))
	theme.set_constant("separation", "VBoxContainer", SPACE_M)
	theme.set_constant("separation", "HBoxContainer", SPACE_M)
	theme.set_constant("h_separation", "GridContainer", SPACE_M)
	theme.set_constant("v_separation", "GridContainer", SPACE_M)
	return theme

static func icon(name: String) -> Texture2D:
	var path := "res://assets/ui/icons/%s.png" % name
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

static func decorate(button: Button, icon_name: String) -> void:
	button.icon = icon(icon_name)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 24)
	if button.icon != null:
		button.tooltip_text = button.tooltip_text if not button.tooltip_text.is_empty() else button.text
	button.add_theme_constant_override("h_separation", 12)

static func apply_text_scale(node: Node, scale: float) -> void:
	if node is Control:
		var control := node as Control
		if control.has_theme_font_size_override("font_size"):
			if not control.has_meta("ui_base_font"):
				control.set_meta("ui_base_font", control.get_theme_font_size("font_size"))
			control.add_theme_font_size_override("font_size", int(float(control.get_meta("ui_base_font")) * scale))
	for child in node.get_children():
		apply_text_scale(child, scale)
