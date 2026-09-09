class_name SaveSchema
extends RefCounted

## Pure save-schema owner: default document, validator/migrator, and typed readers.
## Extracted from SaveManager so the schema is unit-testable without the autoload.
## It never touches disk, timers, or other autoloads; SaveManager keeps the live
## store + debounced flush and delegates all schema work here.

const SCHEMA_VERSION := 5
const BUILD_SCHEMA_VERSION := 1


static func default_save() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"best_score": 0,
		"best_wave": 0,
		"tutorial_completed": false,
		"achievements": [],
		"meta_wallet": 0,
		"meta_ranks": {},
		"prestige_rank": 0,
		"lifetime_statistics": {
			"total_runs": 0,
			"total_kills": 0,
			"total_time_seconds": 0.0,
			"highest_combo": 0,
			"victories": 0,
			"bosses_slain": 0,
		},
		"settings": SettingsData.new().to_dict(),
		"progression": {
			"unlocked_upgrades": [],
			"unlocked_arenas": ["default_arena"],
			"unlocked_cosmetics": [],
		},
		# A summary-only build record. It is not used as live runtime authority;
		# ProgressionComponent/WeaponManager/SkillController are restored by run
		# orchestration when a future resume feature asks for it.
		"last_run_build": default_run_build(),
	}


static func default_run_build() -> Dictionary:
	return {
		"schema_version": BUILD_SCHEMA_VERSION,
		"seed": 0,
		"current_wave": 0,
		"selected_upgrades": {},
		"active_modifiers": [],
		"equipped_weapons": [],
		"equipped_skills": [],
		"build_archetypes": [],
	}


## Pure, headless-testable validator/migrator. Accepts any Variant (raw JSON, null,
## dict with wrong shape) and returns a fully-valid, normalized save Dictionary.
static func normalize_save(raw_data: Variant) -> Dictionary:
	var out := default_save()
	if raw_data == null or not raw_data is Dictionary:
		return out
	var data: Dictionary = raw_data
	var version := _int_or(_dict_get(data, "schema_version", SCHEMA_VERSION), SCHEMA_VERSION)
	if version > SCHEMA_VERSION:
		# Newer schema: keep what we understand, discard the rest rather than crash.
		pass
	if version < SCHEMA_VERSION:
		data = _migrate_static(data, version)
	out.schema_version = SCHEMA_VERSION
	out.best_score = maxi(0, _int_or(_dict_get(data, "best_score", 0), 0))
	out.best_wave = maxi(0, _int_or(_dict_get(data, "best_wave", 0), 0))
	out.tutorial_completed = bool(_dict_get(data, "tutorial_completed", false))
	out.achievements = _string_list(_dict_get(data, "achievements", []))
	out.meta_wallet = maxi(0, _int_or(_dict_get(data, "meta_wallet", 0), 0))
	out.meta_ranks = _string_int_map(_dict_get(data, "meta_ranks", {}))
	out.prestige_rank = Prestige.clamp_rank(_int_or(_dict_get(data, "prestige_rank", 0), 0))
	if data.has("lifetime_statistics") and data.lifetime_statistics is Dictionary:
		var src: Dictionary = data.lifetime_statistics
		var ls: Dictionary = out.lifetime_statistics
		ls.total_runs = maxi(0, _int_or(_dict_get(src, "total_runs", 0), 0))
		ls.total_kills = maxi(0, _int_or(_dict_get(src, "total_kills", 0), 0))
		ls.total_time_seconds = maxf(0.0, _float_or(_dict_get(src, "total_time_seconds", 0.0), 0.0))
		ls.highest_combo = maxi(0, _int_or(_dict_get(src, "highest_combo", 0), 0))
		ls.victories = maxi(0, _int_or(_dict_get(src, "victories", 0), 0))
		ls.bosses_slain = maxi(0, _int_or(_dict_get(src, "bosses_slain", 0), 0))
		out.lifetime_statistics = ls
	if data.has("settings") and data.settings is Dictionary:
		var sd := SettingsData.new()
		sd.from_dict(data.settings)
		out.settings = sd.to_dict()
	if data.has("progression") and data.progression is Dictionary:
		var prog: Dictionary = data.progression
		var unlocked := _string_list(_dict_get(prog, "unlocked_upgrades", []))
		var arenas := _string_list(_dict_get(prog, "unlocked_arenas", ["default_arena"]))
		if "default_arena" not in arenas:
			arenas.append("default_arena")
		var cosmetics := _string_list(_dict_get(prog, "unlocked_cosmetics", []))
		out.progression = {
			"unlocked_upgrades": unlocked,
			"unlocked_arenas": arenas,
			"unlocked_cosmetics": cosmetics,
		}
	out.last_run_build = _normalize_run_build(_dict_get(data, "last_run_build", {}))
	return out


static func _normalize_run_build(value: Variant) -> Dictionary:
	var out := default_run_build()
	if not value is Dictionary:
		return out
	var data: Dictionary = value
	out.schema_version = BUILD_SCHEMA_VERSION
	out.seed = maxi(_int_or(_dict_get(data, "seed", 0), 0), 0)
	out.current_wave = maxi(_int_or(_dict_get(data, "current_wave", 0), 0), 0)
	out.selected_upgrades = _string_int_map(_dict_get(data, "selected_upgrades", {}))
	out.active_modifiers = _string_list(_dict_get(data, "active_modifiers", []))
	out.equipped_weapons = _string_list(_dict_get(data, "equipped_weapons", []))
	out.equipped_skills = _string_list(_dict_get(data, "equipped_skills", []))
	out.build_archetypes = _string_list(_dict_get(data, "build_archetypes", []))
	return out


static func _migrate_static(data: Dictionary, from_version: int) -> Dictionary:
	if from_version <= 3:
		# v1-v3 did not carry last_run_build. New fields intentionally default
		# rather than attempting to infer a build from lifetime statistics.
		pass
	if from_version <= 4:
		# v5 adds prestige_rank + extended lifetime counters.
		if not data.has("prestige_rank"):
			data["prestige_rank"] = 0
	return data


static func _dict_get(data: Dictionary, key: String, fallback: Variant) -> Variant:
	return data.get(key, fallback)


static func _int_or(value: Variant, fallback: int) -> int:
	if value is float or value is int:
		return int(value)
	return fallback


static func _float_or(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		return float(value)
	return fallback


static func _string_list(value: Variant) -> Array:
	var out: Array = []
	if value is Array:
		for item in value:
			# Only genuine text ids survive. String(4) yields "4", which would
			# smuggle a corrupt numeric entry into a list of content ids and let
			# a malformed save resolve to a nonexistent weapon/skill later.
			if not (item is String or item is StringName):
				continue
			var id := String(item)
			if not id.is_empty() and id not in out:
				out.append(id)
	return out


static func _string_int_map(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if value is Dictionary:
		for key in value:
			var v: Variant = value[key]
			if v is float or v is int:
				out[String(key)] = maxi(int(round(float(v))), 0)
	return out
