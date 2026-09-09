extends RefCounted

## Headless unit tests for the DifficultyDirector (adaptive scoring) and WaveMutators
## (authored configs, the typed fold, deterministic rolls). The director's multiplier set is a
## `WaveModifiers` record now rather than a Dictionary, so this file reads fields; the richer
## fold/selection coverage lives in `test_wave_mutators.gd`.

static func suite() -> Array:
	var results: Array = []

	# --- Director: dominating play pushes positive, bounded ---
	var dom := DifficultyDirector.new(100.0)
	dom.set_time(0.0)
	for i in range(20):
		dom.record_kill()
	dom.set_time(10.0)
	var perf_dom := dom.performance_score()
	var mult_dom := dom.next_wave_multipliers()
	results.append({
		"name": "Director rewards domination within bounds",
		"passed": perf_dom > 0.0 and mult_dom.hp_mult > 1.0 and mult_dom.hp_mult <= 1.25,
		"why": "perf=%.2f" % perf_dom,
	})

	# --- Director: heavy damage pushes negative + breather ---
	var hurt := DifficultyDirector.new(100.0)
	hurt.set_time(0.0)
	hurt.record_damage_taken(90.0)
	hurt.set_time(5.0)
	var perf_hurt := hurt.performance_score()
	results.append({
		"name": "Director eases off struggling players + breather",
		"passed": perf_hurt < 0.0 and hurt.suggest_breather() and not hurt.suggest_spice(),
		"why": "perf=%.2f" % perf_hurt,
	})

	# --- Director: window expiry forgets old samples ---
	var forget := DifficultyDirector.new(100.0)
	forget.set_time(0.0)
	forget.record_damage_taken(50.0)
	forget.set_time(DifficultyDirector.WINDOW_SECONDS + 60.0)
	results.append({
		"name": "Director forgets samples outside the window",
		"passed": is_equal_approx(forget.recent_dps_taken(), 0.0) and is_equal_approx(forget.recent_kill_rate(), 0.0),
		"why": "",
	})

	# --- Director: the knobs a struggling player should NOT get are absent when perf <= 0 ---
	results.append({
		"name": "Director hands the record's score/elite bonus to nobody while hurting",
		"passed": is_equal_approx(hurt.next_wave_multipliers().score_mult, 1.0)
			and is_equal_approx(hurt.next_wave_multipliers().elite_bonus, 0.0)
			and hurt.next_wave_multipliers().count_bonus < 0,
		"why": "score=%s elite=%s count=%s" % [hurt.next_wave_multipliers().score_mult,
				hurt.next_wave_multipliers().elite_bonus, hurt.next_wave_multipliers().count_bonus],
	})

	# --- Mutators: every authored id resolves to a validated, non-neutral config ---
	var ids := WaveMutators.ordered_ids()
	var all_known := not ids.is_empty()
	for m in ids:
		var cfg := WaveMutators.resolve(m)
		if cfg == null or not cfg.validate().is_empty() or cfg.is_neutral():
			all_known = false
	results.append({
		"name": "WaveMutators: authored data is complete, unknown ids resolve to nothing",
		"passed": all_known and WaveMutators.is_known(&"swift_horde") and not WaveMutators.is_known(&"nope"),
		"why": "%d mutators" % ids.size(),
	})

	# --- Mutators: combine math ---
	var combo := WaveMutators.combine([&"swift_horde", &"iron_hide"])
	results.append({
		"name": "WaveMutators combine multiplies + maxes severity",
		"passed": is_equal_approx(combo.hp_mult, 0.85 * 1.6) and is_equal_approx(combo.speed_mult, 1.3 * 0.85)
			and combo.severity == WaveMutatorConfig.SEVERITY_MAJOR,
		"why": str(combo.debug_dictionary()),
	})

	# --- Mutators: rolls deterministic + wave-gated ---
	var none := WaveMutators.roll_for_wave(2, 123)
	var one := WaveMutators.roll_for_wave(5, 123)
	var one_again := WaveMutators.roll_for_wave(5, 123)
	var two := WaveMutators.roll_for_wave(9, 123)
	results.append({
		"name": "WaveMutators none<4, one 4-7, two 8+, deterministic",
		"passed": none.is_empty() and one.size() == 1 and one == one_again and two.size() == 2 and two[0] != two[1],
		"why": "",
	})

	# --- Mutators: banner text ---
	results.append({
		"name": "WaveMutators banner text lists names",
		"passed": WaveMutators.banner_text([]) == "" and WaveMutators.banner_text([&"swift_horde"]).contains("Swift"),
		"why": "",
	})

	return results
