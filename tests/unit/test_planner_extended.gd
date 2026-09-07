extends RefCounted

## Headless unit tests for the extended WavePlanner API: early waves unchanged,
## late waves inject new archetypes, boss waves crown a warlord, and authored
## entries expand deterministically.

static func suite() -> Array:
	var results: Array = []

	# --- Waves 1-5 identical to the classic queue ---
	var identical := true
	for w in range(1, 6):
		if WavePlanner.extended_queue_for_wave(w, 4242) != WavePlanner.spawn_queue_for_wave(w):
			identical = false
	results.append({"name": "extended_queue matches classic for waves 1-5", "passed": identical, "why": ""})

	# --- Wave 6+ injects new archetypes ---
	var q6 := WavePlanner.extended_queue_for_wave(6, 4242)
	var classic6 := WavePlanner.spawn_queue_for_wave(6)
	var has_new := false
	for id in q6:
		if id in [&"ranged", &"dasher", &"exploder", &"splitter"]:
			has_new = true
	results.append({
		"name": "wave 6 keeps classics and injects new archetypes",
		"passed": has_new and q6.size() > classic6.size() and q6.count(&"basic") == classic6.count(&"basic"),
		"why": "q6=%d classic=%d" % [q6.size(), classic6.size()],
	})

	# --- Wave 10 crowns a warlord first ---
	var q10 := WavePlanner.extended_queue_for_wave(10, 4242)
	var q10b := WavePlanner.extended_queue_for_wave(10, 4242)
	results.append({
		"name": "wave 10 leads with the warlord, deterministic",
		"passed": not q10.is_empty() and q10[0] == &"warlord" and q10 == q10b,
		"why": "",
	})

	# --- Authored entries expand with exact counts ---
	var cfg := WaveConfig.new()
	cfg.wave_number = 3
	var e1 := WaveSpawnEntry.new()
	e1.archetype_id = &"basic"
	e1.count = 4
	var e2 := WaveSpawnEntry.new()
	e2.archetype_id = &"fast"
	e2.count = 2
	cfg.spawn_entries = [e1, e2]
	var expanded := WavePlanner.expand_authored_entries(cfg, 99)
	var expanded2 := WavePlanner.expand_authored_entries(cfg, 99)
	results.append({
		"name": "expand_authored_entries exact counts + deterministic",
		"passed": expanded.size() == 6 and expanded.count(&"basic") == 4
			and expanded.count(&"fast") == 2 and expanded == expanded2,
		"why": str(expanded),
	})
	results.append({
		"name": "expand_authored_entries null-safe",
		"passed": WavePlanner.expand_authored_entries(null, 1).is_empty(),
		"why": "",
	})

	# --- Real new .tres resources load and validate ---
	var paths := {
		"ranged": "res://data/enemies/ranged_enemy.tres",
		"dasher": "res://data/enemies/dasher_enemy.tres",
		"exploder": "res://data/enemies/exploder_enemy.tres",
		"splitter": "res://data/enemies/splitter_enemy.tres",
		"warlord": "res://data/enemies/warlord_enemy.tres",
	}
	var all_ok := true
	var why := ""
	for id in paths:
		var res := load(paths[id])
		var ec := res as EnemyConfig
		if ec == null or ec.archetype_id != StringName(id) or ec.scene == null or not ec.validate().is_empty():
			all_ok = false
			why = "bad: " + id
	var wres := load("res://data/weapons/gladius.tres") as WeaponConfig
	if wres == null or wres.weapon_id != &"gladius" or not wres.validate().is_empty():
		all_ok = false
		why = "bad: gladius"
	results.append({"name": "new enemy + weapon .tres load and validate", "passed": all_ok, "why": why})

	return results
