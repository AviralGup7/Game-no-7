extends Control
## UI root controller. Owns panel switching (only one major screen visible at a time),
## hosts the touch controls, routes joystick/action intents to the active player, and
## keeps text behind a centralized lookup so localization can be added later.
## Controllers never mutate global state directly: they call GameRoot's command API.

const VIRTUAL_JOYSTICK := preload("res://scripts/ui/virtual_joystick.gd")
const TOUCH_ACTION := preload("res://scripts/ui/touch_action_button.gd")

## Screens (mutually exclusive).
var _main_panel: Control = null
var _settings_panel: Control = null
var _pause_panel: Control = null
var _gameover_panel: Control = null
var _upgrade_panel: Control = null

## HUD (overlay while playing).
var _hud: Control = null
var _touch_layer: Control = null
var _joystick: Control = null
var _attack_btn: Control = null
var _dodge_btn: Control = null

## HUD widgets.
var _hp_label: Label = null
var _hp_bar: ColorRect = null
var _score_label: Label = null
var _wave_label: Label = null
var _combo_label: Label = null
var _currency_label: Label = null

var _last_joystick_value := Vector2.ZERO
var _active_screen := &"none"

# Default English strings (single shipped language for now). Localization swaps this
# table or the whole lookup for translated packs later without touching call sites.
const _TEXT := {
	"app_title": "LAST STAND",
	"app_subtitle": "ARENA",
	"play": "PLAY",
	"settings": "SETTINGS",
	"quit": "QUIT",
	"resume": "RESUME",
	"restart": "RESTART",
	"main_menu": "MAIN MENU",
	"best_score": "Best score",
	"best_wave": "Best wave",
	"score": "SCORE",
	"wave": "WAVE",
	"combo": "COMBO",
	"currency": "COINS",
	"hp": "HP",
	"paused": "PAUSED",
	"game_over": "GAME OVER",
	"kills": "Kills",
	"time_survived": "Time survived",
	"wave_reached": "Wave reached",
	"upgrades_title": "CHOOSE AN UPGRADE",
	"upgrade_pending": "Upgrades unlock as waves are cleared.",
	"retry": "RETRY",
	"close_settings": "CLOSE",
	"reset_settings": "RESET SETTINGS",
	"mute": "Mute audio",
	"vibration": "Vibration",
	"reduced_motion": "Reduced motion",
	"high_contrast": "High contrast",
	"version": "v0.2.0",
}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_screens()
	_build_hud()
	_build_touch()
	EventBus.game_state_changed.connect(_on_state_changed)
	EventBus.player_health_changed.connect(_on_health_changed)
	EventBus.score_changed.connect(_on_score_changed)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.combo_changed.connect(_on_combo_changed)
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.run_ended.connect(func(_s: int, _w: int, _b: int) -> void:
		_refresh_gameover_best()
		_update_gameover_stats())
	_sync_from_state()


func _process(_delta: float) -> void:
	if GameRoot.get_current_state() != GameRoot.State.PLAYING and GameRoot.get_current_state() != GameRoot.State.WAVE_TRANSITION:
		return
	var v := _joystick.get_value()
	if v != _last_joystick_value:
		_last_joystick_value = v
		var p := GameRoot.get_active_player()
		if p != null and is_instance_valid(p) and p.has_method("set_move_input"):
			p.call("set_move_input", v)


# ---------------------------- Layout builders ----------------------------

func _make_panel(name: String) -> Control:
	var panel := Control.new()
	panel.name = name
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	panel.visible = false
	return panel


func _center_container(panel: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	return box


func _title(text: String, parent: Node) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", _font(30))
	parent.add_child(l)
	return l


func _make_button(text: String, parent: Node) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 54)
	b.add_theme_font_size_override("font_size", _font(20))
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(b)
	return b


