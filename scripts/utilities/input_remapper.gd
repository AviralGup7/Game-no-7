class_name InputRemapper
extends RefCounted

## Runtime input remapping on top of Godot's InputMap.
## The game ships with sensible defaults (see project.godot); this helper lets
## the settings UI rebind keyboard/joypad buttons per action, persist the custom
## bindings as portable dictionaries, and restore them on boot. Pure logic plus
## thin InputMap calls; safe to exercise headless (InputMap exists without a tree).

const REMAPPABLE_ACTIONS := [&"attack", &"dodge", &"pause", &"skill_1", &"skill_2", &"skill_3"]
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
		var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
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
	if not InputMap.has_action(action):
		return false
	if not (event is InputEventKey or event is InputEventJoypadButton):
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
		return {"kind": "key", "code": int(k.physical_keycode)}
	if event is InputEventJoypadButton:
		var b := event as InputEventJoypadButton
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
		for entry in binds:
			if not (entry is Dictionary):
				continue
			var event := deserialize_event(entry)
			if event != null:
				InputMap.action_add_event(aname, event)
				applied += 1
	return applied


static func deserialize_event(entry: Dictionary) -> InputEvent:
	var kind := String(entry.get("kind", ""))
	var code := int(entry.get("code", 0))
	match kind:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = code
			return k
		"pad":
			var b := InputEventJoypadButton.new()
			b.button_index = code
			return b
	return null


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
		return (a as InputEventKey).physical_keycode == (b as InputEventKey).physical_keycode
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	return false
