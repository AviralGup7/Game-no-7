class_name SettingsPanel
extends VBoxContainer

## Full settings form: master/music/SFX volumes, camera shake + reduced motion,
## mute/vibration/high-contrast, touch layout scale, FPS cap, quality tier, and
## input rebind buttons for the remappable actions. Reads/writes SettingsData
## through SaveManager and pushes live changes to AudioManager / HitstopManager /
## PerformanceMonitor. Code-built so it drops into any menu scene.

signal settings_applied()
signal close_requested()

var _settings: SettingsData = null
var _volume_sliders: Dictionary = {}
var _shake_check: CheckButton = null
var _motion_check: CheckButton = null
var _mute_check: CheckButton = null
var _vibration_check: CheckButton = null
var _contrast_check: CheckButton = null
var _fps_option: OptionButton = null
var _quality_option: OptionButton = null
var _rebind_buttons: Dictionary = {}
var _awaiting_action: StringName = &""


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_load_settings()
	_build_audio_section()
	_build_accessibility_section()
	_build_general_section()
	_build_performance_section()
	_build_rebind_section()
	_build_buttons()


func _load_settings() -> void:
	if SaveManager != null and SaveManager.has_method("get_settings"):
		_settings = SaveManager.call("get_settings")
	if _settings == null:
		_settings = SettingsData.new()


func _section(title: String) -> VBoxContainer:
	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 18)
	add_child(header)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	return box


func _build_audio_section() -> void:
	var box := _section("Audio")
	_volume_sliders[&"master"] = _volume_row(box, "Master", _settings.get_master_volume() if _settings.has_method("get_master_volume") else 1.0)
	_volume_sliders[&"music"] = _volume_row(box, "Music", _settings.get_music_volume() if _settings.has_method("get_music_volume") else 0.8)
	_volume_sliders[&"sfx"] = _volume_row(box, "Effects", _settings.get_sfx_volume() if _settings.has_method("get_sfx_volume") else 1.0)


