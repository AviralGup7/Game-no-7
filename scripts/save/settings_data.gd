class_name SettingsData
extends RefCounted

## Runtime representation of player settings. Owned/edited by the settings system
## and copied to/from the versioned save dictionary. All setters clamp/validate so
## an external caller cannot inject invalid values.

var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0
var muted: bool = false
var vibration_enabled: bool = true
var graphics_quality: StringName = &"medium"
var reduced_motion: bool = false
var text_scale: float = 1.0
var high_contrast: bool = false
var aim_assist_enabled: bool = true
## Portable InputRemapper snapshot `{action: [{kind, code}, ...]}`. Empty means
## "keep project.godot defaults" — never wipe a working binding on a missing key.
var input_bindings: Dictionary = {}


## Documented safe text-scale range. Kept in one place for validation.
const MIN_TEXT_SCALE: float = 0.8
const MAX_TEXT_SCALE: float = 2.0


func set_master_volume(value: float) -> void:
	master_volume = _clamp01(value)


func set_music_volume(value: float) -> void:
	music_volume = _clamp01(value)


func set_sfx_volume(value: float) -> void:
	sfx_volume = _clamp01(value)


## Accepted quality presets: the four governor tiers (see PerformanceMonitor).
const QUALITY_PRESETS := [&"low", &"medium", &"high", &"ultra"]


func set_graphics_quality(value: StringName) -> void:
	if value in QUALITY_PRESETS:
		graphics_quality = value
	# Invalid values are ignored; the previous safe value is kept.


func set_text_scale(value: float) -> void:
	text_scale = clampf(value, MIN_TEXT_SCALE, MAX_TEXT_SCALE)


func set_muted(value: bool) -> void:
	muted = value


func set_reduced_motion(value: bool) -> void:
	reduced_motion = value


func set_vibration_enabled(value: bool) -> void:
	vibration_enabled = value


func set_high_contrast(value: bool) -> void:
	high_contrast = value


func set_aim_assist_enabled(value: bool) -> void:
	aim_assist_enabled = value


func set_input_bindings(value: Dictionary) -> void:
	input_bindings = value.duplicate(true) if value != null else {}


## Read accessors (UI panels and audio/motion systems read through these).
func get_master_volume() -> float:
	return master_volume


func get_music_volume() -> float:
	return music_volume


func get_sfx_volume() -> float:
	return sfx_volume


func is_muted() -> bool:
	return muted


func get_graphics_quality() -> StringName:
	return graphics_quality


func get_reduced_motion() -> bool:
	return reduced_motion


func get_text_scale() -> float:
	return text_scale


func is_high_contrast() -> bool:
	return high_contrast


func is_vibration_enabled() -> bool:
	return vibration_enabled


func is_aim_assist_enabled() -> bool:
	return aim_assist_enabled


func _clamp01(value: float) -> float:
	if not is_finite(value):
		return 0.0
	return clampf(value, 0.0, 1.0)


## Build a plain Dictionary (save-safe) from current values.
func to_dict() -> Dictionary:
	return {
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"muted": muted,
		"vibration_enabled": vibration_enabled,
		"graphics_quality": String(graphics_quality),
		"reduced_motion": reduced_motion,
		"text_scale": text_scale,
		"high_contrast": high_contrast,
		"aim_assist_enabled": aim_assist_enabled,
		"input_bindings": input_bindings.duplicate(true),
	}


## Populate from a Dictionary (typically the settings key of a save). Invalid or
## missing keys fall back to safe defaults rather than throwing.
func from_dict(data: Dictionary) -> void:
	set_master_volume(_d(data, "master_volume", 1.0, "volume"))
	set_music_volume(_d(data, "music_volume", 1.0, "volume"))
	set_sfx_volume(_d(data, "sfx_volume", 1.0, "volume"))
	muted = bool(_d(data, "muted", false, "bool"))
	vibration_enabled = bool(_d(data, "vibration_enabled", true, "bool"))
	set_graphics_quality(StringName(str(_d(data, "graphics_quality", "medium", "string"))))
	reduced_motion = bool(_d(data, "reduced_motion", false, "bool"))
	set_text_scale(_d(data, "text_scale", 1.0, "float"))
	high_contrast = bool(_d(data, "high_contrast", false, "bool"))
	aim_assist_enabled = bool(_d(data, "aim_assist_enabled", true, "bool"))
	var raw_binds: Variant = data.get("input_bindings", {})
	if raw_binds is Dictionary:
		input_bindings = (raw_binds as Dictionary).duplicate(true)
	else:
		input_bindings = {}


## Read a key with a type-checked fallback. Returns typed_default when missing/wrong.
func _d(data: Dictionary, key: String, typed_default: Variant, type_hint: String) -> Variant:
	if not data.has(key):
		return typed_default
	var raw: Variant = data[key]
	match type_hint:
		"volume":
			if typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT:
				return float(raw)
			return typed_default
		"bool":
			return bool(raw)
		"string":
			return String(raw)
		"float":
			if typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT:
				return float(raw)
			return typed_default
	return typed_default
