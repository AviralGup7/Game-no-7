class_name InputRemapper
extends RefCounted

## Runtime input remapping on top of Godot's InputMap.
## The game ships with sensible defaults (see project.godot); this helper lets
## the settings UI rebind keyboard/joypad buttons per action, persist the custom
## bindings as portable dictionaries, and restore them on boot. Pure logic plus
## thin InputMap calls; safe to exercise headless (InputMap exists without a tree).

const REMAPPABLE_ACTIONS := [&"attack", &"reload", &"dodge", &"pause", &"switch_weapon", &"skill_1", &"skill_2", &"skill_3"]
# The limit applies to editable key/pad bindings, not preserved mouse/axis events.
const MAX_BINDS_PER_ACTION := 3
const RESERVED_ACTIONS := [&"move_left", &"move_right", &"move_up", &"move_down",
	&"camera_look_left", &"camera_look_right", &"camera_look_up", &"camera_look_down",
	&"camera_reset", &"lock_on"]
const MAX_KEY_CODE := 0x7FFFFFFF

## Project.godot defaults captured once before any saved remap is applied, so
## Restore Defaults can put InputMap back without re-parsing the project file.
static var _factory_bindings: Dictionary = {}


## Capture the current InputMap as factory defaults. Idempotent: the first call
## wins so a later save-restore cannot overwrite the snapshot with custom binds.
static func snapshot_factory() -> void:
	if not _factory_bindings.is_empty():
		return
	_factory_bindings = serialize_actions()


## Re-apply the snapshot taken by snapshot_factory(). No-op until a snapshot exists.
static func restore_factory() -> void:
	if _factory_bindings.is_empty():
		return
	deserialize_actions(_factory_bindings)


## All current InputEvent bindings for an action (possibly empty).
static func get_bindings(action: StringName) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not InputMap.has_action(action):
		return out
	for e in InputMap.action_get_events(action):
		out.append(e)
	return out


## Human-readable label for one binding ("Space", "Pad A", ...).
static func binding_label(event: InputEvent) -> String:
	if event == null:
		return "Unbound"
	if event is InputEventKey:
		var k := event as InputEventKey
		var code := k.keycode
		if code == 0 and k.physical_keycode != 0:
			# Physical codes are layout-independent; convert to the user's current
			# layout for display instead of showing a misleading QWERTY label.
			code = _logical_key(k)
		if code == 0:
			code = k.physical_keycode
		var label := OS.get_keycode_string(code)
		return label if not label.is_empty() else "Key %d" % code
	if event is InputEventJoypadButton:
		var b := event as InputEventJoypadButton
		return "Pad %s" % _joy_button_name(b.button_index)
	if event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		return "Mouse %d" % m.button_index
	return event.as_text()


static func _joy_button_name(index: int) -> String:
	match index:
		JOY_BUTTON_A:
			return "A"
		JOY_BUTTON_B:
			return "B"
		JOY_BUTTON_X:
			return "X"
		JOY_BUTTON_Y:
			return "Y"
		JOY_BUTTON_LEFT_SHOULDER:
			return "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "RB"
		JOY_BUTTON_START:
			return "Start"
		JOY_BUTTON_BACK:
			return "Back"
		JOY_BUTTON_LEFT_STICK:
			return "LS"
		JOY_BUTTON_RIGHT_STICK:
			return "RS"
		_:
			return "Btn%d" % index


## Replace the first binding of the SAME device type, preserving its position and
## all other devices. Failure is atomic (even when the action is already full).
static func rebind_first(action: StringName, event: InputEvent) -> bool:
	var replacement := _replacement_bindings(action, event)
	if replacement.is_empty():
		return false
	_replace_events(action, replacement)
	return true


## Settings stages several edits at once. Validate the whole final map before
## touching InputMap so a rejected later edit cannot partially apply earlier ones.
static func rebind_actions(edits: Dictionary) -> bool:
	var replacements: Dictionary = {}
	for action in edits:
		if not (action is String or action is StringName) or not edits[action] is InputEvent:
			return false
		var aname := StringName(action)
		var event := edits[action] as InputEvent
		var replacement := _replacement_bindings(aname, event)
		if replacement.is_empty() or find_conflict(event, aname, edits) != &"":
			return false
		replacements[aname] = replacement
	for action in replacements:
		_replace_events(action, replacements[action])
	return true


static func _replacement_bindings(action: StringName, event: InputEvent) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if action not in REMAPPABLE_ACTIONS or not InputMap.has_action(action) or not _event_is_valid(event):
		return out
	var replaced := false
	for existing in InputMap.action_get_events(action):
		var same_device := (existing is InputEventKey and event is InputEventKey) or (existing is InputEventJoypadButton and event is InputEventJoypadButton)
		if same_device and not replaced:
			out.append(event.duplicate() as InputEvent)
			replaced = true
		elif not _events_match(existing, event):
			out.append(existing)
	if not replaced:
		out.append(event.duplicate() as InputEvent)
	var editable := 0
	for binding in out:
		if binding is InputEventKey or binding is InputEventJoypadButton:
			editable += 1
	if editable > MAX_BINDS_PER_ACTION:
		out.clear()
	return out


static func _replace_events(action: StringName, events: Array[InputEvent]) -> void:
	InputMap.action_erase_events(action)
	for event in events:
		InputMap.action_add_event(action, event)


