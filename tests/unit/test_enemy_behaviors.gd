extends RefCounted

## Headless unit tests for the encounter pass: SpawnLedger direct (burst) spawn
## accounting, BossController phase math, BossPhaseConfig validation, the extended
## EnemyConfig fields (dash/fuse/poise/retreat), and elite-affix behavior hooks.
## All pure/deterministic — node-based behavior lives in the run_tests.gd
## enemy-encounter integration section.

static func suite() -> Array:
	var results: Array = []
	_ledger_direct_spawn(results)
	_ledger_no_false_completion(results)
	_boss_phase_math(results)
	_boss_phase_config(results)
	_enemy_config_validation(results)
	_elite_hooks(results)
	return results


static func _check(results: Array, name: String, passed: bool, why: String = "") -> void:
	results.append({"name": name, "passed": passed, "why": why})


# --- SpawnLedger: burst children register as planned+spawned without queueing ---

static func _ledger_direct_spawn(results: Array) -> void:
	var ledger := SpawnLedger.new()
	var queue: Array[StringName] = [&"splitter"]
	ledger.reset(queue)
	ledger.note_head(&"splitter")
	ledger.pop_on_success()
	# Parent dies, 2 children burst-spawn at the death position.
	ledger.register_direct_spawn(&"mite")
	ledger.register_direct_spawn(&"mite")
	_check(results, "direct spawns extend planned + spawned, not pending",
		ledger.planned_count() == 3 and ledger.spawned_count() == 3
		and ledger.pending_count() == 0 and ledger.is_empty(),
		"snap=%s" % str(ledger.snapshot()))
	ledger.record_defeat()  # parent
	ledger.record_defeat()  # child 1
	ledger.record_defeat()  # child 2
	_check(results, "burst wave completes only after every child is defeated",
		ledger.defeated_count() == 3 and ledger.failed_count() == 0,
		"defeated=%d" % ledger.defeated_count())


# --- A burst wave can never falsely complete or stall ---

static func _ledger_no_false_completion(results: Array) -> void:
	var ledger := SpawnLedger.new()
	var queue: Array[StringName] = [&"splitter"]
	ledger.reset(queue)
	ledger.note_head(&"splitter")
	ledger.pop_on_success()
	ledger.register_direct_spawn(&"mite")
	ledger.register_direct_spawn(&"mite")
	# Only the parent is killed: defeats must NOT equal planned yet.
	ledger.record_defeat()
	_check(results, "killing only the parent leaves the burst wave incomplete",
		ledger.defeated_count() == 1 and ledger.planned_count() == 3)
	# A failed queued spawn stays distinct from defeats.
	ledger.extend_one(&"ghost")
	ledger.note_head(&"ghost")
	var dropped := false
	for i in range(SpawnLedger.MAX_FAILED_ATTEMPTS):
		dropped = ledger.note_attempt()
	_check(results, "failed burst-fallback spawn drops as failed, not defeated",
		dropped and ledger.failed_count() == 1 and ledger.defeated_count() == 1,
		"failed=%d defeated=%d" % [ledger.failed_count(), ledger.defeated_count()])


# --- BossController phase math (pure) ---

static func _boss_phase_math(results: Array) -> void:
	var phases := [
		{"threshold": 1.0, "name": "Awakening"},
		{"threshold": 0.66, "name": "Fury"},
		{"threshold": 0.33, "name": "Enrage"},
	]
	var cases := {1.0: 0, 0.99: 0, 0.66: 1, 0.5: 1, 0.33: 2, 0.1: 2, 0.0: 2}
	var all_ok := true
	var why := ""
	for frac in cases:
		var got := BossController.phase_index_for_fraction(float(frac), phases)
		if got != int(cases[frac]):
			all_ok = false
			why = "frac=%s got=%d want=%d" % [str(frac), got, int(cases[frac])]
	_check(results, "phase_index_for_fraction follows descending thresholds", all_ok, why)
	_check(results, "phase index clamps odd fractions",
		BossController.phase_index_for_fraction(1.7, phases) == 0
		and BossController.phase_index_for_fraction(-2.0, phases) == 2, "")
	_check(results, "empty phase list resolves phase 0",
		BossController.phase_index_for_fraction(0.5, []) == 0, "")


