class_name GameHud
extends Control

## Gameplay HUD overlay, extracted from ui_root. Owns the top stat bar (HP, wave,
## combo, currency, score), the HP bar, the pause button, and the confirmation
## toast (tweened, or static-timed when reduced-motion is on). Display-only: it
## never mutates global state; the pause button calls GameRoot.request_pause().

var _hp_label: Label = null
var _hp_bar: ColorRect = null
var _score_label: Label = null
var _wave_label: Label = null
var _combo_label: Label = null
var _currency_label: Label = null
var _toast_label: Label = null
var _toast_tween: Tween = null
var _toast_show_until := 0


func _ready() -> void:
	name = "GameplayHUD"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_bar()
	_build_hp_bar()
	_build_pause_button()
	_build_toast()
	visible = false


func _process(_delta: float) -> void:
	# Reduced-motion toast expiry (no tween when reduced-motion is enabled).
	if _toast_show_until > 0 and Time.get_ticks_msec() > _toast_show_until:
		_toast_show_until = 0
		if _toast_label != null:
			_toast_label.visible = false


func set_health(current: float, maximum: float) -> void:
	_hp_label.text = "%s %d / %d" % [UiText.get(&"hp"), int(round(current)), int(round(maximum))]
	if maximum > 0.0:
		var ratio := clampf(current / maximum, 0.0, 1.0)
		_hp_bar.offset_right = 12 + ratio * 208.0


func set_score(score: int) -> void:
	_score_label.text = "%s %d" % [UiText.get(&"score"), score]


func set_wave(wave_number: int) -> void:
	_wave_label.text = "%s %d" % [UiText.get(&"wave"), wave_number]


func set_combo(combo: int) -> void:
	_combo_label.text = "%s %d" % [UiText.get(&"combo"), combo] if combo > 1 else ""


func set_currency(currency: int) -> void:
	_currency_label.text = "%s %d" % [UiText.get(&"currency"), currency]


## Confirmation toast (upgrade applied, etc.). Respects reduced-motion.
func show_toast(message: String) -> void:
	if _toast_label == null:
		return
	var settings := SaveManager.get_settings()
	_toast_label.text = UiText.get(&"upgrade_selected_fx") + "  " + message
	_toast_label.visible = true
	_toast_label.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	if settings != null and settings.reduced_motion:
		# Reduced motion: show statically for a short, fixed window (no tween).
		_toast_show_until = Time.get_ticks_msec() + 2000
		return
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.5)


func _build_bar() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", UiFactory.font_scaled(18))
	top.add_child(_hp_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	_wave_label = Label.new()
	_wave_label.text = UiText.get(&"wave") + " 1"
	_wave_label.add_theme_font_size_override("font_size", UiFactory.font_scaled(20))
	top.add_child(_wave_label)

	_combo_label = Label.new()
	_combo_label.text = ""
	_combo_label.add_theme_font_size_override("font_size", UiFactory.font_scaled(18))
	top.add_child(_combo_label)

	_currency_label = Label.new()
	_currency_label.text = UiText.get(&"currency") + " 0"
	_currency_label.add_theme_font_size_override("font_size", UiFactory.font_scaled(18))
	top.add_child(_currency_label)

	_score_label = Label.new()
	_score_label.text = UiText.get(&"score") + " 0"
	_score_label.add_theme_font_size_override("font_size", UiFactory.font_scaled(22))
	top.add_child(_score_label)


func _build_hp_bar() -> void:
	_hp_bar = ColorRect.new()
	_hp_bar.color = Color(0.3, 0.85, 0.4)
	_hp_bar.anchor_left = 0.0
	_hp_bar.anchor_top = 0.0
	_hp_bar.anchor_right = 0.0
	_hp_bar.anchor_bottom = 0.0
	_hp_bar.offset_left = 12
	_hp_bar.offset_top = 52
	_hp_bar.offset_bottom = 60
	_hp_bar.offset_right = 220
	add_child(_hp_bar)


func _build_pause_button() -> void:
	var pause_btn := Button.new()
	pause_btn.text = "II"
	pause_btn.anchor_left = 1.0
	pause_btn.anchor_right = 1.0
	pause_btn.anchor_top = 0.0
	pause_btn.offset_left = -80
	pause_btn.offset_right = -12
	pause_btn.offset_top = 10
	pause_btn.offset_bottom = 54
	pause_btn.add_theme_font_size_override("font_size", UiFactory.font_scaled(20))
	pause_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_btn.pressed.connect(func() -> void: GameRoot.request_pause())
	add_child(pause_btn)


func _build_toast() -> void:
	_toast_label = Label.new()
	_toast_label.name = "UpgradeToast"
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_label.offset_top = -120
	_toast_label.offset_bottom = -60
	_toast_label.offset_left = 40
	_toast_label.offset_right = -40
	_toast_label.add_theme_font_size_override("font_size", UiFactory.font_scaled(18))
	_toast_label.modulate.a = 1.0
	_toast_label.visible = false
	add_child(_toast_label)