## Serialize custom bindings for save data: {action: [{kind, code}, ...]}.
static func serialize_actions(actions: Array = REMAPPABLE_ACTIONS) -> Dictionary:
	var out: Dictionary = {}
	for action in actions:
		if not (action is String or action is StringName):
			continue
		var aname := StringName(action)
		if not InputMap.has_action(aname):
			continue
		var binds: Array = []
		for e in InputMap.action_get_events(aname):
			var entry := serialize_event(e)
			if not entry.is_empty():
				binds.append(entry)
		out[String(action)] = binds
	return out


static func serialize_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var k := event as InputEventKey
		# InputEventKey requires exactly one meaningful key identity. Preserve
		# physical bindings when present, but do not serialize an unusable zero;
		# some platform-generated events only provide keycode.
		if k.physical_keycode != 0:
			return {"kind": "key_physical", "code": int(k.physical_keycode)}
		if k.keycode != 0:
			return {"kind": "keycode", "code": int(k.keycode)}
		return {}
	if event is InputEventJoypadButton:
		var b := event as InputEventJoypadButton
		if b.button_index < 0 or b.button_index > 255:
			return {}
		return {"kind": "pad", "code": int(b.button_index)}
	return {}


## Restore bindings serialized with serialize_actions(). Unknown actions and
## malformed entries are skipped; returns the number of bindings applied.
static func deserialize_actions(data: Dictionary) -> int:
	var applied := 0
	for action_key in data:
		if not (action_key is String or action_key is StringName):
			continue
		var aname := StringName(action_key)
		if aname not in REMAPPABLE_ACTIONS or not InputMap.has_action(aname):
			continue
		var binds: Variant = data[action_key]
		if not (binds is Array):
			continue
		# Parse first, then mutate InputMap. A corrupt array must never erase the
		# working defaults and leave the player with an unusable action.
		var parsed: Array[InputEvent] = []
		for entry in binds:
			if not (entry is Dictionary):
				continue
			var parsed_event := deserialize_event(entry)
			if parsed_event != null and not _event_in(parsed, parsed_event):
				parsed.append(parsed_event)
			if parsed.size() >= MAX_BINDS_PER_ACTION:
				break
		if parsed.is_empty():
			continue
		# Clear only after at least one valid binding has been prepared.
		for existing in InputMap.action_get_events(aname).duplicate():
			if existing is InputEventKey or existing is InputEventJoypadButton:
				InputMap.action_erase_event(aname, existing)
		for event in parsed:
			InputMap.action_add_event(aname, event)
			applied += 1
	return applied


static func deserialize_event(entry: Dictionary) -> InputEvent:
	var raw_kind: Variant = entry.get("kind", "")
	if not (raw_kind is String or raw_kind is StringName):
		return null
	var kind := String(raw_kind)
	var raw_code: Variant = entry.get("code", -1)
	if not (raw_code is int or raw_code is float):
		return null
	if not is_finite(float(raw_code)) or raw_code < 0 or raw_code > MAX_KEY_CODE:
		return null
	if float(raw_code) != floorf(float(raw_code)):
		return null
	var code := int(raw_code)
	if kind == "pad" and code > 255:
		return null
	match kind:
		# "key" is retained as the v1 physical-key format for save compatibility.
		"key", "key_physical":
			if code == 0:
				return null
			var k := InputEventKey.new()
			k.physical_keycode = code as Key
			return k
		"keycode":
			if code == 0:
				return null
			var logical := InputEventKey.new()
			logical.keycode = code as Key
			return logical
		"pad":
			var b := InputEventJoypadButton.new()
			b.button_index = code as JoyButton
			return b
	return null


static func _event_is_valid(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return (key.physical_keycode > 0 and key.physical_keycode <= MAX_KEY_CODE) or (key.keycode > 0 and key.keycode <= MAX_KEY_CODE)
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		return button.button_index >= 0 and button.button_index <= 255
	return false


static func _event_in(events: Array[InputEvent], candidate: InputEvent) -> bool:
	for event in events:
		if _events_match(event, candidate):
			return true
	return false


## Check the effective STAGED map, including fixed movement/camera controls.
## Built-in ui_* actions are deliberately excluded: Escape/pause and Enter/fire
## share menu bindings, but menus and gameplay never own input simultaneously.
static func find_conflict(event: InputEvent, except_action: StringName, edits: Dictionary = {}) -> StringName:
	for action in REMAPPABLE_ACTIONS + RESERVED_ACTIONS:
		var aname := StringName(action)
		if aname == except_action or not InputMap.has_action(aname):
			continue
		var bindings := InputMap.action_get_events(aname)
		if edits.has(aname) and edits[aname] is InputEvent:
			var replacement := _replacement_bindings(aname, edits[aname])
			if not replacement.is_empty():
				bindings = replacement
		for binding in bindings:
			if _events_match(binding, event):
				return aname
	return &""


static func _events_match(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ak := a as InputEventKey
		var bk := b as InputEventKey
		if ak.physical_keycode != 0 and bk.physical_keycode != 0:
			return ak.physical_keycode == bk.physical_keycode
		return _logical_key(ak) != 0 and _logical_key(ak) == _logical_key(bk)
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	return false


static func _logical_key(event: InputEventKey) -> int:
	if event.physical_keycode == 0:
		return event.keycode
	# The headless display server cannot query a keyboard layout and emits an
	# engine error rather than merely returning zero. Physical QWERTY is the
	# deterministic fallback for headless tools/tests.
	if DisplayServer.get_name() == "headless":
		return event.physical_keycode
	var mapped := DisplayServer.keyboard_get_keycode_from_physical(event.physical_keycode)
	return mapped if mapped != 0 else event.physical_keycode
