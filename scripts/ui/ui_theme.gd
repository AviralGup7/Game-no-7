class_name UiTheme
extends RefCounted
## Shared skin + design tokens. Sci-fi station palette with shared responsive chrome.
## Authored chrome lives in res://data/ui/chrome/ (not the locked Kenney pack).

# --- Core palette: ember / bronze / parchment --------------------------------
const INK := Color("06090f")          # deepest fire-pit black
const SURFACE := Color("0e1726")      # resting leather
const SURFACE_ALT := Color("15233a")  # raised plate
const SURFACE_TOP := Color("1c2f4d")  # light catch
const EDGE := Color("33506f")         # bronze rim
const EDGE_SOFT := Color("203349")    # inner rim
const TEXT := Color("eaf2fa")         # parchment
const MUTED := Color("92a7bd")
const FAINT := Color("5f718a")
const GOLD := Color("f4c76b")         # CTA / rank / currency
const CYAN := Color("55d3e6")         # copper ember (info / energy accent)
const HEALTH := Color("46e0a2")       # blood
const STAMINA := Color("6cc0ff")      # gold stamina
const XP := Color("c789f0")           # ember
const DANGER := Color("ff5a52")

const ART := "res://data/ui/chrome/"

# Loaded at class init (after import), not const-preloaded: Godot 4.4.1 has no
# compile-time loader for `.ttf`, so a typed `preload` fails the whole UI graph.
static var REGULAR: Font = load("res://assets/fonts/rajdhani/Rajdhani-Regular.ttf") as Font
static var BOLD: Font = load("res://assets/fonts/rajdhani/Rajdhani-Bold.ttf") as Font

const SPACE_S := 8
const SPACE_M := 16
const SPACE_L := 24
const RADIUS := 12
const RADIUS_SM := 8
const TOUCH_MIN := 88


static func art(file: String) -> Texture2D:
	var path := ART + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## 9-slice a chrome PNG. Falls back to a flat plate when the file is missing.
static func skin(file: String, tex_margin: int = 64, content: int = 18,
		tint: Color = Color.WHITE) -> StyleBox:
	var tex := art(file)
	if tex == null:
		return plate()
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.set_texture_margin_all(tex_margin)
	sb.modulate_color = tint
	sb.content_margin_left = content
	sb.content_margin_right = content
	sb.content_margin_top = content
	sb.content_margin_bottom = content
	return sb


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
		style.shadow_color = Color(0, 0, 0, 0.55)
		style.shadow_size = 10
		style.shadow_offset = Vector2(0, 5)
	return style


static func row_card() -> StyleBox:
	var framed := skin("panel.png", 72, SPACE_M)
	if framed is StyleBoxTexture:
		return framed
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


static func glass(bg: Color = Color(0.07, 0.03, 0.02, 0.78), radius: int = RADIUS) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(EDGE.r, EDGE.g, EDGE.b, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = SPACE_M
	style.content_margin_right = SPACE_M
	style.content_margin_top = SPACE_M
	style.content_margin_bottom = SPACE_M
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	return style


static func bar(color: Color, radius: int = RADIUS_SM, round_end := true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius if round_end else 0)
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	style.content_margin_left = 0
	style.content_margin_right = 0
	return style


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

	for type in ["Button", "OptionButton", "CheckButton", "MenuButton", "LinkButton"]:
		theme.set_stylebox("normal", type, skin("btn_dark.png", 48, 18))
		theme.set_stylebox("hover", type, skin("btn_dark.png", 48, 18, Color(1.18, 1.08, 0.88)))
		theme.set_stylebox("pressed", type, skin("btn_gold.png", 56, 18, Color(0.95, 0.82, 0.55)))
		theme.set_stylebox("disabled", type, control(disabled_bg, Color(edge.r, edge.g, edge.b, 0.45), 1, Color.TRANSPARENT))
		theme.set_stylebox("focus", type, control(Color.TRANSPARENT, GOLD, 2, Color.TRANSPARENT))
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
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	theme.set_color("font_shadow_color", "RichTextLabel", Color(0, 0, 0, 0.55))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("caret_color", "LineEdit", GOLD)
	theme.set_color("font_color", "PopupMenu", TEXT)

	theme.set_stylebox("panel", "PanelContainer", skin("panel.png", 72, SPACE_M))
	theme.set_stylebox("panel", "PopupMenu", skin("btn_dark.png", 48, 12))

	var field := control(Color(INK.r, INK.g, INK.b, 0.8), edge)
	field.content_margin_left = 16
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", control(Color(INK), GOLD, 2, Color(GOLD.r, GOLD.g, GOLD.b, 0.25)))

	var trough := StyleBoxFlat.new()
	trough.bg_color = Color(0.05, 0.02, 0.01, 0.92)
	trough.border_color = EDGE_SOFT
	trough.set_border_width_all(1)
	trough.set_corner_radius_all(7)
	theme.set_stylebox("background", "ProgressBar", trough)
	theme.set_stylebox("fill", "ProgressBar", bar(HEALTH))
	theme.set_stylebox("grabber_area", "HSlider", control(Color(SURFACE_TOP), GOLD, 1))
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
	var path := "res://assets/scifi/ui/icons/%s.png" % name
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func decorate(button: Button, icon_name: String) -> void:
	button.icon = icon(icon_name)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 32)
	if button.icon != null:
		button.tooltip_text = button.tooltip_text if not button.tooltip_text.is_empty() else button.text
	button.add_theme_constant_override("h_separation", 12)


static func apply_text_scale(node: Node, scale: float) -> void:
	if node is Control:
		var as_control := node as Control
		if as_control.has_theme_font_size_override("font_size"):
			if not as_control.has_meta("ui_base_font"):
				as_control.set_meta("ui_base_font", as_control.get_theme_font_size("font_size"))
			as_control.add_theme_font_size_override("font_size", int(float(as_control.get_meta("ui_base_font")) * scale))
	for child in node.get_children():
		apply_text_scale(child, scale)
