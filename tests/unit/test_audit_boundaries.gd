extends RefCounted
## Behavioral regressions from the project-wide audit. InputMap changes are
## restored exactly, including mouse/axis bindings, before returning to the runner.

static func suite() -> Array:
	var results: Array = []
	_test_bindings(results)
	_test_settings_and_save(results)
	_test_json(results)
	return results


static func _check(results: Array, label: String, passed: bool) -> void:
	results.append({"name": label, "passed": passed, "why": ""})


static func _key(code: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.physical_keycode = code
	return key


static func _pad(code: JoyButton) -> InputEventJoypadButton:
	var pad := InputEventJoypadButton.new()
	pad.button_index = code
	return pad


static func _restore(bindings: Dictionary) -> void:
	for action in bindings:
		InputMap.action_erase_events(action)
		for event in bindings[action]:
			InputMap.action_add_event(action, event)


static func _test_bindings(results: Array) -> void:
	var original: Dictionary = {}
	for action in InputMap.get_actions():
		original[action] = InputMap.action_get_events(action)
	InputMap.load_from_project_settings()
	var defaults: Dictionary = {}
	for action in InputMap.get_actions():
		defaults[action] = InputMap.action_get_events(action)
	for action in InputRemapper.REMAPPABLE_ACTIONS + InputRemapper.RESERVED_ACTIONS:
		for event in InputMap.action_get_events(action):
			if event is InputEventKey or event is InputEventJoypadButton:
				_check(results, "default input has no gameplay conflict: " + String(action) + " " + event.as_text(), InputRemapper.find_conflict(event, action) == &"")
	_check(results, "Start pauses and shoulders activate skills", InputMap.action_has_event(&"pause", _pad(JOY_BUTTON_START)) and InputMap.action_has_event(&"skill_1", _pad(JOY_BUTTON_LEFT_SHOULDER)) and InputMap.action_has_event(&"skill_2", _pad(JOY_BUTTON_RIGHT_SHOULDER)))
	_check(results, "pad labels follow Godot 4 enum values", InputRemapper.binding_label(_pad(JOY_BUTTON_START)) == "Pad Start" and InputRemapper.binding_label(_pad(JOY_BUTTON_LEFT_SHOULDER)) == "Pad LB")
	var attack_events := InputMap.action_get_events(&"attack").size()
	_check(results, "default four-event fire action can be rebound", InputRemapper.rebind_first(&"attack", _key(KEY_V)))
	_check(results, "fire remap preserves mouse and pad", InputMap.action_get_events(&"attack").size() == attack_events and InputMap.action_has_event(&"attack", _pad(JOY_BUTTON_A)))
	InputRemapper.rebind_first(&"attack", _key(KEY_B))
	_check(results, "repeated remap replaces primary, not secondary", InputMap.action_has_event(&"attack", _key(KEY_B)) and InputMap.action_has_event(&"attack", _key(KEY_ENTER)) and not InputMap.action_has_event(&"attack", _key(KEY_V)))
	InputRemapper.rebind_first(&"attack", _key(KEY_ENTER))
	_check(results, "rebinding to own secondary deduplicates", InputMap.action_get_events(&"attack").size() == attack_events - 1)

	InputMap.action_erase_events(&"attack")
	for code in [KEY_C, KEY_V, KEY_B]:
		InputMap.action_add_event(&"attack", _key(code))
	var before := InputRemapper.serialize_actions()
	_check(results, "full action rejects extra device without erasing a key", not InputRemapper.rebind_first(&"attack", _pad(JOY_BUTTON_A)) and InputRemapper.serialize_actions() == before)
	_check(results, "batch failure rolls back all earlier edits", not InputRemapper.rebind_actions({&"dodge": _key(KEY_H), &"attack": _pad(JOY_BUTTON_A)}) and InputRemapper.serialize_actions() == before)
	_restore(defaults)

	_check(results, "movement controls are reserved during remapping", InputRemapper.find_conflict(_key(KEY_W), &"attack") == &"move_up")
	var logical := InputEventKey.new()
	logical.keycode = KEY_SPACE
	_check(results, "logical and physical codes conflict", InputRemapper.find_conflict(logical, &"dodge") == &"attack")
	var edits := {&"dodge": _key(KEY_C), &"attack": _key(KEY_SHIFT)}
	_check(results, "staging frees the old binding for another action", InputRemapper.find_conflict(_key(KEY_SHIFT), &"attack", edits) == &"")
	_check(results, "staged nonconflicting batch applies atomically", InputRemapper.rebind_actions(edits) and InputMap.action_has_event(&"attack", _key(KEY_SHIFT)) and InputMap.action_has_event(&"dodge", _key(KEY_C)))
	before = InputRemapper.serialize_actions()
	_check(results, "duplicate staged keys are rejected atomically", not InputRemapper.rebind_actions({&"attack": _key(KEY_H), &"dodge": _key(KEY_H)}) and InputRemapper.serialize_actions() == before)

	for code in [NAN, INF, -INF, -1, 0, 1.25, 1.0e30]:
		_check(results, "malformed key code rejected: " + str(code), InputRemapper.deserialize_event({"kind": "keycode", "code": code}) == null)
	_check(results, "non-string input kind is rejected", InputRemapper.deserialize_event({"kind": 7, "code": 32}) == null)
	_check(results, "non-string action keys are ignored", InputRemapper.deserialize_actions({7: [{"kind": "keycode", "code": 32}]}) == 0)
	_check(results, "corrupt saved bindings leave working action intact", InputRemapper.deserialize_actions({"attack": [{"kind": "keycode", "code": INF}]}) == 0 and InputRemapper.serialize_actions() == before)
	_restore(original)


static func _test_settings_and_save(results: Array) -> void:
	var settings := SettingsData.new()
	for value in [NAN, INF, -INF]:
		settings.set_text_scale(value)
		_check(results, "non-finite text scale has finite default: " + str(value), settings.text_scale == 1.0)
	settings.from_dict({"graphics_quality": [], "muted": "false", "text_scale": NAN, "high_contrast": {"invalid": true}})
	_check(results, "wrong-type settings do not crash or turn flags on", settings.graphics_quality == &"medium" and not settings.muted and not settings.high_contrast and settings.text_scale == 1.0)
	var legacy := {"schema_version": 1, "best_score": 42}
	var normalized := SaveSchema.normalize_save(legacy)
	_check(results, "save migration does not mutate its input", not legacy.has("prestige_rank") and legacy.schema_version == 1 and normalized.best_score == 42)
	normalized = SaveSchema.normalize_save({
		"best_score": INF, "best_wave": NAN, "meta_wallet": -INF,
		"tutorial_completed": "false",
		"meta_ranks": {7: 4, "": 1, "bad": INF, "good": 2},
		"lifetime_statistics": {"total_time_seconds": INF},
	})
	_check(results, "non-finite save counters become defaults", normalized.best_score == 0 and normalized.best_wave == 0 and normalized.meta_wallet == 0 and normalized.lifetime_statistics.total_time_seconds == 0.0)
	_check(results, "only valid rank ids and finite ranks survive", normalized.meta_ranks == {"good": 2} and not normalized.tutorial_completed)
	var old_defaults := {"skill_3": [{"kind": "key_physical", "code": KEY_R}, {"kind": "pad", "code": 6}]}
	normalized = SaveSchema.normalize_save({"schema_version": 6, "settings": {"input_bindings": old_defaults}})
	var migrated: Dictionary = normalized.settings.input_bindings
	_check(results, "old factory remaps migrate away from reload", migrated.skill_3[0].code == KEY_F and migrated.skill_3[1].code == JOY_BUTTON_LEFT_STICK and old_defaults.skill_3[0].code == KEY_R)
	old_defaults.skill_3[0].code = KEY_H
	normalized = SaveSchema.normalize_save({"schema_version": 6, "settings": {"input_bindings": old_defaults}})
	_check(results, "custom bindings survive the default-controls migration", normalized.settings.input_bindings == old_defaults)
	normalized = SaveSchema.normalize_save({"best_score": 1.0e30, "meta_ranks": {"good": 1.0e30}})
	_check(results, "oversized counters cannot overflow signed integers", normalized.best_score == SaveSchema.MAX_SAFE_INTEGER and normalized.meta_ranks.good == SaveSchema.MAX_SAFE_INTEGER)


static func _test_json(results: Array) -> void:
	_check(results, "corrupt JSON recovers without engine errors", JsonHelpers.parse_safe("not json", {"fallback": true}) == {"fallback": true})
	_check(results, "JSON null uses the supplied fallback", JsonHelpers.parse_safe("null", 42) == 42)
	var overrides := {"nested": {"items": [1]}, "items": [2]}
	var merged := JsonHelpers.deep_merge({}, overrides)
	merged.nested.items.append(3)
	merged.items.append(4)
	_check(results, "deep merge does not alias override arrays or dictionaries", overrides.nested.items == [1] and overrides.items == [2])
	_check(results, "non-finite clamped JSON numbers use fallback", JsonHelpers.clamped_number({"n": NAN}, "n", 0.0, 1.0, 0.5) == 0.5 and JsonHelpers.clamped_number({"n": INF}, "n", 0.0, 1.0, 0.5) == 0.5)
