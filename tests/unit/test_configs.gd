extends RefCounted

## Headless unit tests for typed content-resource validation.

static func suite() -> Array:
	var results: Array = []

	# EnemyConfig validation
	var EnemyScript = load("res://scripts/enemies/enemy_config.gd")
	var e := EnemyScript.new()
	e.archetype_id = &"basic"
	e.scene = null  # a real config points to a scene
	results.append({
		"name": "EnemyConfig flags missing scene",
		"passed": not e.validate().is_empty(),
		"why": "",
	})
	e.scene = load("res://scenes/enemies/enemy_base.tscn") if ResourceLoader.exists("res://scenes/enemies/enemy_base.tscn") else null
	results.append({"name": "EnemyConfig id present", "passed": e.archetype_id == &"basic", "why": ""})

	# UpgradeConfig validation
	var UpgradeScript = load("res://scripts/progression/upgrade_config.gd")
	var u := UpgradeScript.new()
	u.upgrade_id = &"vitality"
	u.stat_modifiers = {"max_health_add": 20.0, "bogus_key": 1.0}
	results.append({
		"name": "UpgradeConfig flags unknown modifier key",
		"passed": not u.validate().is_empty(),
		"why": "",
	})
	var u2 := UpgradeScript.new()
	u2.upgrade_id = &"swift"
	u2.stat_modifiers = {"move_speed_multiplier": 0.15}
	results.append({"name": "UpgradeConfig valid passes", "passed": u2.validate().is_empty(), "why": ""})

	# CameraProfile validation
	var CamScript = load("res://scripts/main/camera_profile.gd")
	var c := CamScript.new()
	c.profile_id = &"default"
	results.append({"name": "CameraProfile valid passes", "passed": c.validate().is_empty(), "why": ""})
	c.distance = 0.1
	results.append({"name": "CameraProfile flags bad distance", "passed": not c.validate().is_empty(), "why": ""})

	# WaveConfig planned_count
	var WaveScript = load("res://scripts/waves/wave_config.gd")
	var EntryScript = load("res://scripts/waves/wave_spawn_entry.gd")
	var w := WaveScript.new()
	w.wave_number = 1
	var en := EntryScript.new()
	en.archetype_id = &"basic"
	en.count = 5
	w.spawn_entries = [en]
	results.append({"name": "WaveConfig.planned_count", "passed": w.planned_count() == 5, "why": ""})

	# ArenaConfig validation
	var ArenaScript = load("res://scripts/arena/arena_config.gd")
	var a := ArenaScript.new()
	a.arena_id = &"default_arena"
	a.scene = null
	results.append({"name": "ArenaConfig flags missing scene", "passed": not a.validate().is_empty(), "why": ""})

	return results