# --- BossPhaseConfig validation ---

static func _boss_phase_config(results: Array) -> void:
	var ok := BossPhaseConfig.new()
	ok.phase_name = "Fury"
	ok.threshold = 0.66
	ok.damage_mult = 1.25
	ok.speed_mult = 1.1
	ok.abilities = [&"slam", &"summon"]
	_check(results, "authored boss phase validates", ok.validate().is_empty(), str(ok.validate()))
	var d := ok.to_dict()
	_check(results, "phase to_dict carries tuning",
		String(d.get("name", "")) == "Fury" and float(d.get("threshold", 0.0)) == 0.66
		and (d.get("abilities") as Array).size() == 2, str(d))
	var bad := BossPhaseConfig.new()
	bad.phase_name = ""
	bad.threshold = 1.4
	bad.abilities = [&"meteor"]
	_check(results, "bad phase entries are all flagged",
		bad.validate().size() >= 3, str(bad.validate()))


# --- EnemyConfig extended fields ---

static func _enemy_config_validation(results: Array) -> void:
	var base := EnemyConfig.new()
	base.archetype_id = &"probe"
	base.scene = PackedScene.new()
	_check(results, "default melee config validates (no duplicate members)",
		base.validate().is_empty(), str(base.validate()))

	var dash := EnemyConfig.new()
	dash.archetype_id = &"dasher_probe"
	dash.scene = PackedScene.new()
	dash.dash_trigger_range = 7.5
	dash.dash_windup = 0.45
	dash.dash_speed = 13.0
	dash.dash_duration = 0.45
	dash.dash_contact_radius = 1.3
	dash.dash_recovery = 0.7
	dash.dash_cooldown = 3.2
	_check(results, "valid dasher config validates", dash.validate().is_empty(), str(dash.validate()))

	var bad_dash := dash.duplicate() as EnemyConfig
	bad_dash.dash_cooldown = 0.2  # shorter than the dash itself
	bad_dash.dash_windup = 0.01    # unreadable telegraph
	_check(results, "dash cooldown/windup rules enforced", bad_dash.validate().size() >= 2,
		str(bad_dash.validate()))

	var fuse := EnemyConfig.new()
	fuse.archetype_id = &"fuse_probe"
	fuse.scene = PackedScene.new()
	fuse.fuse_range = 2.6
	fuse.fuse_time = 0.05  # too fast to react
	_check(results, "fuse_time below the reaction floor is rejected",
		not fuse.validate().is_empty(), str(fuse.validate()))
	fuse.fuse_time = 0.75
	_check(results, "valid fuse config validates", fuse.validate().is_empty(), str(fuse.validate()))

	var poise := EnemyConfig.new()
	poise.archetype_id = &"poise_probe"
	poise.scene = PackedScene.new()
	poise.poise = -1.0
	_check(results, "negative poise rejected", not poise.validate().is_empty(), "")
	poise.poise = 30.0
	poise.attack_retreat_time = 0.35
	_check(results, "poise + retreat config validates", poise.validate().is_empty(), str(poise.validate()))


# --- Elite behavior hooks ---

static func _elite_hooks(results: Array) -> void:
	_check(results, "vampiric heal ratio is a sane sustain value",
		EliteAffix.VAMPIRIC_HEAL_RATIO > 0.0 and EliteAffix.VAMPIRIC_HEAL_RATIO <= 0.5, "")
	_check(results, "frenzied trigger/cadence constants sane",
		EliteAffix.FRENZIED_HP_TRIGGER > 0.0 and EliteAffix.FRENZIED_HP_TRIGGER < 1.0
		and EliteAffix.FRENZIED_COOLDOWN_MULT > 0.0 and EliteAffix.FRENZIED_COOLDOWN_MULT < 1.0, "")
	var combo := EliteAffix.combine([EliteAffix.VAMPIRIC, EliteAffix.FRENZIED])
	_check(results, "behavior affixes combine like stat affixes",
		float(combo["hp"]) > 1.0 and float(combo["damage"]) > 1.0, str(combo))
