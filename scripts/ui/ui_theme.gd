class_name UiTheme
extends RefCounted
## Shared, static skin + design tokens for the whole interface. No gameplay
## dependencies. Every colour, spacing multiple, radius and the accessibility
## floor live here so screens stay visually cohesive no matter who builds them.

# --- Core palette: polished dark-arena refinement ----------------------------
const INK := Color("06090f")          # deepest void behind everything
const SURFACE := Color("0e1726")      # resting panel
const SURFACE_ALT := Color("15233a")  # raised / hover panel
const SURFACE_TOP := Color("1c2f4d")  # light catch for top-highlight gradients
const EDGE := Color("33506f")         # neutral panel border
const EDGE_SOFT := Color("203349")    # faint inner border
const TEXT := Color("eaf2fa")
const MUTED := Color("92a7bd")
const FAINT := Color("5f718a")
const GOLD := Color("f4c76b")         # currency / CTA / rank accents
const CYAN := Color("55d3e6")         # energy / info accents
const HEALTH := Color("46e0a2")       # positive green meters
const STAMINA := Color("6cc0ff")      # cool stamina blue
const XP := Color("c789f0")           # level-up violet
const DANGER := Color("ff5a52")

const REGULAR := preload("res://assets/fonts/rajdhani/Rajdhani-Regular.ttf")
const BOLD := preload("res://assets/fonts/rajdhani/Rajdhani-Bold.ttf")

## Spacing scale — every panel/margin/separation in the UI is a multiple of it,
## so gaps stay consistent between screens.
const SPACE_S := 8
const SPACE_M := 16
const SPACE_L := 24
const RADIUS := 12
const RADIUS_SM := 8
## Android accessibility floor for an interactive control.
const TOUCH_MIN := 88

## Build a flat, rounded box. Kept as the fast primitive; richer components use
## plate()/panel()/control() below.
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


