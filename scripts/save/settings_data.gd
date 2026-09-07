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


## Documented safe text-scale range. Kept in one place for validation.
const MIN_TEXT_SCALE: float = 0.8
const MAX_TEXT_SCALE: float = 2.0


func set_master_volume(value: float) -> void:
	master_volume = _clamp01(value)


func set_music_volume(value: float) -> void:
	music_volume = _clamp01(value)


func set_sfx_volume(value: float) -> void:
	sfx_volume = _clamp01(value)


func set_graphics_quality(value: StringName) -> void:
	if value == &"low" or value == &"medium" or value == &"high":
		graphics_quality = value
	# Invalid values are ignored; the previous safe value is kept.


func set_text_scale(value: float) -> void:
	text_scale = clampf(value, MIN_TEXT_SCALE, MAX_TEXT_SCALE)


func _clamp01(value: float) -> float:
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
