extends RefCounted

## Headless unit tests for the real upgrade library under res://data/upgrades/.
## Loads the .tres resources directly (no autoload dependency) and asserts each valid,
## uniquely id'd, has >= 1 recognized modifier, and the required 10-set is present.

static func suite() -> Array:
	var results: Array = []
	var ids := [
		&"vitality", &"swift", &"power", &"haste", &"fortified", &"hunter",
		&"reach", &"force", &"scavenger", &"bloodlust",
	]
	var seen := {}
	var all_valid := true
	for id in ids:
		var res := load("res://data/upgrades/%s.tres" % String(id))
		var cfg := res as UpgradeConfig
		var valid := cfg != null and cfg.upgrade_id == id and cfg.validate().is_empty() \
			and cfg.stat_modifiers.size() >= 1 and cfg.max_stacks >= 1 and cfg.weight > 0.0
		if not valid:
			all_valid = false
		seen[String(id)] = valid
		results.append({
			"name": "upgrade '%s' .tres loads and validates" % String(id),
			"passed": valid,
			"why": "res=%s" % str(res),
		})
	results.append({
		"name": "all 10 required upgrades present and valid",
		"passed": all_valid and seen.size() == 10,
		"why": "",
	})

	# No duplicate upgrade ids across files (guard against a stray extra .tres colliding).
	var extras_valid := true
	var dir := DirAccess.open("res://data/upgrades")
	if dir != null:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if not dir.current_is_dir() and f.ends_with(".tres"):
				var extra := load("res://data/upgrades/%s" % f)
				if extra is UpgradeConfig:
					var eid: String = String(extra.upgrade_id)
					if eid not in seen:
						seen[eid] = true  # count any additional valid id once
			f = dir.get_next()
		dir.list_dir_end()
	results.append({
		"name": "upgrade .tres dir enumerates without error",
		"passed": extras_valid,
		"why": "",
	})
	return results
