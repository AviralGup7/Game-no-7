class_name GameHud
extends Control
## Display-only HUD. Owns the top status plate and the toast; the bottom-left
## vital meters live in a dedicated UiGauges dock (see ui_gauges.gd). Events drive
## updates; run_started seeds snapshots because world construction may emit its
## first values before binding. All geometry is applied by UiRoot from the shared
## UiLayout solution; this panel only owns its *look* and text content.

## The vital dock ships as a reusable packed scene so it can be edited / themed in
## the Godot editor; UiFactory.gauge remains the only place metre chrome is built.
const GAUGES_SCENE := preload("res://scenes/ui/ui_gauges.tscn")

var _score_label: Label
var _score_value: Label
var _wave_label: Label
var _combo_label: Label
var _currency_label: Label
var _toast_label: Label
var _toast_show_until := 0
var _experience: ExperienceComponent
var _gauges: UiGauges
var _top: HBoxContainer
var _top_scrim: PanelContainer
var _gauges_scrim: PanelContainer
var _pause_button: Button
var _compact := false
var _toast_fits := true
var _weapon_refresh := 0.0
# Dirty-flag caches so repeated events with unchanged values never force a label
# write / tooltip rebuild (the HUD is updated at event rate and on a per-frame
# weapon poll, so this keeps low-end GPUs free of redundant string work).
var _score_cached := -1
var _currency_cached := -1
var _wave_cached := -1
var _combo_cached := -1
var _weapon_caption_cache := ""
var _weapon_tip_cache := ""


func _ready() -> void:
	name = "GameplayHUD"
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE

	# --- Top status plate ----------------------------------------------------
	# Sleek translucent command bar that hugs the top safe edge. A glass plate +
	# crisp rim keeps meters readable over bright arena floors.
	_top_scrim = PanelContainer.new()
	_top_scrim.mouse_filter = MOUSE_FILTER_IGNORE
	_top_scrim.add_theme_stylebox_override("panel", _scrim())
	_top_scrim.clip_contents = true
	add_child(_top_scrim)
	_top = HBoxContainer.new()
	_top.mouse_filter = MOUSE_FILTER_IGNORE
	_top.add_theme_constant_override("separation", 12)
	_top.alignment = BoxContainer.ALIGNMENT_CENTER
	_top_scrim.add_child(_top)

	_wave_label = UiFactory.title("WAVE 1", _top, 26)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_wave_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wave_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_wave_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_wave_label.add_theme_color_override("font_color", UiTheme.GOLD)
	_wave_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_wave_label.add_theme_constant_override("outline_size", 4)
	_combo_label = UiFactory.title("", _top, 22)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_combo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_combo_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_combo_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_combo_label.modulate = UiTheme.GOLD
	_combo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_combo_label.add_theme_constant_override("outline_size", 4)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	_top.add_child(spacer)

	_currency_label = _value_chip(_top, UiTheme.CYAN, "COINS 0")
	_score_label = UiFactory.label("SCORE", _top, 16)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_score_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_score_label.modulate = UiTheme.MUTED
	_score_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_score_label.add_theme_constant_override("outline_size", 3)
	_score_value = UiFactory.title("0", _top, 28)
	_score_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_value.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_score_value.autowrap_mode = TextServer.AUTOWRAP_OFF
	_score_value.modulate = Color.WHITE
	_score_value.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_score_value.add_theme_constant_override("outline_size", 5)
	var score_stack := VBoxContainer.new()
	score_stack.add_theme_constant_override("separation", 0)
	score_stack.add_child(_score_label)
	score_stack.add_child(_score_value)
	_top.add_child(score_stack)

	_pause_button = UiFactory.button(
		"PAUSE", _top, 20, Vector2(UiLayout.MIN_TOUCH * 1.5, UiLayout.MIN_TOUCH)
	)
	_pause_button.size_flags_vertical = SIZE_SHRINK_CENTER
	_pause_button.tooltip_text = "Pause the run"
	UiTheme.decorate(_pause_button, "pause")
	_pause_button.pressed.connect(func() -> void: GameRoot.request_pause())

	# --- Vitals dock (bottom-left) ------------------------------------------
	_gauges_scrim = PanelContainer.new()
	_gauges_scrim.mouse_filter = MOUSE_FILTER_IGNORE
	_gauges_scrim.add_theme_stylebox_override("panel", _scrim())
	_gauges_scrim.clip_contents = true
	add_child(_gauges_scrim)
	_gauges = GAUGES_SCENE.instantiate() as UiGauges
	_gauges_scrim.add_child(_gauges)

	_toast_label = UiFactory.title("", self, 24)
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast_label.add_theme_constant_override("outline_size", 6)
	_toast_label.visible = false

	EventBus.run_started.connect(func(_id: int, _seed: int) -> void: seed_from_run())
	EventBus.player_health_changed.connect(set_health)
	EventBus.stamina_changed.connect(set_stamina)
	EventBus.score_changed.connect(func(value: int, _delta: int) -> void: set_score(value))
	EventBus.currency_changed.connect(func(value: int, _delta: int) -> void: set_currency(value))
	EventBus.combo_changed.connect(func(value: int, _best: int) -> void: set_combo(value))
	EventBus.wave_started.connect(func(wave: int, planned: int) -> void: _wave_progress(wave, 0, planned))
	EventBus.wave_progressed.connect(_wave_progress)
	EventBus.weapon_equipped.connect(func(id: StringName, _slot: int) -> void: set_weapon(id))
	EventBus.weapon_switched.connect(func(_old: StringName, id: StringName) -> void: set_weapon(id))
	EventBus.objective_progress.connect(func(label: String, _p: int, _t: int) -> void: set_objective(label))


