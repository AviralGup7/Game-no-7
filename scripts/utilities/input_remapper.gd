class_name InputRemapper
extends RefCounted

## Runtime input remapping on top of Godot's InputMap.
## The game ships with sensible defaults (see project.godot); this helper lets
## the settings UI rebind keyboard/joypad buttons per action, persist the custom
## bindings as portable dictionaries, and restore them on boot. Pure logic plus
## thin InputMap calls; safe to exercise headless (InputMap exists without a tree).

const REMAPPABLE_ACTIONS := [&"attack", &"dodge", &"pause", &"switch_weapon", &"skill_1", &"skill_2", &"skill_3"]
const MAX_BINDS_PER_ACTION := 3


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
	if event is InputEventKey:
		var k := event as InputEventKey
		var code := k.keycode
		if code == 0 and k.physical_keycode != 0:
			# Physical codes are layout-independent; convert to the user's current
			# layout for display instead of showing a misleading QWERTY label.
			code = DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)
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
		0:
			return "A"
		1:
			return "B"
		2:
			return "X"
		3:
			return "Y"
		4:
			return "LB"
		5:
			return "RB"
		9:
			return "Start"
		_:
			return "Btn%d" % index


## Replace the FIRST keyboard/joypad binding of an action with `event`.
## Returns false when the action is unknown or the event type is unsupported.
static func rebind_first(action: StringName, event: InputEvent) -> bool:
	if action not in REMAPPABLE_ACTIONS:
		return false
	if not InputMap.has_action(action) or not _event_is_valid(event):
		return false
	var existing := InputMap.action_get_events(action)
	for e in existing:
		if (e is InputEventKey and event is InputEventKey) or (e is InputEventJoypadButton and event is InputEventJoypadButton):
			InputMap.action_erase_event(action, e)
			break
	if InputMap.action_get_events(action).size() >= MAX_BINDS_PER_ACTION:
		return false
	InputMap.action_add_event(action, event)
	return true


## Serialize custom bindings for save data: {action: [{kind, code}, ...]}.
static func serialize_actions(actions: Array = REMAPPABLE_ACTIONS) -> Dictionary:
	var out: Dictionary = {}
	for action in actions:
		var aname := StringName(String(action))
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
		var aname := StringName(String(action_key))
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
			var event := deserialize_event(entry)
			if event != null and not _event_in(parsed, event):
				parsed.append(event)
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
	var kind := String(entry.get("kind", ""))
	var raw_code: Variant = entry.get("code", -1)
	if not (raw_code is int or raw_code is float):
		return null
	var code := int(raw_code)
	if code < 0:
		return null
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
		return key.physical_keycode != 0 or key.keycode != 0
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		return button.button_index >= 0 and button.button_index <= 255
	return false


static func _event_in(events: Array[InputEvent], candidate: InputEvent) -> bool:
	for event in events:
		if _events_match(event, candidate):
			return true
	return false


## True when `event` is already bound to a DIFFERENT remappable action (used to
## warn about conflicts in the settings UI).
static func find_conflict(event: InputEvent, except_action: StringName) -> StringName:
	for action in REMAPPABLE_ACTIONS:
		var aname := StringName(String(action))
		if aname == except_action or not InputMap.has_action(aname):
			continue
		for e in InputMap.action_get_events(aname):
			if _events_match(e, event):
				return aname
	return &""


static func _events_match(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ak := a as InputEventKey
		var bk := b as InputEventKey
		if ak.physical_keycode != 0 and bk.physical_keycode != 0:
			return ak.physical_keycode == bk.physical_keycode
		return ak.keycode != 0 and ak.keycode == bk.keycode
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	return false
