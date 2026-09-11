extends RefCounted

## Headless unit tests for ProgressionComponent modifier semantics (single documented
## model: base * (1 + sum) for multiplicative; base + sum for additive; cooldown uses
## (1 + sum) with a negative sum = reduction, clamped). Pure: no tree/autoloads.

static func _cfg(id: StringName, mods: Dictionary, stacks: int = 99) -> UpgradeConfig:
	var c := UpgradeConfig.new()
	c.upgrade_id = id
	c.stat_modifiers = mods
	c.max_stacks = stacks
	return c


static func suite() -> Array:
	var results: Array = []
	var prog := ProgressionComponent.new()
	prog.reset()

	# one stack of +15% damage
	var ok1 := prog.apply_upgrade(_cfg(&"power", {"attack_damage_multiplier": 0.15}))
	results.append({"name": "apply one damage stack", "passed": ok1, "why": ""})
	results.append({"name": "one +15% stack: base * 1.15", "passed": is_equal_approx(prog.get_stat(&"attack_damage_multiplier", 100.0), 115.0), "why": "%f" % prog.get_stat(&"attack_damage_multiplier", 100.0)})

	# second stack -> additive total 0.30 -> base * 1.30
	var ok2 := prog.apply_upgrade(_cfg(&"power2", {"attack_damage_multiplier": 0.15}))
	results.append({"name": "two +15% stacks stack additively -> *1.30",
		"passed": ok2 and is_equal_approx(prog.get_stat(&"attack_damage_multiplier", 100.0), 130.0),
		"why": "%f" % prog.get_stat(&"attack_damage_multiplier", 100.0)})

	# cooldown reduction must REDUCE not increase
	var cprog := ProgressionComponent.new()
	cprog.apply_upgrade(_cfg(&"haste", {"attack_cooldown_multiplier": -0.10}))
	results.append({"name": "-10% cooldown reduces (0.9x) not increases",
		"passed": is_equal_approx(cprog.get_stat(&"attack_cooldown_multiplier", 1.0), 0.9),
		"why": "%f" % cprog.get_stat(&"attack_cooldown_multiplier", 1.0)})
	# floor clamp
	var c2 := ProgressionComponent.new()
	c2.apply_upgrade(_cfg(&"haste_many", {"attack_cooldown_multiplier": -0.99}))
	results.append({"name": "cooldown clamps to a small floor (never 0/negative)",
		"passed": c2.get_stat(&"attack_cooldown_multiplier", 1.0) >= 0.05,
		"why": "%f" % c2.get_stat(&"attack_cooldown_multiplier", 1.0)})

	# movement
	var mprog := ProgressionComponent.new()
	mprog.apply_upgrade(_cfg(&"swift", {"move_speed_multiplier": 0.15}))
	results.append({"name": "movement multiplier base * 1.15",
		"passed": is_equal_approx(mprog.get_stat(&"move_speed_multiplier", 6.0), 6.9),
		"why": "%f" % mprog.get_stat(&"move_speed_multiplier", 6.0)})

	# knockback
	var kprog := ProgressionComponent.new()
	kprog.apply_upgrade(_cfg(&"force", {"knockback_multiplier": 0.15}))
	results.append({"name": "knockback multiplier base * 1.15",
		"passed": is_equal_approx(kprog.get_stat(&"knockback_multiplier", 6.0), 6.9), "why": ""})

	# health addition
	var hprog := ProgressionComponent.new()
	hprog.apply_upgrade(_cfg(&"vitality", {"max_health_add": 20.0}))
	results.append({"name": "max health add 100 -> 120",
		"passed": is_equal_approx(hprog.get_stat(&"max_health_add", 100.0), 120.0), "why": ""})

	# resistance clamps to [0,1]
	var rprog := ProgressionComponent.new()
	rprog.apply_upgrade(_cfg(&"fort1", {"damage_resistance_add": 0.6}))
	rprog.apply_upgrade(_cfg(&"fort2", {"damage_resistance_add": 0.6}))
	results.append({"name": "resistance clamped to <= 1.0",
		"passed": is_equal_approx(rprog.get_stat(&"damage_resistance_add", 0.0), 1.0),
		"why": "%f" % rprog.get_stat(&"damage_resistance_add", 0.0)})

	# attack range add
	var aprog := ProgressionComponent.new()
	aprog.apply_upgrade(_cfg(&"reach", {"attack_range_add": 0.35}))
	results.append({"name": "attack range add 2.6 -> 2.95",
		"passed": is_equal_approx(aprog.get_stat(&"attack_range_add", 2.6), 2.95), "why": ""})

	# score / currency multipliers
	var sprog := ProgressionComponent.new()
	sprog.apply_upgrade(_cfg(&"hunter", {"score_multiplier_add": 0.10}))
	results.append({"name": "score multiplier add total 0.10 (consumers add 1.0)",
		"passed": is_equal_approx(sprog.get_stat(&"score_multiplier_add", 0.0), 0.10), "why": ""})
	var cuprog := ProgressionComponent.new()
	cuprog.apply_upgrade(_cfg(&"scavenger", {"currency_multiplier_add": 0.15}))
	results.append({"name": "currency multiplier add total 0.15",
		"passed": is_equal_approx(cuprog.get_stat(&"currency_multiplier_add", 0.0), 0.15), "why": ""})

	# healing on kill
	var bprog := ProgressionComponent.new()
	bprog.apply_upgrade(_cfg(&"bloodlust", {"healing_on_kill": 4.0}))
	results.append({"name": "healing_on_kill additive 0 -> 4",
		"passed": is_equal_approx(bprog.get_stat(&"healing_on_kill", 0.0), 4.0), "why": ""})

	# reject null / max stacks / reset
	results.append({"name": "apply_upgrade(null) rejected", "passed": not prog.apply_upgrade(null), "why": ""})
	var cap := ProgressionComponent.new()
	cap.apply_upgrade(_cfg(&"c", {"attack_damage_multiplier": 0.1}, 2))
	cap.apply_upgrade(_cfg(&"c", {"attack_damage_multiplier": 0.1}, 2))
	var third := cap.apply_upgrade(_cfg(&"c", {"attack_damage_multiplier": 0.1}, 2))
	results.append({"name": "max stacks respected (3rd rejected)", "passed": not third and cap.get_stack_count(&"c") == 2, "why": ""})

	cap.reset()
	results.append({"name": "reset clears stacks and modifiers",
		"passed": cap.get_upgrade_stack_snapshot().is_empty() and is_equal_approx(cap.get_stat(&"attack_damage_multiplier", 10.0), 10.0), "why": ""})

	# no modifier present returns base unchanged
	var fresh := ProgressionComponent.new()
	results.append({"name": "unmodified stat returns base", "passed": is_equal_approx(fresh.get_stat(&"move_speed_multiplier", 6.0), 6.0), "why": ""})

	var qprog := ProgressionComponent.new()
	qprog.apply_upgrade(_cfg(&"quartermaster", {"pickup_radius_add": 0.75}))
	results.append({
		"name": "pickup_radius_add is additive from 0",
		"passed": is_equal_approx(qprog.get_stat(&"pickup_radius_add", 0.0), 0.75),
		"why": "%f" % qprog.get_stat(&"pickup_radius_add", 0.0),
	})
	return results