func _value_chip(parent: Node, accent: Color, text: String) -> Label:
	var chip := Label.new()
	chip.text = text
	chip.mouse_filter = MOUSE_FILTER_IGNORE
	chip.add_theme_font_override("font", UiTheme.BOLD)
	chip.add_theme_font_size_override("font_size", 20)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_theme_color_override("font_color", accent)
	chip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	chip.add_theme_constant_override("outline_size", 4)
	parent.add_child(chip)
	return chip


## Shared translucent plate chrome for the top strip and the gauges dock. One
## definition so both always read alike.
func _scrim() -> StyleBoxFlat:
	var style := UiTheme.glass(Color(0.05, 0.08, 0.14, 0.78))
	style.set_corner_radius_all(UiTheme.RADIUS)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func seed_from_run() -> void:
	var run := GameRoot.get_run()
	if run == null:
		return
	set_score(run.score)
	set_currency(run.currency)
	set_wave(run.current_wave)
	set_combo(run.combo)
	set_objective("")
	_toast_label.visible = false
	var player := GameRoot.get_active_player()
	if is_instance_valid(_experience) and _experience.xp_changed.is_connected(_on_xp):
		_experience.xp_changed.disconnect(_on_xp)
	_experience = null
	if not is_instance_valid(player): return
	var hp := player.get_health_component()
	if hp != null: set_health(hp.current_health, hp.max_health)
	var stamina := player.get_stamina_component()
	if stamina != null: set_stamina(stamina.get_current(), stamina.get_max())
	_experience = player.get_experience_component()
	if _experience != null:
		_experience.xp_changed.connect(_on_xp)
		_on_xp(_experience.get_xp(), _experience.get_level(), _experience.get_xp(), ExperienceComponent.xp_for_level(_experience.get_level()))
	var weapons := player.get_weapon_manager()
	if weapons != null:
		set_weapon(weapons.active_weapon_id())


## ---- Forwards to the UiGauges dock -----------------------------------------
func set_health(current: float, maximum: float) -> void: _gauges.set_health(current, maximum)
func set_stamina(current: float, maximum: float) -> void: _gauges.set_stamina(current, maximum)
func set_objective(text: String) -> void: _gauges.set_objective(text)
func _on_xp(_total: int, level: int, into: int, required: int) -> void:
	_gauges.set_xp(level, into, required)


func set_weapon(id: StringName) -> void:
	var cfg := ContentRegistry.get_weapon(id)
	_gauges.set_weapon_text(
		cfg.display_name if cfg != null else "No weapon",
		"Switch weapon: " + UiCommands.binding(&"switch_weapon"))


