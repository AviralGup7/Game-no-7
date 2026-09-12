class_name SaveSchema
extends RefCounted

## Pure save-schema owner: default document, validator/migrator, and typed readers.
## Extracted from SaveManager so the schema is unit-testable without the autoload.
## It never touches disk, timers, or other autoloads; SaveManager keeps the live
## store + debounced flush and delegates all schema work here.

const SCHEMA_VERSION := 8
const BUILD_SCHEMA_VERSION := 1
# JSON numbers round-trip through doubles. Larger integers lose identity on disk.
const MAX_SAFE_INTEGER := 9007199254740991


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
		"campaign": CampaignProgress.defaults(),
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
		data = _migrate_static(data.duplicate(true), version)
	out.schema_version = SCHEMA_VERSION
	out.best_score = maxi(0, _int_or(_dict_get(data, "best_score", 0), 0))
	out.best_wave = maxi(0, _int_or(_dict_get(data, "best_wave", 0), 0))
	var tutorial: Variant = _dict_get(data, "tutorial_completed", false)
	out.tutorial_completed = tutorial if tutorial is bool else false
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
	out.campaign = CampaignProgress.normalize(data.get("campaign", {}))
	return out


static func _normalize_run_build(value: Variant) -> Dictionary:
	var out := default_run_build()
	if not value is Dictionary:
		return out
	var data: Dictionary = value
	out.schema_version = BUILD_SCHEMA_VERSION
	# Public contract key is `seed` (RunState.build_snapshot / last_run_build).
	# Older or mistaken writers used `run_seed`; accept either, write only `seed`.
	var seed_raw: Variant = _dict_get(data, "seed", _dict_get(data, "run_seed", 0))
	out.seed = _seed_or(seed_raw)
	out.erase("run_seed")
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
	if from_version <= 6:
		_migrate_input_defaults(data)
	return data


## v7 repairs the shipped R/reload conflict and the Godot 3-style pad indices.
## Only EXACT old factory pairs move: genuinely customized bindings are kept.
static func _migrate_input_defaults(data: Dictionary) -> void:
	var settings: Variant = data.get("settings", {})
	if not settings is Dictionary:
		return
	var bindings: Variant = settings.get("input_bindings", {})
	if not bindings is Dictionary:
		return
	var changes := {
		"pause": [KEY_ESCAPE, 9, KEY_ESCAPE, JOY_BUTTON_START],
		"skill_1": [KEY_Q, 4, KEY_Q, JOY_BUTTON_LEFT_SHOULDER],
		"skill_2": [KEY_E, 5, KEY_E, JOY_BUTTON_RIGHT_SHOULDER],
		"skill_3": [KEY_R, 6, KEY_F, JOY_BUTTON_LEFT_STICK],
	}
	for action in changes:
		var change: Array = changes[action]
		var old := [{"kind": "key_physical", "code": change[0]}, {"kind": "pad", "code": change[1]}]
		if bindings.get(action) == old:
			bindings[action] = [{"kind": "key_physical", "code": change[2]}, {"kind": "pad", "code": change[3]}]


static func _dict_get(data: Dictionary, key: String, fallback: Variant) -> Variant:
	return data.get(key, fallback)


static func _int_or(value: Variant, fallback: int) -> int:
	if value is int:
		return clampi(value, -MAX_SAFE_INTEGER, MAX_SAFE_INTEGER)
	if value is float and is_finite(value):
		return int(clampf(value, -MAX_SAFE_INTEGER, MAX_SAFE_INTEGER))
	return fallback


## Seeds use the full nonnegative int64 range in memory. New saves encode them
## as decimal strings, because JSON numbers cannot preserve daily seeds > 2^53.
static func _seed_or(value: Variant) -> int:
	if value is int:
		return maxi(value, 0)
	if value is String and value.is_valid_int():
		var digits: String = value.strip_edges().trim_prefix("+")
		if digits.is_empty() or digits.begins_with("-"):
			return 0
		if digits.length() < 19 or (digits.length() == 19 and digits <= "9223372036854775807"):
			return digits.to_int()
	# Legacy numeric JSON seeds are supported within the exact-integer range.
	return maxi(_int_or(value, 0), 0)


static func _float_or(value: Variant, fallback: float) -> float:
	if (value is float or value is int) and is_finite(float(value)):
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
			if not (key is String or key is StringName) or String(key).is_empty():
				continue
			var v: Variant = value[key]
			if (v is float or v is int) and is_finite(float(v)):
				out[String(key)] = maxi(_int_or(roundf(float(v)), 0), 0)
	return out
