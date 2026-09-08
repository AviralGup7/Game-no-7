class_name SettingsPanel
extends VBoxContainer
## Staged SettingsData copy; Apply delegates persistence to SaveManager. No
## private save files. Runtime-only controls are explicitly labelled as such.
signal settings_applied()
signal close_requested()
var _draft: SettingsData
var _feedback: Label
var _awaiting_action: StringName = &""
var _rebind_buttons: Dictionary = {}
var _pending_bindings: Dictionary = {}
var _fps := 0
var _volume_labels: Dictionary = {}

func _ready() -> void:
	EventBus.save_failed.connect(func(_reason: StringName) -> void:
		if is_visible_in_tree(): _feedback.text = "Could not save settings. Please retry before closing the game.")
	refresh()

func refresh() -> void:
	cancel_edit()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_draft = SettingsData.new()
	_draft.from_dict(SaveManager.get_settings().to_dict())
	_fps = Engine.max_fps
	_pending_bindings.clear()
	_rebind_buttons.clear()
	_volume_labels.clear()
	UiFactory.label("Apply saves your changes. Back discards unapplied edits.", self, 20)
	_section("AUDIO")
	for key in ["master", "music", "sfx"]:
		_volume_row(key)
	_toggle("Mute audio", _draft.muted, func(value: bool) -> void: _draft.set_muted(value))
	_section("ACCESSIBILITY & CONTROLS")
	_toggle("Reduced motion (also reduces shake)", _draft.reduced_motion, func(value: bool) -> void: _draft.set_reduced_motion(value))
	_toggle("High contrast", _draft.high_contrast, func(value: bool) -> void: _draft.set_high_contrast(value))
	_toggle("Vibration", _draft.vibration_enabled, func(value: bool) -> void: _draft.set_vibration_enabled(value))
	_toggle("Aim assist", _draft.aim_assist_enabled, func(value: bool) -> void: _draft.set_aim_assist_enabled(value))
	var scale_label := UiFactory.label("Text size  %d%%" % int(_draft.text_scale * 100), self)
	var scale_slider := _slider(SettingsData.MIN_TEXT_SCALE, SettingsData.MAX_TEXT_SCALE, 0.1, _draft.text_scale)
	scale_slider.value_changed.connect(func(value: float) -> void:
		_draft.set_text_scale(value)
		scale_label.text = "Text size  %d%% — applied on Save" % int(value * 100))
	UiFactory.label("Touch controls adapt automatically to the safe area. Skills stay separate from the movement stick.", self, 18)
	_section("PERFORMANCE")
	var quality := OptionButton.new()
	quality.custom_minimum_size.y = 56
	var tiers := [&"low", &"medium", &"high"]
	for tier in tiers: quality.add_item("Quality: " + String(tier).capitalize())
	quality.select(maxi(tiers.find(_draft.graphics_quality), 0))
	quality.item_selected.connect(func(index: int) -> void: _draft.set_graphics_quality(tiers[index]))
	add_child(quality)
	var fps := OptionButton.new()
	fps.custom_minimum_size.y = 56
	for cap in [30, 60, 120, 0]:
		fps.add_item(("%d FPS" % cap if cap > 0 else "Unlimited FPS") + " (this session)", cap)
	fps.select(maxi(fps.get_item_index(_fps), 0))
	fps.item_selected.connect(func(index: int) -> void: _fps = fps.get_item_id(index))
	add_child(fps)
	_section("KEYBOARD / GAMEPAD BINDINGS")
	UiFactory.label("Bindings apply for this session only; the current save schema has no binding field. Escape cancels capture. Conflicts are rejected.", self, 18)
	for action in InputRemapper.REMAPPABLE_ACTIONS:
		var row := HBoxContainer.new()
		add_child(row)
		var label := UiFactory.label(String(action).replace("_", " ").capitalize(), row, 20)
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		var button := UiFactory.button(UiCommands.binding(action), row, 20, Vector2(220, 56))
		_rebind_buttons[action] = button
		var id: StringName = action
		button.pressed.connect(func() -> void: _begin_rebind(id))
	_feedback = UiFactory.label("", self, 20)
	_feedback.modulate = UiTheme.GOLD
	UiFactory.button("SAVE SETTINGS", self, 24).pressed.connect(_apply)
	UiFactory.button("RESTORE & SAVE DEFAULTS", self, 20).pressed.connect(_reset_draft)
	UiFactory.button("BACK", self, 20).pressed.connect(func() -> void: close_requested.emit())
	UiTheme.apply_text_scale(self, SaveManager.get_settings().text_scale)

