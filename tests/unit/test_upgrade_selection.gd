extends RefCounted

## Headless unit tests for the deterministic UpgradeSelector engine. Pure/static: no
## scene tree, no autoloads, no global RNG. Verifies determinism, exactly-3, no
## duplicates, unlock/prereq/exclusion/max-stack/disabled filtering and the graceful
## fewer-than-N fallback.

static func _cfg(id: StringName, value: float, wave: int = 1, weight: float = 1.0,
	stacks: int = 99, disabled := false) -> UpgradeConfig:
	var c := UpgradeConfig.new()
	c.upgrade_id = id
	c.display_name = String(id)
	c.description = "test"
	c.stat_modifiers = {"attack_damage_multiplier": value}
	c.unlock_wave = wave
	c.weight = weight
	c.max_stacks = stacks
	c.disabled = disabled
	return c


static func suite() -> Array:
	var results: Array = []
	var pool: Array = []
	for i in range(1, 11):
		pool.append(_cfg(StringName("u%d" % i), 0.1))

	var three := UpgradeSelector.choose_upgrade_choices(pool, 3, 999, 2, {})
	results.append({"name": "returns exactly 3 from a 10-pool", "passed": three.size() == 3, "why": "n=%d" % three.size()})
	var unique := true
	for i in three.size():
		for j in range(i + 1, three.size()):
			if three[i].upgrade_id == three[j].upgrade_id:
				unique = false
	results.append({"name": "no duplicate choices", "passed": unique, "why": ""})

	var again := UpgradeSelector.choose_upgrade_choices(pool, 3, 999, 2, {})
	var same := three.size() == again.size()
	if same:
		for idx in three.size():
			if three[idx].upgrade_id != again[idx].upgrade_id:
				same = false
	results.append({"name": "deterministic for same seed/wave/stacks", "passed": same, "why": ""})

	var diff_seed := UpgradeSelector.choose_upgrade_choices(pool, 3, 12345, 2, {})
	results.append({"name": "different seed yields different set (likely)",
		"passed": diff_seed.size() == 3 and diff_seed[0].upgrade_id != three[0].upgrade_id,
		"why": "first=%s vs %s" % [str(diff_seed[0].upgrade_id), str(three[0].upgrade_id)]})

	var non_null := true
	for c in three:
		if c == null or not c is UpgradeConfig:
			non_null = false
	results.append({"name": "never returns null/invalid choices", "passed": non_null, "why": ""})

	# unlock wave filtering
	var locked := _cfg(&"locked", 0.1, 10)
	var early := UpgradeSelector.eligible_upgrades([pool[0], locked], 2, {})
	results.append({"name": "unlock_wave filters out too-early upgrades",
		"passed": early.size() == 1 and early[0].upgrade_id == pool[0].upgrade_id, "why": "n=%d" % early.size()})

	# disabled
	var dis := _cfg(&"disabled_x", 0.1, 1, 1.0, 99, true)
	results.append({"name": "disabled upgrades excluded", "passed": not UpgradeSelector.is_eligible(dis, 2, {}), "why": ""})

	# prerequisites
	var req := _cfg(&"child", 0.1)
	req.prerequisites = [&"parent"]
	results.append({"name": "missing prerequisite -> ineligible", "passed": not UpgradeSelector.is_eligible(req, 2, {}), "why": ""})
	results.append({"name": "present prerequisite -> eligible", "passed": UpgradeSelector.is_eligible(req, 2, {&"parent": 1}), "why": ""})

	# exclusions
	var excl := _cfg(&"feud", 0.1)
	excl.exclusions = [&"power"]
	results.append({"name": "exclusion present -> ineligible", "passed": not UpgradeSelector.is_eligible(excl, 2, {&"power": 1}), "why": ""})

	# max stacks
	var capped := _cfg(&"cap", 0.1, 1, 1.0, 2)
	results.append({"name": "at max stacks -> ineligible", "passed": not UpgradeSelector.is_eligible(capped, 2, {&"cap": 2}), "why": ""})
	results.append({"name": "below max stacks -> eligible", "passed": UpgradeSelector.is_eligible(capped, 2, {&"cap": 1}), "why": ""})

	# fewer-than-N fallback returns available valid choices (no fake cards)
	var tiny := UpgradeSelector.choose_upgrade_choices([pool[0]], 3, 5, 2, {})
	results.append({"name": "fewer-than-N falls back to available choices",
		"passed": tiny.size() == 1 and tiny[0].upgrade_id == pool[0].upgrade_id, "why": "n=%d" % tiny.size()})

	# empty pool -> empty result (graceful, no crash)
	results.append({"name": "empty pool returns empty (no crash)",
		"passed": UpgradeSelector.choose_upgrade_choices([], 3, 5, 2, {}).is_empty(), "why": ""})

	# A zero-weight card sitting first must not win a 0.0 roll (acc starts at 0).
	var zero := _cfg(&"zero_w", 0.1, 1, 0.0)
	var heavy := _cfg(&"heavy_w", 0.1, 1, 4.0)
	var picked := UpgradeSelector.choose_upgrade_choices([zero, heavy], 1, 1, 1, {})
	results.append({
		"name": "zero-weight candidate is not selected over a positive weight",
		"passed": picked.size() == 1 and picked[0].upgrade_id == &"heavy_w",
		"why": "picked=%s" % (str(picked[0].upgrade_id) if not picked.is_empty() else "empty"),
	})
	return results