func _volume_row(parent: VBoxContainer, label_text: String, value: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(90, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = clampf(value, 0.0, 1.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_volume_changed)
	row.add_child(slider)
	parent.add_child(row)
	return slider


func _build_accessibility_section() -> void:
	var box := _section("Accessibility")
	_shake_check = _check_row(box, "Camera shake", not _settings.get_reduced_motion() if _settings.has_method("get_reduced_motion") else true)
	_motion_check = _check_row(box, "Reduced motion", _settings.get_reduced_motion() if _settings.has_method("get_reduced_motion") else false)


func _build_general_section() -> void:
	var box := _section("General")
	_mute_check = _check_row(box, "Mute audio", _settings.is_muted() if _settings.has_method("is_muted") else false)
	_vibration_check = _check_row(box, "Vibration", _settings.is_vibration_enabled() if _settings.has_method("is_vibration_enabled") else true)
	_contrast_check = _check_row(box, "High contrast", _settings.is_high_contrast() if _settings.has_method("is_high_contrast") else false)


func _check_row(parent: VBoxContainer, label_text: String, pressed: bool) -> CheckButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var check := CheckButton.new()
	check.button_pressed = pressed
	check.toggled.connect(_on_accessibility_changed)
	row.add_child(check)
	parent.add_child(row)
	return check


func _build_performance_section() -> void:
	var box := _section("Performance")
	_fps_option = OptionButton.new()
	for cap in [30, 60, 120]:
		_fps_option.add_item("%d FPS" % cap, cap)
	_fps_option.add_item("Unlimited", 0)
	_fps_option.selected = 1
	_fps_option.item_selected.connect(_on_fps_selected)
	box.add_child(_fps_option)
	_quality_option = OptionButton.new()
	for tier in ["Low", "Medium", "High", "Ultra"]:
		_quality_option.add_item(tier)
	_quality_option.selected = 2
	_quality_option.item_selected.connect(_on_quality_selected)
	box.add_child(_quality_option)


func _build_rebind_section() -> void:
	var box := _section("Controls (keyboard / gamepad)")
	for action in InputRemapper.REMAPPABLE_ACTIONS:
		var aname := StringName(String(action))
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = String(action).capitalize().replace("_", " ")
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button := Button.new()
		button.text = _bindings_text(aname)
		button.custom_minimum_size = Vector2(160, 0)
		var act := aname
		button.pressed.connect(func() -> void: _begin_rebind(act))
		row.add_child(button)
		_rebind_buttons[aname] = button
		box.add_child(row)


func _bindings_text(action: StringName) -> String:
	var binds := InputRemapper.get_bindings(action)
	if binds.is_empty():
		return "—"
	return InputRemapper.binding_label(binds[0])


func _build_buttons() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: close_requested.emit())
	row.add_child(close)
	var apply := Button.new()
	apply.text = "Apply"
	apply.pressed.connect(_apply)
	row.add_child(apply)
	add_child(row)


func _begin_rebind(action: StringName) -> void:
	_awaiting_action = action
	(_rebind_buttons[action] as Button).text = "Press a key..."


func _unhandled_input(event: InputEvent) -> void:
	if _awaiting_action == &"":
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			_finish_rebind(_awaiting_action, key_event)
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton:
		var pad_event := event as InputEventJoypadButton
		if pad_event.pressed:
			_finish_rebind(_awaiting_action, pad_event)
			get_viewport().set_input_as_handled()


func _finish_rebind(action: StringName, event: InputEvent) -> void:
	_awaiting_action = &""
	var conflict := InputRemapper.find_conflict(event, action)
	if conflict != &"" and EventBus != null:
		EventBus.report_warning("Binding conflicts with %s" % String(conflict))
	InputRemapper.rebind_first(action, event)
	(_rebind_buttons[action] as Button).text = InputRemapper.binding_label(event)


func _on_volume_changed(_value: float) -> void:
	_push_audio_live()


func _on_accessibility_changed(_pressed: bool) -> void:
	_push_accessibility_live()
	_push_mute_live()


func _on_fps_selected(index: int) -> void:
	Engine.max_fps = _fps_option.get_item_id(index)


func _on_quality_selected(index: int) -> void:
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group("performance_monitor"):
			if node.has_method("set_tier"):
				node.call("set_tier", index)


func _push_audio_live() -> void:
	if AudioManager == null:
		return
	if AudioManager.has_method("set_master_volume"):
		AudioManager.call("set_master_volume", float((_volume_sliders[&"master"] as HSlider).value))
	if AudioManager.has_method("set_music_volume"):
		AudioManager.call("set_music_volume", float((_volume_sliders[&"music"] as HSlider).value))
	if AudioManager.has_method("set_sfx_volume"):
		AudioManager.call("set_sfx_volume", float((_volume_sliders[&"sfx"] as HSlider).value))


func _push_accessibility_live() -> void:
	var reduced := _motion_check.button_pressed
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group("hitstop_manager"):
			if node.has_method("set_reduced_motion"):
				node.call("set_reduced_motion", reduced or not _shake_check.button_pressed)


func _push_mute_live() -> void:
	if AudioManager != null and AudioManager.has_method("set_muted"):
		AudioManager.call("set_muted", _mute_check.button_pressed)


func _apply() -> void:
	if _settings != null:
		if _settings.has_method("set_master_volume"):
			_settings.call("set_master_volume", float((_volume_sliders[&"master"] as HSlider).value))
		if _settings.has_method("set_music_volume"):
			_settings.call("set_music_volume", float((_volume_sliders[&"music"] as HSlider).value))
		if _settings.has_method("set_sfx_volume"):
			_settings.call("set_sfx_volume", float((_volume_sliders[&"sfx"] as HSlider).value))
		if _settings.has_method("set_muted"):
			_settings.call("set_muted", _mute_check.button_pressed)
		if _settings.has_method("set_reduced_motion"):
			_settings.call("set_reduced_motion", _motion_check.button_pressed)
		if _settings.has_method("set_vibration_enabled"):
			_settings.call("set_vibration_enabled", _vibration_check.button_pressed)
		if _settings.has_method("set_high_contrast"):
			_settings.call("set_high_contrast", _contrast_check.button_pressed)
	if SaveManager != null and SaveManager.has_method("save_settings"):
		SaveManager.call("save_settings", _settings)
	_push_audio_live()
	_push_accessibility_live()
	_push_mute_live()
	settings_applied.emit()
