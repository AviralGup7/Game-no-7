extends RefCounted

## Content/progression contract tests for Agent 3's data library. These tests load
## resources directly so they stay independent of autoload startup order while still
## exercising the same Resource validation used by ContentRegistry.

static func _ids(dir_path: String, property_name: String) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		var clean := file.trim_suffix(".remap")
		if not dir.current_is_dir() and clean.ends_with(".tres"):
			var resource: Resource = load(dir_path.path_join(clean))
			if resource != null:
				out[String(resource.get(property_name))] = resource
		file = dir.get_next()
	dir.list_dir_end()
	return out


static func _contains_all(values: Array, expected: Array) -> bool:
	for item in expected:
		if item not in values:
			return false
	return true


static func suite() -> Array:
	var results: Array = []
	var weapons := _ids("res://data/weapons", "weapon_id")
	var skills := _ids("res://data/skills", "skill_id")
	var statuses := _ids("res://data/status", "effect_id")
	var upgrades := _ids("res://data/upgrades", "upgrade_id")

	var all_valid := true
	for cfg in weapons.values():
		if not (cfg is WeaponConfig) or not (cfg as WeaponConfig).validate().is_empty():
			all_valid = false
	for cfg in skills.values():
		if not (cfg is SkillConfig) or not (cfg as SkillConfig).validate().is_empty():
			all_valid = false
	for cfg in statuses.values():
		if not (cfg is StatusEffectConfig) or not (cfg as StatusEffectConfig).validate().is_empty():
			all_valid = false
	for cfg in upgrades.values():
		if not (cfg is UpgradeConfig) or not (cfg as UpgradeConfig).validate().is_empty():
			all_valid = false
	results.append({
		"name": "every weapon skill status and upgrade resource validates",
		"passed": all_valid,
		"why": "weapons=%d skills=%d statuses=%d upgrades=%d" % [weapons.size(), skills.size(), statuses.size(), upgrades.size()],
	})

	results.append({
		"name": "expanded content ids are present",
		"passed": weapons.size() >= 9 and skills.size() >= 8 and statuses.size() >= 13 and upgrades.size() >= 30
			and _contains_all(weapons.keys(), [&"ember_scepter", &"moonlance", &"venom_chain"])
			and _contains_all(skills.keys(), [&"chain_lightning", &"mending_light", &"shatterwave"])
			and _contains_all(statuses.keys(), [&"poison", &"exposed", &"overguard"]),
		"why": "",
	})

	# Every weapon's proc ids, every skill's effect ids, and every upgrade graph edge
	# must resolve through content ids rather than hidden code constants.
	var references_ok := true
	for cfg in weapons.values():
		var wc := cfg as WeaponConfig
		for id in wc.on_hit_effects:
			if not statuses.has(id):
				references_ok = false
	for cfg in skills.values():
		var sc := cfg as SkillConfig
		for id in sc.victim_effects + sc.caster_effects:
			if not statuses.has(id):
				references_ok = false
	for cfg in upgrades.values():
		var uc := cfg as UpgradeConfig
		for id in uc.prerequisites + uc.exclusions:
			if not upgrades.has(id):
				references_ok = false
	results.append({"name": "all content references resolve", "passed": references_ok, "why": ""})

	# Station Zero deliberately ships firearms only. Keep the generic melee /
	# hybrid resolver tests elsewhere; weapon variety now comes from magazines,
	# cadence, pellet counts and status riders, not obsolete melee data rows.
	var firearms := true
	var cadences := {}
	var magazines := {}
	var pellets := {}
	var kinds := {}
	var patterns := {}
	var damage_types := {}
	for cfg in weapons.values():
		var wc := cfg as WeaponConfig
		firearms = firearms and wc.kind == &"ranged" and wc.ammo_per_magazine > 0
		cadences[wc.swing_cooldown] = true
		magazines[wc.ammo_per_magazine] = true
		pellets[wc.projectile_count] = true
		kinds[wc.kind] = true
		patterns[wc.attack_pattern] = true
		damage_types[wc.damage_type] = true
	results.append({
		"name": "firearm library spans cadences, magazines and pellet counts",
		"passed": firearms and weapons.size() == 9 and cadences.size() >= 3 and magazines.size() >= 3 and pellets.size() >= 2,
		"why": "cadences=%s magazines=%s pellets=%s" % [str(cadences.keys()), str(magazines.keys()), str(pellets.keys())],
	})
	results.append({
		"name": "weapon library spans resolver kinds and attack patterns",
		"passed": kinds.has(&"ranged") and patterns.has(&"volley") and damage_types.size() >= 5,
		"why": "kinds=%s patterns=%s damage_types=%s" % [str(kinds.keys()), str(patterns.keys()), str(damage_types.keys())],
	})

	var categories := {}
	for cfg in upgrades.values():
		categories[(cfg as UpgradeConfig).category] = true
	results.append({
		"name": "upgrade library exposes build archetype categories",
		"passed": _contains_all(categories.keys(), [&"damage", &"defense", &"mobility", &"crit", &"status", &"aoe", &"sustain", &"economy"]),
		"why": str(categories.keys()),
	})

	# Determinism is independent of resource discovery order. A reversed pool must
	# produce the same ordered offer because selection sorts stable content ids first.
	var pool: Array = upgrades.values()
	var first := UpgradeSelector.choose_upgrade_choices(pool, 3, 551122, 6, {})
	pool.reverse()
	var second := UpgradeSelector.choose_upgrade_choices(pool, 3, 551122, 6, {})
	var deterministic := first.size() == second.size()
	if deterministic:
		for i in first.size():
			if first[i].upgrade_id != second[i].upgrade_id:
				deterministic = false
	results.append({"name": "upgrade choices stay deterministic across pool order", "passed": deterministic, "why": ""})
	results.append({"name": "zero-choice and invalid-wave requests are empty", "passed": UpgradeSelector.choose_upgrade_choices(first, 0, 1, 1, {}).is_empty() and UpgradeSelector.choose_upgrade_choices(first, 1, 1, 0, {}).is_empty(), "why": ""})

	# A representative build uses crit, status and area modifiers together without
	# mutating a shared resource or allowing invalid modifier keys.
	var prog := ProgressionComponent.new()
	prog.set_current_wave(2)
	var crit := upgrades.get("critical_edge") as UpgradeConfig
	var status := upgrades.get("status_attunement") as UpgradeConfig
	var area := upgrades.get("broad_sweep") as UpgradeConfig
	var applied := prog.apply_upgrade(crit) and prog.apply_upgrade(status) and prog.apply_upgrade(area)
	results.append({
		"name": "crit status and area build modifiers compose",
		"passed": applied and prog.get_stat(&"crit_chance_add", 0.0) > 0.0
			and prog.get_stat(&"status_duration_multiplier", 1.0) > 1.0
			and prog.get_stat(&"area_radius_multiplier", 1.0) > 1.0,
		"why": str(prog.get_debug_snapshot()),
	})

	var invalid_upgrade := UpgradeConfig.new()
	invalid_upgrade.upgrade_id = &"invalid_content"
	invalid_upgrade.stat_modifiers = {"not_a_real_modifier": 1.0}
	results.append({
		"name": "invalid modifier config is rejected by progression",
		"passed": not prog.apply_upgrade(invalid_upgrade),
		"why": "",
	})
	var full_stack := UpgradeConfig.new()
	full_stack.upgrade_id = &"bounded_test_upgrade"
	full_stack.max_stacks = 2
	full_stack.stat_modifiers = {"attack_damage_multiplier": 0.05}
	var stack_ok := prog.apply_upgrade(full_stack) and prog.apply_upgrade(full_stack)
	results.append({
		"name": "full stack rejects additional application",
		"passed": stack_ok and not prog.apply_upgrade(full_stack) and prog.get_stack_count(full_stack.upgrade_id) == 2,
		"why": "",
	})
	results.append({
		"name": "unavailable upgrade id never becomes an offer",
		"passed": UpgradeSelector.choose_upgrade_choices([null, invalid_upgrade], 1, 9, 2, {}).is_empty(),
		"why": "",
	})

	# New save fields are optional and safely normalized, while malformed build ids
	# and negative stack counts are sanitized for backwards compatibility.
	var SaveScript = load("res://scripts/save/save_schema.gd")
	var normalized: Dictionary = SaveScript.normalize_save({
		"schema_version": 3,
		"last_run_build": {
			"seed": -9,
			"current_wave": 4,
			"selected_upgrades": {"power": 2, "broken": -4},
			# 4 is not a content id: it must be dropped, not stringified to "4",
			# and it must not take the rest of the list down with it.
			"equipped_weapons": ["gladius", "gladius", 4],
			"equipped_skills": ["seismic_slam"],
		},
	})
	var build: Dictionary = normalized.get("last_run_build", {})
	# Read the expected version off the same script object the call went through,
	# so this never compares against a different constant than the one in use.
	var expected_version: int = int(SaveScript.SCHEMA_VERSION)
	var got_version: int = int(normalized.get("schema_version", 0))
	results.append({
		"name": "save schema preserves and sanitizes last run build",
		"passed": got_version == expected_version
			and int(build.get("seed", 1)) == 0
			and build.get("selected_upgrades", {}).get("broken", 1) == 0
			and (build.get("equipped_weapons", []) as Array) == ["gladius"]
			and (build.get("equipped_skills", []) as Array) == ["seismic_slam"],
		"why": "version=%d/%d build=%s" % [got_version, expected_version, str(build)],
	})

	prog.free()
	return results
