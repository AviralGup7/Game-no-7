class_name JsonHelpers
extends RefCounted

## Small, total (never-throwing) JSON + file helpers used by save, analytics
## export, daily-challenge and debug tooling. All functions are static and pure.

const MAX_FILE_BYTES := 1_000_000


## Parse JSON text; returns `fallback` on any error (never throws, never null
## unless the fallback itself is null).
static func parse_safe(text: String, fallback: Variant = {}) -> Variant:
	if text.is_empty():
		return fallback
	# JSON.parse_string prints an engine ERROR for expected corrupt input. The
	# instance API returns an error code instead, keeping recovery non-fatal.
	var parser := JSON.new()
	if parser.parse(text) != OK or parser.data == null:
		return fallback
	return parser.data


## Stringify a value; returns "{}" when the value is not JSON-serializable.
static func stringify_safe(value: Variant, pretty: bool = false) -> String:
	var indent := "  " if pretty else ""
	var text := JSON.stringify(value, indent)
	if text.is_empty():
		return "{}"
	return text


## Read a whole text file; returns "" when missing/unreadable/oversized.
static func read_text_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var length := int(file.get_length())
	if length > MAX_FILE_BYTES:
		file.close()
		return ""
	var text := file.get_as_text()
	file.close()
	return text


## Direct text write for non-critical exports/logs (NOT an atomic save). Critical
## profile persistence uses SaveManager's temp + rename path. Check buffered I/O
## errors before closing so full/read-only storage never reports false success.
static func write_text_file(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK


## Load a JSON dictionary from disk; returns {} on any failure.
static func load_dict(path: String) -> Dictionary:
	var text := read_text_file(path)
	if text.is_empty():
		return {}
	var parsed: Variant = parse_safe(text, {})
	return parsed if parsed is Dictionary else {}


## Save a JSON-serializable value to disk. Returns success.
static func save_value(path: String, value: Variant, pretty: bool = false) -> bool:
	return write_text_file(path, stringify_safe(value, pretty))


## Deep-merge `overrides` into `base` (nested dictionaries merge recursively,
## anything else overwrites). Returns a NEW dictionary; inputs are untouched.
static func deep_merge(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	var copied := overrides.duplicate(true)
	for key in copied:
		var ov: Variant = copied[key]
		if out.has(key) and out[key] is Dictionary and ov is Dictionary:
			out[key] = deep_merge(out[key], ov)
		else:
			out[key] = ov
	return out


## Clamp a numeric entry of a dictionary into [low, high]; missing/non-numeric
## entries become `fallback`.
static func clamped_number(data: Dictionary, key: String, low: float, high: float, fallback: float) -> float:
	if not data.has(key):
		return fallback
	var v: Variant = data[key]
	if (v is float or v is int) and is_finite(float(v)):
		return clampf(float(v), low, high)
	return fallback
