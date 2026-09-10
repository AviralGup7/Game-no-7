extends RefCounted

## Headless unit tests for the wave-mutator subsystem: authored configs (`WaveMutatorConfig`),
## the typed fold (`WaveModifiers`) and the deterministic selector (`WaveMutators`).
##
## These run with no ContentRegistry (the harness boots EventBus only), so every lookup goes
## through the same registry-or-disk fallback a tooling script uses — which is exactly the path
## that must not depend on a live autoload. The shipped numbers are mirrored in
## `tests/python/test_regress_wave_mutators.py`; what lives here is the arithmetic and the refusal
## paths, i.e. the questions only a running script can answer.
##
## A config built with `.new()` has an empty `resource_path`, so `validate()`'s file-name rule
## stands down and the rest of the rules are the ones under test.

const SHIPPED_ROLL_ORDER: Array[StringName] = [
	&"swift_horde", &"iron_hide", &"elite_surge", &"glass_cannon",
	&"bounty_hunt", &"volatile_mix", &"ember_winds",
]


static func suite() -> Array:
	var results: Array = []

	# --- A neutral record really is neutral, and folding nothing changes nothing ---
	var neutral := WaveModifiers.neutral()
	var before := neutral.debug_dictionary()
	neutral.fold_mutator(null)
	results.append({
		"name": "WaveModifiers starts neutral and folding a null config is a no-op",
		"passed": neutral.is_neutral() and neutral.debug_dictionary() == before,
		"why": str(before),
	})

	# --- Multiply vs add vs max, read from the data, not restated as a table here ---
	# elite_surge (elite 0.2) + bounty_hunt (elite 0.05) => ADD => 0.25.
	# volatile_mix (explode 0.35) + bounty_hunt (explode 0)  => MAX => 0.35, not a sum.
	var stacked := WaveMutators.combine([&"elite_surge", &"bounty_hunt", &"volatile_mix"])
	results.append({
		"name": "additive chances add, one-shot flags take the max",
		"passed": is_equal_approx(stacked.elite_bonus, 0.25) and is_equal_approx(stacked.explode_chance, 0.35),
		"why": str(stacked.debug_dictionary()),
	})

	# --- The two knobs that used to die in SpawnManager's four-key whitelist ---
	# Bounty Hunt's whole pitch is "far more currency"; Glass Cannon's is "you hit harder".
	var paid := WaveMutators.combine([&"bounty_hunt"])
	var cannon := WaveMutators.combine([&"glass_cannon"])
	results.append({
		"name": "currency_mult and player_damage_mult survive the fold",
		"passed": is_equal_approx(paid.currency_mult, 2.0) and is_equal_approx(paid.score_mult, 1.0) \
			and is_equal_approx(cannon.player_damage_mult, 1.25) and is_equal_approx(cannon.hp_mult, 0.8),
		"why": "currency=%s player=%s" % [paid.currency_mult, cannon.player_damage_mult],
	})

	# --- Bounds are applied once, after the fold, to whatever the data asked for ---
	# `push_error` fires on the INF/NaN lines below on purpose: the rule under test is "a broken
	# number is reported, then bounded". Godot prints those as `USER ERROR:`, which the CI log
	# grep does not treat as a script error (same reasoning as test_arena_world.gd's refusal cases).
	var wild := WaveModifiers.neutral()
	wild.hp_mult = 0.0
	wild.score_mult = -3.0
	wild.speed_mult = INF
	wild.damage_mult = NAN
	wild.elite_bonus = 5.0
	wild.explode_chance = 2.0
	wild.count_bonus = 9
	wild.clamp_bounds()
	results.append({
		"name": "clamp_bounds floors multipliers, caps chances and bounds counts",
		"passed": is_equal_approx(wild.hp_mult, WaveMutatorConfig.MULT_FLOOR) \
			and is_equal_approx(wild.score_mult, WaveMutatorConfig.MULT_FLOOR) \
			and is_equal_approx(wild.speed_mult, WaveMutatorConfig.MULT_CEIL) \
			and is_equal_approx(wild.damage_mult, 1.0) \
			and is_equal_approx(wild.elite_bonus, WaveMutatorConfig.ELITE_BONUS_MAX) \
			and is_equal_approx(wild.explode_chance, 1.0) \
			and wild.count_bonus == WaveModifiers.COUNT_BONUS_MAX,
		"why": str(wild.debug_dictionary()),
	})

	# --- Fold order: plan scalars, then the director, then the mutators ---
	var folded := WaveModifiers.neutral()
	folded.apply_plan_scalars({"hp": 2.0, "damage": 1.5, "speed": 1.0})
	var nudge := WaveModifiers.neutral()
	nudge.hp_mult = 1.1
	nudge.damage_mult = 1.06
	nudge.score_mult = 1.2
	nudge.elite_bonus = 0.1
	nudge.count_bonus = 1
	folded.fold_director(nudge)
	WaveMutators.fold_into(folded, [&"iron_hide"])
	var expected := 2.0 * 1.1 * 1.6
	results.append({
		"name": "plan scalars and the director nudge multiply before mutators",
		"passed": is_equal_approx(folded.hp_mult, expected) and is_equal_approx(folded.elite_bonus, 0.1) \
			and folded.count_bonus == 1 and is_equal_approx(folded.score_mult, 1.2 * 1.25),
		"why": "hp=%.4f want=%.4f" % [folded.hp_mult, expected],
	})

	# --- An elite's own factors ride on top of the wave's, without touching the record ---
	var scaled := folded.enemy_scaling(2.0, 1.5, 1.0)
	results.append({
		"name": "enemy_scaling multiplies the wave onto the caller's own factors",
		"passed": is_equal_approx(scaled.x, expected * 2.0) and is_equal_approx(scaled.y, folded.damage_mult * 1.5),
		"why": str(scaled),
	})

	# --- Ember Winds: the mutator's entire mechanic is a status, so it has to resolve ---
	var ember := WaveMutators.combine([&"ember_winds"])
	var ember_effect := ember.status_effect
	results.append({
		"name": "ember_winds resolves its authored status and stamps both sides",
		"passed": ember_effect != null and ember_effect.effect_id == &"ember_air" \
			and is_equal_approx(ember_effect.dot_per_second, 1.5) \
			# one stack, authored in `data/mutators/ember_winds.tres` and mirrored by
			# `tests/python/test_regress_wave_mutators.py`; targeting both sides is what `all` means, and
			# it never meant "apply it twice".
			and ember.status_stacks == 1 and ember.status_targets_enemies and ember.status_targets_player,
		"why": "effect=%s" % (String(ember_effect.effect_id) if ember_effect != null else "<unresolved>"),
	})

	# --- `status_targets` is an id, so `all` must mean both and not be a substring test ---
	var enemies_only := _stub_config(&"enemies_only")
	enemies_only.status_targets = WaveMutatorConfig.TARGET_ENEMIES
	var one_sided := WaveModifiers.neutral()
	one_sided.fold_mutator(enemies_only)
	var nobody := WaveModifiers.neutral()
	var untargeted := _stub_config(&"untargeted")
	# Names a status but targets nobody: `has_status()` is the single place that decides whether a
	# mutator carries one, so a fold must not half-apply it (enemies burnt, player untouched).
	untargeted.status_targets = WaveMutatorConfig.TARGET_NONE
	nobody.fold_mutator(untargeted)
	results.append({
		"name": "status targets are exact ids: enemies-only never lights the player up",
		"passed": one_sided.status_targets_enemies and not one_sided.status_targets_player \
			and ember.status_targets_enemies and ember.status_targets_player \
			and not nobody.status_targets_enemies and not nobody.status_targets_player,
		"why": "one_sided=%s/%s" % [one_sided.status_targets_enemies, one_sided.status_targets_player],
	})

	# --- Unknown ids are reported and dropped, never folded as a neutral stand-in ---
	var partial := WaveMutators.combine([&"iron_hide", &"definitely_not_a_mutator"])
	results.append({
		"name": "an unknown mutator id is dropped without erasing the rest",
		"passed": partial.mutator_ids.size() == 1 and partial.mutator_ids[0] == &"iron_hide" \
			and is_equal_approx(partial.hp_mult, 1.6),
		"why": str(partial.mutator_ids),
	})

	# --- Authoring refusals ---
	var ghost := _stub_config(&"neutral_ghost")
	ghost.hp_mult = 1.0
	ghost.status_effect_id = &""
	var bad_sev := _stub_config(&"bad_severity")
	bad_sev.severity = &"catastrophic"
	var bad_target := _stub_config(&"bad_target")
	bad_target.status_targets = &"spectators"
	var tiny := _stub_config(&"too_tiny")
	tiny.hp_mult = 0.01
	results.append({
		"name": "a neutral mutator is refused outright, and bad knobs are reported",
		"passed": not ghost.validate().is_empty() and not bad_sev.validate().is_empty() \
			and not bad_target.validate().is_empty() and not tiny.validate().is_empty() \
			and ghost.is_neutral(),
		"why": "ghost=%s sev=%s target=%s tiny=%s" % [ghost.validate(), bad_sev.validate(),
				bad_target.validate(), tiny.validate()],
	})

	# --- Roll shape + the authored wave floor (Glass Cannon's gate is data now) ---
	var none := WaveMutators.roll_for_wave(3, 4242)
	var gated := true
	for s in range(24):
		for id in WaveMutators.roll_for_wave(4, s * 977 + 13):
			if id == &"glass_cannon":
				gated = false
		for id in WaveMutators.roll_for_wave(5, s * 991 + 17):
			if id == &"glass_cannon":
				gated = false
	var unlocked := false
	for s in range(24):
		if &"glass_cannon" in WaveMutators.roll_for_wave(6, s * 1009 + 23):
			unlocked = true
			break
	var one := WaveMutators.roll_for_wave(5, 123)
	var two := WaveMutators.roll_for_wave(9, 123)
	results.append({
		"name": "rolls are gated by wave and by min_wave, and stay deterministic",
		"passed": none.is_empty() and one.size() == 1 and one == WaveMutators.roll_for_wave(5, 123) \
			and two.size() == 2 and two[0] != two[1] and gated and unlocked,
		"why": "wave3=%d gated=%s unlocked=%s" % [none.size(), gated, unlocked],
	})

	# --- resolve_for_wave: authored wins, breather vetoes, spice adds a distinct second ---
	var authored := WaveMutators.resolve_for_wave([&"iron_hide"], 9, 7, false, false)
	var vetoed := WaveMutators.resolve_for_wave([], 9, 7, true, false)
	var spiced := WaveMutators.resolve_for_wave([], 4, 7, false, true)
	var deduped := WaveMutators.resolve_for_wave([&"iron_hide", &"iron_hide"], 2, 7, false, false)
	var stale := WaveMutators.resolve_for_wave([&"iron_hide", &"ghost_id"], 2, 7, false, false)
	results.append({
		"name": "resolve_for_wave honours declarations, breathers, spice, duplicates and typos",
		"passed": authored.size() == 1 and authored[0] == &"iron_hide" and vetoed.is_empty() \
			and spiced.size() == 2 and spiced[0] != spiced[1] \
			and deduped.size() == 1 and stale.size() == 1 and stale[0] == &"iron_hide",
		"why": "auth=%s veto=%s spice=%s dedupe=%s" % [authored, vetoed, spiced, deduped],
	})

	# --- The daily challenge draws out of the ROLL ORDER, so pin the order itself ---
	var ids := WaveMutators.ordered_ids()
	results.append({
		"name": "the shipped roll order is unchanged (the daily pool indexes it)",
		"passed": ids == SHIPPED_ROLL_ORDER,
		"why": str(ids),
	})

	# --- Names for the banner: display_name falls back to the id, never to an empty line ---
	results.append({
		"name": "display_name and banner_text cover known and unknown ids",
		"passed": WaveMutators.display_name(&"swift_horde") == "Swift Horde" \
			and WaveMutators.display_name(&"mystery") == "mystery" \
			and WaveMutators.banner_text([]) == "" \
			and WaveMutators.banner_text([&"swift_horde"]).contains("Swift"),
		"why": "",
	})

	# --- RunState mirrors the ids the summary and the save show ---
	var run := RunState.new()
	run.set_wave_modifiers(stacked)
	var fresh := RunState.new()
	fresh.set_wave_modifiers(null)
	var mirrored: Array = run.summary()["active_modifiers"]
	results.append({
		"name": "RunState publishes the wave's ids and survives a null record",
		"passed": run.active_modifiers.size() == stacked.mutator_ids.size() and mirrored.size() == 3 \
			and fresh.active_modifiers.is_empty() and fresh.modifiers.is_neutral(),
		"why": str(run.active_modifiers),
	})

	return results


## A config with every mandatory authored field set (and hp_mult 2.0 so it is not neutral), so a
## test can break exactly one knob without tripping the others. Status presence is decided by
## `status_effect_id` plus a non-empty target list, never by the target alone.
static func _stub_config(id: StringName) -> WaveMutatorConfig:
	var cfg := WaveMutatorConfig.new()
	cfg.mutator_id = id
	cfg.display_name = "Test Mutator"
	cfg.description = "test fixture"
	cfg.hp_mult = 2.0
	cfg.severity = WaveMutatorConfig.SEVERITY_MINOR
	cfg.status_effect_id = &"ember_air"
	cfg.status_targets = WaveMutatorConfig.TARGET_ALL
	cfg.status_stacks = 1
	return cfg