func _check(text: String, parent: Node, initial: bool, on_toggle: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = initial
	c.add_theme_font_size_override("font_size", _font(18))
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.toggled.connect(on_toggle)
	parent.add_child(c)
	return c


func _font(base: int) -> int:
	var settings := SaveManager.get_settings()
	return int(round(base * settings.text_scale))


func _build_screens() -> void:
	_main_panel = _make_panel("MainMenuPanel")
	var box := _center_container(_main_panel)
	_title(loc(&"app_title"), box)
	_title(loc(&"app_subtitle"), box)
	_title("", box)  # spacer
	var play_btn := _make_button(loc(&"play"), box)
	play_btn.pressed.connect(func() -> void: GameRoot.request_play())
	var settings_btn := _make_button(loc(&"settings"), box)
	settings_btn.pressed.connect(_open_settings)
	var quit_btn := _make_button(loc(&"quit"), box)
	quit_btn.pressed.connect(_request_quit)
	_best_menu_labels(box)

	_build_settings_screen()
	_build_pause_screen()
	_build_gameover_screen()
	_build_upgrade_screen()


func _best_menu_labels(box: VBoxContainer) -> void:
	var bs := Label.new()
	bs.name = "BestScoreLabel"
	bs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bs.add_theme_font_size_override("font_size", _font(16))
	box.add_child(bs)
	_refresh_best_label(bs)
	var ver := Label.new()
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.text = loc(&"version")
	ver.add_theme_font_size_override("font_size", _font(12))
	ver.modulate.a = 0.6
	box.add_child(ver)


func _build_settings_screen() -> void:
	_settings_panel = _make_panel("SettingsPanel")
	var box := _center_container(_settings_panel)
	_title(loc(&"settings"), box)
	var s := SaveManager.get_settings()
	_check(loc(&"mute"), box, s.muted, func(v: bool) -> void:
		var cur := SaveManager.get_settings(); cur.muted = v; _persist())
	_check(loc(&"vibration"), box, s.vibration_enabled, func(v: bool) -> void:
		var cur := SaveManager.get_settings(); cur.vibration_enabled = v; _persist())
	_check(loc(&"reduced_motion"), box, s.reduced_motion, func(v: bool) -> void:
		var cur := SaveManager.get_settings(); cur.reduced_motion = v; _persist())
	_check(loc(&"high_contrast"), box, s.high_contrast, func(v: bool) -> void:
		var cur := SaveManager.get_settings(); cur.high_contrast = v; _persist())
	var reset_btn := _make_button(loc(&"reset_settings"), box)
	reset_btn.pressed.connect(func() -> void:
		SaveManager.reset_settings(); _open_settings())
	var close_btn := _make_button(loc(&"close_settings"), box)
	close_btn.pressed.connect(_close_settings)


func _persist() -> void:
	SaveManager.persist_settings()


func _build_pause_screen() -> void:
	_pause_panel = _make_panel("PausePanel")
	var box := _center_container(_pause_panel)
	_title(loc(&"paused"), box)
	var resume_btn := _make_button(loc(&"resume"), box)
	resume_btn.pressed.connect(func() -> void: GameRoot.request_resume())
	var restart_btn := _make_button(loc(&"restart"), box)
	restart_btn.pressed.connect(func() -> void: GameRoot.request_restart())
	var menu_btn := _make_button(loc(&"main_menu"), box)
	menu_btn.pressed.connect(func() -> void: GameRoot.request_main_menu())
	var set_btn := _make_button(loc(&"settings"), box)
	set_btn.pressed.connect(_open_settings)


func _build_gameover_screen() -> void:
	_gameover_panel = _make_panel("GameOverPanel")
	var box := _center_container(_gameover_panel)
	_title(loc(&"game_over"), box)
	var stats := Label.new()
	stats.name = "RunStatsLabel"
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", _font(18))
	box.add_child(stats)
	var retry_btn := _make_button(loc(&"retry"), box)
	retry_btn.pressed.connect(func() -> void: GameRoot.request_play())
	var menu_btn := _make_button(loc(&"main_menu"), box)
	menu_btn.pressed.connect(func() -> void: GameRoot.request_main_menu())
	_gameover_stats = stats


var _gameover_stats: Label = null


func _build_upgrade_screen() -> void:
	_upgrade_panel = _make_panel("UpgradePanel")
	var box := _center_container(_upgrade_panel)
	_title(loc(&"upgrades_title"), box)
	var note := Label.new()
	note.text = loc(&"upgrade_pending")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", _font(18))
	box.add_child(note)


func _build_hud() -> void:
	_hud = Control.new()
	_hud.name = "GameplayHUD"
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_hud.visible = false

	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(top)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", _font(18))
	top.add_child(_hp_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	_wave_label = Label.new()
	_wave_label.text = loc(&"wave") + " 1"
	_wave_label.add_theme_font_size_override("font_size", _font(20))
	top.add_child(_wave_label)

	_combo_label = Label.new()
	_combo_label.text = ""
	_combo_label.add_theme_font_size_override("font_size", _font(18))
	top.add_child(_combo_label)

	_currency_label = Label.new()
	_currency_label.text = loc(&"currency") + " 0"
	_currency_label.add_theme_font_size_override("font_size", _font(18))
	top.add_child(_currency_label)

	_score_label = Label.new()
	_score_label.text = loc(&"score") + " 0"
	_score_label.add_theme_font_size_override("font_size", _font(22))
	top.add_child(_score_label)

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
	_hud.add_child(_hp_bar)

	var pause_btn := Button.new()
	pause_btn.text = "II"
	pause_btn.anchor_left = 1.0
	pause_btn.anchor_right = 1.0
	pause_btn.anchor_top = 0.0
	pause_btn.offset_left = -80
	pause_btn.offset_right = -12
	pause_btn.offset_top = 10
	pause_btn.offset_bottom = 54
	pause_btn.add_theme_font_size_override("font_size", _font(20))
	pause_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_btn.pressed.connect(func() -> void: GameRoot.request_pause())
	_hud.add_child(pause_btn)


func _build_touch() -> void:
	_touch_layer = Control.new()
	_touch_layer.name = "TouchControls"
	_touch_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_touch_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_touch_layer)
	_touch_layer.visible = false

	_joystick = VIRTUAL_JOYSTICK.new()
	_joystick.name = "MovementJoystick"
	_joystick.anchor_left = 0.0
	_joystick.anchor_right = 0.0
	_joystick.anchor_top = 1.0
	_joystick.anchor_bottom = 1.0
	_joystick.offset_left = 8
	_joystick.offset_right = 480
	_joystick.offset_top = -440
	_joystick.offset_bottom = 8
	_joystick.mouse_filter = Control.MOUSE_FILTER_STOP
	_touch_layer.add_child(_joystick)

	_attack_btn = TOUCH_ACTION.new()
	_attack_btn.name = "AttackButton"
	_attack_btn.action_name = "attack"
	_attack_btn.vibrate_on_press = true
	_attack_btn.anchor_left = 1.0
	_attack_btn.anchor_top = 1.0
	_attack_btn.offset_left = -150
	_attack_btn.offset_right = -38
	_attack_btn.offset_top = -180
	_attack_btn.offset_bottom = -68
	_attack_btn.pressed.connect(func() -> void:
		var p := GameRoot.get_active_player()
		if p != null and is_instance_valid(p) and p.has_method("request_attack"):
			p.call("request_attack"))
	_touch_layer.add_child(_attack_btn)

	_dodge_btn = TOUCH_ACTION.new()
	_dodge_btn.name = "DodgeButton"
	_dodge_btn.action_name = "dodge"
	_dodge_btn.radius = 44.0
	_dodge_btn.anchor_left = 1.0
	_dodge_btn.anchor_top = 1.0
	_dodge_btn.offset_left = -270
	_dodge_btn.offset_right = -182
	_dodge_btn.offset_top = -110
	_dodge_btn.offset_bottom = -22
	_dodge_btn.pressed.connect(func() -> void:
		var p := GameRoot.get_active_player()
		if p != null and is_instance_valid(p) and p.has_method("request_dodge"):
			p.call("request_dodge"))
	_touch_layer.add_child(_dodge_btn)


# ---------------------------- Screen switching ----------------------------

func _show_screen(screen: StringName) -> void:
	_active_screen = screen
	_main_panel.visible = screen == &"main_menu" or screen == &"main_menu_settings"
	_settings_panel.visible = screen == &"settings"
	_pause_panel.visible = screen == &"paused"
	_gameover_panel.visible = screen == &"game_over"
	_upgrade_panel.visible = screen == &"upgrade_selection"
	var playing := screen == &"playing" or screen == &"wave_transition"
	_hud.visible = playing
	_touch_layer.visible = playing


func _sync_from_state() -> void:
	var state := GameRoot.get_current_state()
	match state:
		GameRoot.State.MAIN_MENU:
			_show_screen(&"main_menu")
		GameRoot.State.PLAYING, GameRoot.State.WAVE_TRANSITION:
			_show_screen(&"playing")
		GameRoot.State.UPGRADE_SELECTION:
			_show_screen(&"upgrade_selection")
		GameRoot.State.PAUSED:
			_show_screen(&"paused")
		GameRoot.State.GAME_OVER:
			_show_screen(&"game_over")
			_update_gameover_stats()
		_:
			_show_screen(&"main_menu")


func _on_state_changed(_p: StringName, _c: StringName) -> void:
	pass  # handled via _sync_from_state; kept for clarity/extension


func _open_settings() -> void:
	_show_screen(&"settings")


func _close_settings() -> void:
	if GameRoot.get_current_state() == GameRoot.State.MAIN_MENU:
		_show_screen(&"main_menu")
	elif GameRoot.get_current_state() == GameRoot.State.PAUSED:
		_show_screen(&"paused")


func _request_quit() -> void:
	get_tree().quit()


# ---------------------------- HUD updates ----------------------------

func _on_health_changed(current: float, maximum: float) -> void:
	_hp_label.text = "%s %d / %d" % [loc(&"hp"), int(round(current)), int(round(maximum))]
	if maximum > 0.0:
		var ratio := clampf(current / maximum, 0.0, 1.0)
		_hp_bar.offset_right = 12 + ratio * 208.0


func _on_score_changed(score: int, _delta: int) -> void:
	_score_label.text = "%s %d" % [loc(&"score"), score]


func _on_wave_started(wave_number: int, _planned: int) -> void:
	_wave_label.text = "%s %d" % [loc(&"wave"), wave_number]


func _on_combo_changed(combo: int, best: int) -> void:
	_combo_label.text = "%s %d" % [loc(&"combo"), combo] if combo > 1 else ""


func _on_currency_changed(currency: int, _delta: int) -> void:
	_currency_label.text = "%s %d" % [loc(&"currency"), currency]


func _refresh_best_label(label: Label) -> void:
	label.text = "%s %d    %s %d" % [
		loc(&"best_score"), GameRoot.get_best_score(),
		loc(&"best_wave"), GameRoot.get_best_wave(),
	]


func _refresh_gameover_best() -> void:
	for child in _main_panel.find_children("*", "Label", true, false):
		if child.name == "BestScoreLabel":
			_refresh_best_label(child)


func _update_gameover_stats() -> void:
	if _gameover_stats == null:
		return
	var run := GameRoot.get_run()
	var secs := int(run.elapsed_seconds)
	var summary := run.summary()
	_gameover_stats.text = "%s: %d\n%s: %d\n%s: %d\n%s: %ds\n%s: %d" % [
		loc(&"score"), summary.score,
		loc(&"wave_reached"), summary.current_wave,
		loc(&"kills"), summary.kills,
		loc(&"time_survived"), secs,
		loc(&"best_score"), GameRoot.get_best_score(),
	]


# ---------------------------- Localization ----------------------------

func loc(key: StringName) -> String:
	var k := String(key)
	if _TEXT.has(k):
		return _TEXT[k]
	return k


func get_debug_snapshot() -> Dictionary:
	return {
		"active_screen": String(_active_screen),
		"joystick_active": _joystick.is_active(),
		"joystick_value": _joystick.get_value(),
	}
