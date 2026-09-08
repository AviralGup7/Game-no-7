extends RefCounted

## Headless unit tests for deterministic wave generation (WavePlanner), typed
## WaveConfig validation, and the three real enemy archetype resources. WavePlanner is
## a registered class_name and pure/static, so it is exercised directly without the
## scene tree or autoloads.

static func suite() -> Array:
	var results: Array = []

	# --- Wave 1: pure basics ---
	var q1 := WavePlanner.spawn_queue_for_wave(1)
	var c1 := WavePlanner.generate_wave(1, 999)
	results.append({
		"name": "wave 1 is 5 basics with matching plan",
		"passed": q1.size() == 5 and q1.count(WavePlanner.BASIC) == 5
			and c1.planned_count() == q1.size(),
		"why": "q1=%d planned=%d" % [q1.size(), c1.planned_count()],
	})

	# --- Wave 3 introduces fasts; no heavies yet ---
	var q3 := WavePlanner.spawn_queue_for_wave(3)
	var c3 := WavePlanner.generate_wave(3, 999)
	results.append({
		"name": "wave 3 = 8 basic + 1 fast, no heavy",
		"passed": q3.count(WavePlanner.BASIC) == 8 and q3.count(WavePlanner.FAST) == 1
			and q3.count(WavePlanner.HEAVY) == 0 and c3.planned_count() == 9,
		"why": "q3=%d" % q3.size(),
	})

	# --- Wave 5 introduces heavies ---
	var q5 := WavePlanner.spawn_queue_for_wave(5)
	results.append({
		"name": "wave 5 includes a heavy",
		"passed": q5.count(WavePlanner.HEAVY) == 1,
		"why": "q5=%d" % q5.size(),
	})

	# --- Determinism: identical inputs give identical output ---
	var a := WavePlanner.spawn_queue_for_wave(7)
	var b := WavePlanner.spawn_queue_for_wave(7)
	var wa := WavePlanner.generate_wave(7, 42)
	var wb := WavePlanner.generate_wave(7, 42)
	results.append({
		"name": "generation is deterministic for same wave/seed",
		"passed": a == b and wa.planned_count() == wb.planned_count(),
		"why": "",
	})

	# --- Generated WaveConfigs always validate clean ---
	var all_ok := true
	var latest_size := 0
	for w in range(1, 41):
		var cfg := WavePlanner.generate_wave(w, 7)
		if not cfg.validate().is_empty():
			all_ok = false
		latest_size = maxi(latest_size, cfg.planned_count())
	results.append({
		"name": "all generated wave configs (1..40) validate; counts capped",
		"passed": all_ok and latest_size <= 40,
		"why": "max_planned=%d all_ok=%s" % [latest_size, str(all_ok)],
	})

	# --- Difficulty scalars are bounded and >= 1 ---
	var s1 := WavePlanner.calculate_difficulty_scalars(1)
	var s40 := WavePlanner.calculate_difficulty_scalars(40)
	results.append({
		"name": "difficulty scalars bounded: wave1==1, wave40 capped",
		"passed": float(s1["hp"]) == 1.0 and float(s40["hp"]) <= 3.0
			and float(s40["damage"]) <= 2.5 and float(s40["speed"]) <= 1.3,
		"why": "",
	})

	# --- Difficulty scalars never go below 1 for out-of-range input ---
	var s0 := WavePlanner.calculate_difficulty_scalars(0)
	results.append({
		"name": "wave <= 0 clamps to wave-1 difficulty",
		"passed": float(s0["hp"]) == 1.0,
		"why": "",
	})

	# --- Real archetype .tres resources load and validate ---
	var tres := {
		&"basic": "res://data/enemies/basic_enemy.tres",
		&"fast": "res://data/enemies/fast_enemy.tres",
		&"heavy": "res://data/enemies/heavy_enemy.tres",
	}
	for id in tres:
		var res := load(tres[id])
		var ok: bool = res != null and res is EnemyConfig
		var cfg := res as EnemyConfig
		var name_ok: bool = ok and cfg != null and cfg.archetype_id == id and cfg.scene != null
		var valid_ok: bool = ok and cfg != null and cfg.validate().is_empty()
		results.append({
			"name": "%s archetype .tres loads with scene and validates" % String(id),
			"passed": name_ok and valid_ok,
			"why": "res=%s" % str(res),
		})
	return results
