extends RefCounted

## Headless unit tests for the save schema + settings clamping.
## The save script has no class_name (it is an autoload), so it is loaded by path and
## its static helpers are called through the loaded script (results are read as
## Variant; no `:=` inference is used on them).

static func suite() -> Array:
	var results: Array = []
	var SaveScript = load("res://scripts/save/save_manager.gd")

	var normalized = SaveScript.normalize_save(null)
	results.append({
		"name": "normalize_save(null) returns a valid default",
		"passed": normalized is Dictionary and int(normalized.get("schema_version", 0)) == int(SaveScript.SCHEMA_VERSION),
		"why": "",
	})

	var wrong = SaveScript.normalize_save("not a dict")
	results.append({
		"name": "normalize_save(non-dict) returns defaults",
		"passed": wrong is Dictionary,
		"why": "",
	})

	# --- valid data is preserved & migrated ---
	var migrated = SaveScript.normalize_save({
		"schema_version": 1,
		"best_score": 42,
		"best_wave": 7,
		"lifetime_statistics": {"total_runs": 3, "total_kills": 100, "total_time_seconds": 55.0, "highest_combo": 5},
		"progression": {"unlocked_arenas": ["arena_b"], "unlocked_upgrades": [], "unlocked_cosmetics": []},
	})
	results.append({
		"name": "migrates schema 1 -> current",
		"passed": int(migrated.get("schema_version", 0)) == int(SaveScript.SCHEMA_VERSION) and int(migrated.get("best_score", 0)) == 42,
		"why": "",
	})

	# --- negative/oversized values are sanitized ---
	var sanitized = SaveScript.normalize_save({"schema_version": 2, "best_score": -5, "best_wave": -1})
	results.append({
		"name": "negative best score/wave are clamped to 0",
		"passed": int(sanitized.get("best_score", 0)) == 0 and int(sanitized.get("best_wave", 0)) == 0,
		"why": "",
	})

	# --- default arena is always present in unlocked arenas ---
	var prog: Dictionary = migrated.get("progression", {})
	var arenas: Array = prog.get("unlocked_arenas", [])
	results.append({
		"name": "default_arena always in unlocked_arenas",
		"passed": "default_arena" in arenas,
		"why": "",
	})

	# --- settings clamp ---
	var sd := SettingsData.new()
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
		"passed": sd.text_scale <= SettingsData.MAX_TEXT_SCALE and sd.text_scale >= SettingsData.MIN_TEXT_SCALE,
		"why": "",
	})
	# Ultra is a valid preset (the governor rebuild made it round-trippable),
	# so it must be accepted, not dropped like a typo.
	sd.set_graphics_quality(&"ultra")
	results.append({
		"name": "ultra graphics quality accepted",
		"passed": sd.graphics_quality == &"ultra",
		"why": "",
	})
	sd.set_graphics_quality(&"not_a_quality")
	results.append({
		"name": "invalid graphics quality ignored",
		"passed": sd.graphics_quality == &"ultra",
		"why": "",
	})
	var binds := {"attack": [{"kind": "keycode", "code": 32}]}
	sd.set_input_bindings(binds)
	var round := SettingsData.new()
	round.from_dict(sd.to_dict())
	results.append({
		"name": "input_bindings round-trip through settings dict",
		"passed": round.input_bindings.has("attack")
			and (round.input_bindings["attack"] as Array).size() == 1,
		"why": str(round.input_bindings),
	})
	var migrated_binds := SaveScript.normalize_save({
		"schema_version": 5,
		"settings": {"master_volume": 0.4, "input_bindings": binds},
	})
	var settings_out: Dictionary = migrated_binds.get("settings", {})
	results.append({
		"name": "schema 5 settings keep remaps on migrate to current",
		"passed": int(migrated_binds.get("schema_version", 0)) == int(SaveScript.SCHEMA_VERSION)
			and (settings_out.get("input_bindings", {}) as Dictionary).has("attack"),
		"why": str(settings_out.get("input_bindings", {})),
	})
	return results