func _section(text: String) -> void:
	UiFactory.title(text, self, 22).modulate = UiTheme.CYAN

func _slider(minimum: float, maximum: float, step: float, value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.y = 48
	add_child(slider)
	return slider

func _volume_row(key: String) -> void:
	var value := float(_draft.get(key + "_volume"))
	var label := UiFactory.label("%s  %d%%" % [key.capitalize(), int(value * 100)], self)
	_volume_labels[key] = label
	var slider := _slider(0, 1, 0.01, value)
	slider.value_changed.connect(func(amount: float) -> void:
		_draft.call("set_" + key + "_volume", amount)
		label.text = "%s  %d%%" % [key.capitalize(), int(amount * 100)])

func _toggle(text: String, initial: bool, callback: Callable) -> void:
	var row := HBoxContainer.new()
	add_child(row)
	var label := UiFactory.label(text, row, 20)
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	var check := CheckButton.new()
	check.custom_minimum_size = Vector2(90, 56)
	check.button_pressed = initial
	check.tooltip_text = text
	check.toggled.connect(callback)
	row.add_child(check)

func _begin_rebind(action: StringName) -> void:
	cancel_edit()
	_awaiting_action = action
	_rebind_buttons[action].text = "Press key / pad…"
	_feedback.text = "Press a key or controller button. Escape cancels."

func is_rebinding() -> bool: return _awaiting_action != &""

func cancel_edit() -> void:
	if _awaiting_action != &"" and _rebind_buttons.has(_awaiting_action):
		_rebind_buttons[_awaiting_action].text = UiCommands.binding(_awaiting_action)
	_awaiting_action = &""

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not is_rebinding(): return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			cancel_edit()
			_feedback.text = "Binding unchanged."
			return
		# Normalize physical codes for InputRemapper conflict/serialization helpers.
		var key := InputEventKey.new()
		key.physical_keycode = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		_finish_rebind(key)
	elif event is InputEventJoypadButton and event.pressed:
		get_viewport().set_input_as_handled()
		_finish_rebind(event)

func _finish_rebind(event: InputEvent) -> void:
	var conflict := InputRemapper.find_conflict(event, _awaiting_action)
	for action in _pending_bindings:
		if action != _awaiting_action and InputRemapper._events_match(_pending_bindings[action], event):
			conflict = action
	if conflict != &"":
		_feedback.text = "Already used by %s. Choose another binding or press Escape." % String(conflict)
		return
	_pending_bindings[_awaiting_action] = event
	_rebind_buttons[_awaiting_action].text = InputRemapper.binding_label(event) + " *"
	_awaiting_action = &""
	_feedback.text = "Binding staged. Save settings to apply."

func _apply() -> void:
	cancel_edit()
	for action in _pending_bindings:
		if not InputRemapper.rebind_first(action, _pending_bindings[action]):
			_feedback.text = "Binding could not be applied. Too many bindings for this action."
			return
	_pending_bindings.clear()
	Engine.max_fps = _fps
	var saved := SettingsData.new()
	saved.from_dict(_draft.to_dict())
	SaveManager.save_settings(saved)
	_feedback.text = "Settings applied. Session-only choices reset when the game closes."
	# SaveManager owns retries/disk status; do not claim success before its result.
	if not SaveManager.save_now():
		_feedback.text = "Settings applied in memory, but saving failed. Please retry."
	settings_applied.emit()

func _reset_draft() -> void:
	# Explicit reset command belongs to SaveManager, not a duplicate save schema.
	SaveManager.reset_settings()
	refresh()
	_feedback.text = "Saved settings restored to defaults. Session-only bindings are unchanged."