## A premium raised panel: base surface + a crisp rim + a gentle drop shadow.
## The default chrome for cards, dialogs and plates.
static func plate(border: Color = EDGE, margin := SPACE_M, radius: int = RADIUS,
		shadow: bool = true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = SURFACE
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	if shadow:
		style.shadow_color = Color(0, 0, 0, 0.4)
		style.shadow_size = 8
		style.shadow_offset = Vector2(0, 4)
	return style


## Compact "raised row" card used for list rows and stat groups (thinner chrome).
static func row_card() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(SURFACE_ALT.r, SURFACE_ALT.g, SURFACE_ALT.b, 0.9)
	style.border_color = EDGE_SOFT
	style.set_border_width_all(1)
	style.set_corner_radius_all(RADIUS_SM)
	style.content_margin_left = SPACE_M
	style.content_margin_right = SPACE_M
	style.content_margin_top = SPACE_S
	style.content_margin_bottom = SPACE_S
	return style


## A shallow translucent plate for panels floating over gameplay / artwork.
static func glass(bg: Color = Color(0.06, 0.09, 0.15, 0.72), radius: int = RADIUS) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(EDGE.r, EDGE.g, EDGE.b, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = SPACE_M
	style.content_margin_right = SPACE_M
	style.content_margin_top = SPACE_M
	style.content_margin_bottom = SPACE_M
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	return style


## A neat segmented "meter" fill. `color` is the fill; passing Color.TRANSPARENT
## lets callers draw their own textured gloss on top.
static func bar(color: Color, radius: int = RADIUS_SM, round_end := true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius if round_end else 0)
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	style.content_margin_left = 0
	style.content_margin_right = 0
	return style


## Interactive button styling. `emphasis` drives accent glow:
## "primary" (gold glow) / "ghost" (neutral) / "danger".
static func control(bg: Color, border: Color, border_w: int = 1,
		glow: Color = Color.TRANSPARENT, radius: int = RADIUS_SM) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_w)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	if glow.a > 0.0:
		style.shadow_color = glow
		style.shadow_size = 10
		style.shadow_offset = Vector2(0, 0)
	return style


static func create(settings: SettingsData) -> Theme:
	var theme := Theme.new()
	theme.default_font = REGULAR
	theme.default_font_size = int(20 * settings.text_scale)
	var edge := Color.WHITE if settings.high_contrast else EDGE
	var disabled_bg := Color(INK.r, INK.g, INK.b, 0.85)

	# --- Buttons -------------------------------------------------------------
	# Resting ghost, hover reads as live, press is a loud gold flash. On touch
	# there is no hover, so the press flash is the only tap confirmation.
	for type in ["Button", "OptionButton", "CheckButton", "MenuButton", "LinkButton"]:
		var rest := control(Color(SURFACE_ALT.r, SURFACE_ALT.g, SURFACE_ALT.b, 0.95), edge)
		theme.set_stylebox("normal", type, rest)
		var hov := control(Color(SURFACE_TOP.r, SURFACE_TOP.g, SURFACE_TOP.b, 0.98), CYAN, 1,
			Color(CYAN.r, CYAN.g, CYAN.b, 0.28))
		theme.set_stylebox("hover", type, hov)
		var pressed := control(Color("2c4a68"), GOLD, 2, Color(GOLD.r, GOLD.g, GOLD.b, 0.4))
		theme.set_stylebox("pressed", type, pressed)
		theme.set_stylebox("disabled", type, control(disabled_bg, Color(edge.r, edge.g, edge.b, 0.45), 1, Color.TRANSPARENT))
		theme.set_stylebox("focus", type, control(Color.TRANSPARENT, GOLD, 2, Color.TRANSPARENT))
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_disabled_color", type, MUTED)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_pressed_color", type, GOLD)
		theme.set_color("font_focus_color", type, Color.WHITE)
		theme.set_font("font", type, BOLD)
		theme.set_constant("outline_size", type, 0)

	# Labels inherit a light-on-dark fill; big display text can sit on any scene.
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "RichTextLabel", TEXT)
	theme.set_font("font", "Label", REGULAR)
	theme.set_font("font", "RichTextLabel", REGULAR)
	theme.set_font("font", "PopupMenu", REGULAR)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	theme.set_color("font_shadow_color", "RichTextLabel", Color(0, 0, 0, 0.35))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("caret_color", "LineEdit", CYAN)
	theme.set_color("font_color", "PopupMenu", TEXT)

	# Panels / cards: raised chrome for depth on menu screens.
	var panel_flat := plate(edge)
	theme.set_stylebox("panel", "PanelContainer", panel_flat)
	theme.set_stylebox("panel", "PopupMenu", control(SURFACE_ALT, edge))

	# Text field / dropdown editor.
	var field := control(Color(INK.r, INK.g, INK.b, 0.8), edge)
	field.content_margin_left = 16
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", control(Color(INK), CYAN, 2, Color(CYAN.r, CYAN.g, CYAN.b, 0.2)))

	# Meters: an inset trough + bright fill with rounded lead edges.
	var trough := StyleBoxFlat.new()
	trough.bg_color = Color(0.02, 0.04, 0.07, 0.9)
	trough.border_color = EDGE_SOFT
	trough.set_border_width_all(1)
	trough.set_corner_radius_all(7)
	theme.set_stylebox("background", "ProgressBar", trough)
	theme.set_stylebox("fill", "ProgressBar", bar(HEALTH))
	theme.set_stylebox("grabber_area", "HSlider", control(Color(SURFACE_TOP), CYAN, 1))
	theme.set_stylebox("grabber_area_highlight", "HSlider", control(Color(SURFACE_TOP), GOLD, 1))
	theme.set_stylebox("slider", "HSlider", trough)
	theme.set_stylebox("grabber", "HSlider", control(Color.WHITE, GOLD, 2))

	theme.set_constant("separation", "VBoxContainer", SPACE_M)
	theme.set_constant("separation", "HBoxContainer", SPACE_M)
	theme.set_constant("h_separation", "GridContainer", SPACE_M)
	theme.set_constant("v_separation", "GridContainer", SPACE_M)
	theme.set_constant("outline_size", "Label", 0)
	return theme


static func icon(name: String) -> Texture2D:
	var path := "res://assets/ui/icons/%s.png" % name
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Apply an icon to a button and give it room to breathe beside the caption.
static func decorate(button: Button, icon_name: String) -> void:
	button.icon = icon(icon_name)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 24)
	if button.icon != null:
		button.tooltip_text = button.tooltip_text if not button.tooltip_text.is_empty() else button.text
	button.add_theme_constant_override("h_separation", 12)


static func apply_text_scale(node: Node, scale: float) -> void:
	if node is Control:
		var control_node := node as Control
		if control_node.has_theme_font_size_override("font_size"):
			if not control_node.has_meta("ui_base_font"):
				control_node.set_meta("ui_base_font", control_node.get_theme_font_size("font_size"))
			control_node.add_theme_font_size_override("font_size", int(float(control_node.get_meta("ui_base_font")) * scale))
	for child in node.get_children():
		apply_text_scale(child, scale)
