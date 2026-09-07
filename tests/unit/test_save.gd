extends RefCounted

## Headless unit tests for the save schema + settings clamping.
## Runs without autoloads by preloading scripts by path.

static func suite() -> Array:
	var results: Array = []

	# --- normalize_save handles garbage without throwing ---
	var SaveScript = load("res://scripts/save/save_manager.gd")
	var normalized := SaveScript.normalize_save(null)
	results.append({
		"name": "normalize_save(null) returns a valid default",
		"passed": normalized is Dictionary and int(normalized.get("schema_version", 0)) == SaveScript.SCHEMA_VERSION,
		"why": "",
	})

	var wrong = SaveScript.normalize_save("not a dict")
	results.append({
		"name": "normalize_save(non-dict) returns defaults",
		"passed": wrong is Dictionary,
		"why": "",
	})

	# --- valid data is preserved & migrated ---
	var migrated := SaveScript.normalize_save({
		"schema_version": 1,
		"best_score": 42,
		"best_wave": 7,
		"lifetime_statistics": {"total_runs": 3, "total_kills": 100, "total_time_seconds": 55.0, "highest_combo": 5},
		"progression": {"unlocked_arenas": ["arena_b"], "unlocked_upgrades": [], "unlocked_cosmetics": []},
	})
	results.append({
		"name": "migrates schema 1 -> %d" % SaveScript.SCHEMA_VERSION,
		"passed": int(migrated.get("schema_version", 0)) == SaveScript.SCHEMA_VERSION and int(migrated.get("best_score", 0)) == 42,
		"why": "",
	})

	# --- negative/oversized values are sanitized ---
	var sanitized := SaveScript.normalize_save({"schema_version": 2, "best_score": -5, "best_wave": -1})
	results.append({
		"name": "negative best score/wave are clamped to 0",
		"passed": int(sanitized.get("best_score", 0)) == 0 and int(sanitized.get("best_wave", 0)) == 0,
		"why": "",
	})

	# --- default arena is always present in unlocked arenas ---
	results.append({
		"name": "default_arena always in unlocked_arenas",
		"passed": "default_arena" in migrated.get("progression", {}).get("unlocked_arenas", []),
		"why": "",
	})

	# --- settings clamp ---
	var SettingsScript = load("res://scripts/save/settings_data.gd")
	var sd = SettingsScript.new()
	sd.set_master_volume(2.5)
	sd.set_master_volume(-1.0)
	sd.set_sfx_volume(0.4)
	results.append({
		"name": "volume clamped into [0,1]",
		"passed": sd.master_volume == 0.0 and is_equal_approx(sd.sfx_volume, 0.4),
		"why": "",
	})
	sd.set_text_scale(99.0)
	sd.set_text_scale(0.1)
	results.append({
		"name": "text_scale clamped to safe range",
		"passed": sd.text_scale <= SettingsScript.MAX_TEXT_SCALE and sd.text_scale >= SettingsScript.MIN_TEXT_SCALE,
		"why": "",
	})
	sd.set_graphics_quality(&"ultra")
	results.append({
		"name": "invalid graphics quality ignored",
		"passed": sd.graphics_quality == &"medium",
		"why": "",
	})
	return results
