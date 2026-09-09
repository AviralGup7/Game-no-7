class_name UiGauges
extends VBoxContainer
## Presentation-only dock for the in-run vital meters (health / stamina / level /
## weapon / objective). Owns BOTH the construction of its rows/bars AND the value
## formatting, so GameHud (or any future dock) only forwards canonical numbers.
## Every meter here is built from the shared UiFactory.gauge primitive, so gauges
## can never drift apart in chrome.

var health_caption: Label
var health_value: Label
var health_bar: ProgressBar
var stamina_caption: Label
var stamina_bar: ProgressBar
var xp_caption: Label
var xp_bar: ProgressBar
var weapon_caption: Label
var objective_caption: Label

var _last_hp := 0.0
var _last_hp_max := 0.0
var _last_stamina := 0.0
var _last_stamina_max := 0.0


func _init() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	# Health — caption + live numbers share one row, bar directly beneath.
	var hrow := _head_row()
	health_caption = _caption(hrow, "HEALTH", 17, Color.WHITE)
	health_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health_value = _value(hrow)
	add_child(hrow)
	health_bar = UiFactory.gauge(self, UiTheme.HEALTH)

	stamina_caption = _caption(self, "STAMINA  —", 15, Color.WHITE)
	stamina_bar = UiFactory.gauge(self, UiTheme.STAMINA)

	xp_caption = _caption(self, "LV 1  /  XP 0", 15, UiTheme.XP)
	xp_bar = UiFactory.gauge(self, UiTheme.XP)

	weapon_caption = _caption(self, "", 15, UiTheme.MUTED)
	objective_caption = _caption(self, "", 15, UiTheme.CYAN)
	objective_caption.visible = false


func _head_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	return row


func _caption(parent: Node, text: String, size: int, color: Color) -> Label:
	var l := UiFactory.title(text, parent, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.modulate = color
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _value(parent: Node) -> Label:
	var l := UiFactory.title("—", parent, 17)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.modulate = Color.WHITE
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func set_health(current: float, maximum: float) -> void:
	_last_hp = current
	_last_hp_max = maximum
	if not is_finite(current) or not is_finite(maximum) or maximum <= 0.0:
		health_bar.value = 0.0
		health_value.text = "—"
	else:
		health_bar.value = clampf(current / maximum, 0, 1)
		health_value.text = "%d / %d" % [ceili(current), ceili(maximum)]
	var low := health_bar.value <= 0.25
	health_caption.text = "LOW HP" if low else "HEALTH"
	health_caption.modulate = UiTheme.DANGER if low else Color.WHITE


func set_stamina(current: float, maximum: float) -> void:
	_last_stamina = current
	_last_stamina_max = maximum
	if not is_finite(current) or not is_finite(maximum) or maximum <= 0.0:
		stamina_bar.value = 0.0
	else:
		stamina_bar.value = clampf(current / maximum, 0, 1)
	stamina_caption.text = "STAMINA  %d / %d" % [ceili(current), ceili(maximum)]


func set_xp(level: int, into: int, required: int) -> void:
	xp_bar.value = clampf(float(into) / maxi(required, 1), 0, 1)
	if level >= ExperienceComponent.MAX_LEVEL:
		xp_bar.value = 1
		xp_caption.text = "LV %d  /  MAX LEVEL" % level
		return
	xp_caption.text = "LV %d  /  XP %d / %d" % [level, into, required]


func set_weapon_text(text: String, tooltip: String = "") -> void:
	weapon_caption.text = text
	if not tooltip.is_empty():
		weapon_caption.tooltip_text = tooltip


func set_objective(text: String) -> void:
	objective_caption.text = text
	objective_caption.visible = not text.is_empty()


## Re-emit the last-known values (e.g. after the dock is shown or text re-scales).
func relabel() -> void:
	if _last_hp_max > 0.0:
		set_health(_last_hp, _last_hp_max)
	if _last_stamina_max > 0.0:
		set_stamina(_last_stamina, _last_stamina_max)