func set_score(score: int) -> void:
	if score == _score_cached: return
	_score_cached = score
	_score_value.text = str(score)


func set_currency(currency: int) -> void:
	if currency == _currency_cached: return
	_currency_cached = currency
	_currency_label.text = "COINS %d" % currency


func set_wave(wave: int) -> void:
	if wave == _wave_cached: return
	_wave_cached = wave
	_wave_label.text = "WAVE %d" % wave


func set_combo(combo: int) -> void:
	if combo == _combo_cached: return
	_combo_cached = combo
	_combo_label.text = "COMBO ×%d" % combo if combo > 1 else ""


func _wave_progress(wave: int, defeated: int, total: int) -> void:
	_wave_cached = wave
	_wave_label.text = "W%d • %d/%d" % [wave, defeated, total] if _compact else "WAVE %d  /  %d of %d" % [wave, defeated, total]


func show_toast(message: String) -> void:
	_toast_label.text = message
	_toast_label.visible = _toast_fits
	_toast_show_until = Time.get_ticks_msec() + 3500


func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_weapon_refresh += delta
	if _weapon_refresh >= 0.15:
		_weapon_refresh = 0
		_refresh_weapon()
	if _toast_show_until > 0 and Time.get_ticks_msec() > _toast_show_until:
		_toast_show_until = 0
		_toast_label.visible = false


## Position every HUD element from the shared layout solution (safe-area local).
func vitals_screen_rect() -> Rect2:
	if _gauges_scrim == null:
		return Rect2()
	return _gauges_scrim.get_global_rect()


func apply_layout(plan: Dictionary, view: Vector2) -> void:
	if _top == null: return
	_compact = bool(plan.get("compact", false)) or SaveManager.get_settings().text_scale > 1.3
	var top_bar: Rect2 = plan["top_bar"]
	var vitals: Rect2 = plan["vitals"]
	UiLayout.place(_top_scrim, top_bar, view)
	UiLayout.place(_gauges_scrim, vitals, view)
	UiLayout.place(_toast_label, plan["toast"], view)
	_gauges_scrim.visible = not UiLayout.is_collapsed(vitals)
	_toast_fits = not UiLayout.is_collapsed(plan["toast"])
	if not _toast_fits:
		_toast_label.visible = false
	for label in [_wave_label, _score_value, _currency_label, _combo_label]:
		label.custom_minimum_size.x = 0
	_wave_label.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_combo_label.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_currency_label.size_flags_horizontal = SIZE_SHRINK_END
	_score_value.size_flags_horizontal = SIZE_SHRINK_END
	_currency_label.visible = not _compact or top_bar.size.x > 620.0
	_gauges.custom_minimum_size.x = maxf(vitals.size.x - 28.0, 120.0)


func _refresh_weapon() -> void:
	var player := GameRoot.get_active_player()
	if not is_instance_valid(player): return
	var manager := player.get_weapon_manager()
	if manager == null: return
	var active := manager.active_instance()
	var caption := ""
	var tip := ""
	if active == null or active.config == null:
		caption = "No weapon equipped"
	else:
		var status := String(active.phase).to_upper()
		if active.config.has_ammo(): status += "  %d / %d" % [active.ammo, active.config.ammo_per_magazine]
		caption = "%s • %s" % [active.config.display_name, status]
		var slots := PackedStringArray()
		for index in range(2):
			var item := manager.slot_instance(index)
			slots.append(item.config.display_name if item != null and item.config != null else "Empty")
		tip = "Loadout: %s\nSwitch: %s" % [" / ".join(slots), UiCommands.binding(&"switch_weapon")]
	# Dirty-flag: the 0.15 s poll only rewrites the dock when the loadout or ammo
	# actually changed, so an idle run stops rebuilding text every frame.
	if caption == _weapon_caption_cache and tip == _weapon_tip_cache:
		return
	_weapon_caption_cache = caption
	_weapon_tip_cache = tip
	_gauges.set_weapon_text(caption, tip)
