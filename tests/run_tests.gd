extends SceneTree
## Headless test runner.
##   godot --headless --path . --import          (first run only)
##   godot --headless --path . --script res://tests/run_tests.gd
## Returns exit code 0 only when every unit suite plus the live-loop integrations
## (combat, progression, spawn-accounting) pass.
##
## Pure unit suites run synchronously in _initialize(). Node-based integration tests
## are deferred to _process() because nodes added during _initialize() are not yet
## inside the live tree (global transforms return identity there), which would make
## positional/spatial assertions invalid.

const UNIT_SUITES := [
	"res://tests/unit/test_save.gd",
	"res://tests/unit/test_combat.gd",
	"res://tests/unit/test_configs.gd",
	"res://tests/unit/test_scoring.gd",
	"res://tests/unit/test_waves.gd",
	"res://tests/unit/test_combo.gd",
	"res://tests/unit/test_upgrades.gd",
	"res://tests/unit/test_upgrade_selection.gd",
	"res://tests/unit/test_progression.gd",
]

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _failures: Array[String] = []
var _total := 0
var _integration_run := false


func _initialize() -> void:
	# Unit suites are pure (no nodes) -> safe to run immediately.
	for path in UNIT_SUITES:
		var script: GDScript = load(path)
		if script == null:
			_failures.append("Could not load suite: %s" % path)
			_total += 1
			continue
		var cases: Array = script.call("suite")
		for c in cases:
			_total += 1
			if not bool(c.get("passed", false)):
				_failures.append("%s :: %s — %s" % [path.get_file(), str(c.get("name", "")), str(c.get("why", ""))])


func _process(_delta: float) -> bool:
	if _integration_run:
		return false
	_integration_run = true
	# Deferred to the first live frame so Node3D children are truly inside the tree.
	var combat := _run_combat_integration()
	_consume(combat, "combat")

	# Live-loop integrations need the autoload singletons (GameRoot / EventBus /
	# ContentRegistry / AudioManager). If they are not present in this headless context,
	# report a clear environment failure rather than silently skipping the assertions.
	if _autoload(&"GameRoot") != null and _autoload(&"EventBus") != null \
			and _autoload(&"ContentRegistry") != null:
		var progression := _run_progression_integration()
		_consume(progression, "progression")
		var spawn := _run_spawn_accounting_integration()
		_consume(spawn, "spawn")
	else:
		_failures.append("integration :: autoload context unavailable — live-loop tests could not run")
		_total += 1

	print("========================================")
	print("GDScript tests: %d total, %d failed" % [_total, _failures.size()])
	for f in _failures:
		print("  FAIL  " + f)
	print("========================================")
	quit(0 if _failures.is_empty() else 1)
	return false


func _consume(results: Array, prefix: String) -> void:
	for c in results:
		_total += 1
		if not bool(c.get("passed", false)):
			_failures.append("%s :: %s — %s" % [prefix, str(c.get("name", "")), str(c.get("why", ""))])


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


## Deterministic combat integration: real HealthComponent damage/invuln/death +
## pure arc target query, using injected fake-clock time. No physics or audio needed.
func _run_combat_integration() -> Array:
	var results: Array = []

	var clock := FakeClock.new()
	var hp := HealthComponent.new()
	root.add_child(hp)
	hp.set_time_source(clock.now)
	hp.reset(100.0)

	# Damage applies and reduces health.
	var dmg := DamagePayload.new()
	dmg.amount = 30.0
	var r1 := hp.take_damage(dmg)
	results.append({
		"name": "damage applies 30/100 -> 70",
		"passed": r1.accepted and is_equal_approx(hp.current_health, 70.0) and not r1.target_died,
		"why": "current=%f accepted=%s" % [hp.current_health, str(r1.accepted)],
	})

	# Invalid payloads rejected safely.
	var bad := DamagePayload.new()
	bad.amount = -5.0
	var rb := hp.take_damage(bad)
	results.append({
		"name": "negative damage rejected (invalid_payload)",
		"passed": not rb.accepted and rb.ignored_reason == DamageResult.IGNORE_INVALID_PAYLOAD,
		"why": "",
	})

	# Invulnerability window ignores damage.
	hp.set_invulnerable(1.0)
	var inv := hp.take_damage(dmg)
	results.append({
		"name": "invulnerable damage ignored",
		"passed": not inv.accepted and inv.ignored_reason == DamageResult.IGNORE_INVULNERABLE,
		"why": "",
	})

	# Healing caps at max.
	hp.heal(500.0)
	results.append({
		"name": "heal caps at max health",
		"passed": is_equal_approx(hp.current_health, 100.0),
		"why": "",
	})

	# Advance past the 1s invulnerability window so the next hit can land.
	clock.advance(2.0)

	# Lethal damage -> death exactly once.
	# Note: GDScript lambdas capture outer locals by value, so a mutable Array is
	# used as the counter instead of an int.
	var lethal := DamagePayload.new()
	lethal.amount = 1000.0
	var death_count: Array[int] = [0]
	hp.died.connect(func() -> void: death_count[0] += 1)
	var rl := hp.take_damage(lethal)
	hp.take_damage(lethal)  # duplicate damage on a corpse
	results.append({
		"name": "lethal damage dies once, duplicate ignored",
		"passed": rl.target_died and death_count[0] == 1 and hp.is_dead(),
		"why": "died=%d" % death_count[0],
	})
	root.remove_child(hp)
	hp.queue_free()

	# Pure arc query against fake Node3D targets (added to tree first so that
	# global_position reflects their positions).
	var t1 := Node3D.new()
	root.add_child(t1)
	t1.global_position = Vector3(0, 0, -2.0)  # in front, in range
	var t2 := Node3D.new()
	root.add_child(t2)
	t2.global_position = Vector3(0, 0, -8.0)  # too far
	var t3 := Node3D.new()
	root.add_child(t3)
	t3.global_position = Vector3(0, 0, -1.0)
	var arc_hits := CombatQuery.find_targets_in_arc(Vector3.ZERO, Vector3(0, 0, -1), [t1, t2, t3], 3.0, 45.0)
	results.append({
		"name": "arc query keeps in-range targets only",
		"passed": arc_hits.size() == 2 and t1 in arc_hits and t3 in arc_hits and t2 not in arc_hits,
		"why": "hits=%d" % arc_hits.size(),
	})
	for n in [t1, t2, t3]:
		root.remove_child(n)
		n.queue_free()
	return results


## Live-loop progression integration (deterministic, no physics/timers): drives the REAL
## GameRoot canonical state machine + a real Player scene + ProgressionComponent through
## the menu → run → (simulated completed wave) → upgrade selection → apply → finalize →
## restart flow, recording an event trace and asserting exactly-once + no-leak ordering.
func _run_progression_integration() -> Array:
	var results: Array = []
	var trace: Array = []
	var counts := {}
	var rec := func(ev: String) -> void:
		trace.append(ev)
		counts[ev] = int(counts.get(ev, 0)) + 1

	EventBus.run_started.connect(func(_id: int, _s: int) -> void: rec("run_started"))
	EventBus.upgrade_choices_presented.connect(func(_c: Array) -> void: rec("upgrade_choices_presented"))
	EventBus.upgrade_selected.connect(func(_u: StringName) -> void: rec("upgrade_selected"))
	EventBus.run_ended.connect(func(_a: int, _b: int, _c: int) -> void: rec("run_ended"))

	if GameRoot.get_current_state() != GameRoot.State.MAIN_MENU:
		results.append({"name": "starts from main_menu", "passed": false,
			"why": "state=%s" % str(GameRoot.get_current_state())})
		return results
	results.append({"name": "starts from main_menu", "passed": true, "why": ""})

	# menu -> start run
	GameRoot.request_play()
	results.append({"name": "run starts into PLAYING with fresh zeroed run state",
		"passed": GameRoot.get_current_state() == GameRoot.State.PLAYING \
			and GameRoot.get_run().score == 0 and GameRoot.get_run().kills == 0 \
			and GameRoot.get_run().combo == 0 and GameRoot.get_run().upgrade_choices.is_empty(),
		"why": "state=%s" % str(GameRoot.get_current_state())})
	results.append({"name": "run_started emitted once", "passed": int(counts.get("run_started", 0)) == 1, "why": ""})

	# Real player + real progression gameplay wiring (fresh)
	var player := PLAYER_SCENE.instantiate()
	root.add_child(player)
	player.call("reset_for_new_run", Transform3D.IDENTITY)
	GameRoot.set_active_player(player)

	# Vitality: 100/100 full -> +20 max -> 120/120
	var health := player.get_node_or_null("HealthComponent")
	var hp_before := health.call("get_current")
	var vitality_ok := bool(player.call("apply_upgrade", &"vitality"))
	var max_hp := 0.0
	if health != null and health.has_method("get_debug_snapshot"):
		max_hp = float((health.call("get_debug_snapshot") as Dictionary).get("max_health", 0.0))
	var cur_hp := health.call("get_current")
	results.append({"name": "vitality on real player: 100/100 full -> 120/120",
		"passed": vitality_ok and is_equal_approx(hp_before, 100.0) and is_equal_approx(max_hp, 120.0) and is_equal_approx(cur_hp, 120.0),
		"why": "before=%f max=%f cur=%f" % [hp_before, max_hp, cur_hp]})

	# Swift: real CharacterController move_speed 6 -> 6.9
	player.call("reset_for_new_run", Transform3D.IDENTITY)
	var cc := player.get_node_or_null("CharacterController")
	var base_speed := float(cc.get("move_speed"))
	var swift_ok := bool(player.call("apply_upgrade", &"swift"))
	var new_speed := float(cc.get("move_speed"))
	results.append({"name": "swift on real player raises CharacterController move_speed 6 -> 6.9",
		"passed": swift_ok and is_equal_approx(base_speed, 6.0) and is_equal_approx(new_speed, 6.9),
		"why": "base=%f now=%f" % [base_speed, new_speed]})

	# Reset for the actual run-flow check below.
	player.call("reset_for_new_run", Transform3D.IDENTITY)

	# completed wave -> deterministic upgrade selection presented (exactly 3, distinct, legal)
	var presented := GameRoot.present_upgrade_selection_for_wave(2)
	var choices: Array = GameRoot.get_run().upgrade_choices
	var distinct := _distinct_ids(choices)
	var all_legal := _all_choices_legal(choices, 2, player)
	results.append({"name": "present 3 distinct legal upgrades and enter UPGRADE_SELECTION",
		"passed": presented and choices.size() == 3 and distinct and all_legal \
			and GameRoot.get_current_state() == GameRoot.State.UPGRADE_SELECTION,
		"why": "n=%d" % choices.size()})
	results.append({"name": "upgrade_choices_presented emitted once",
		"passed": int(counts.get("upgrade_choices_presented", 0)) == 1, "why": ""})

	# invalid / un-offered selections are rejected and do not leave the state
	var reject1 := GameRoot.request_upgrade_selection(&"not_offered")
	var some_real := ContentRegistry.get_all_upgrades().keys()
	var unoffered := &"none"
	for k in some_real:
		if k not in choices:
			unoffered = StringName(String(k))
			break
	var reject2 := GameRoot.request_upgrade_selection(unoffered)
	results.append({"name": "un-offered / arbitrary ids rejected while in UPGRADE_SELECTION",
		"passed": not reject1 and not reject2 \
			and GameRoot.get_current_state() == GameRoot.State.UPGRADE_SELECTION \
			and int(counts.get("upgrade_selected", 0)) == 0,
		"why": ""})

	# valid selection applies to progression and returns to PLAYING
	var chosen := StringName(String(choices[0]))
	var prog := player.get_node_or_null("ProgressionComponent")
	var applied := GameRoot.request_upgrade_selection(chosen)
	var stack_after := prog.call("get_stack_count", chosen) if prog != null else 0
	var mods_nonempty := false
	if prog != null and prog.has_method("get_modifier_snapshot"):
		mods_nonempty = not (prog.call("get_modifier_snapshot") as Dictionary).is_empty()
	var run_state_mirror := GameRoot.get_run().selected_upgrades.has(chosen)
	results.append({"name": "valid selection applies once and returns to PLAYING",
		"passed": applied and GameRoot.get_current_state() == GameRoot.State.PLAYING \
			and stack_after == 1 and mods_nonempty and run_state_mirror \
			and GameRoot.get_run().upgrade_choices.is_empty(),
		"why": ""})
	results.append({"name": "upgrade_selected emitted once (no dup)",
		"passed": int(counts.get("upgrade_selected", 0)) == 1, "why": ""})

	# game over finalizes exactly once
	GameRoot.request_game_over()
	var ended_once := int(counts.get("run_ended", 0)) == 1
	GameRoot.request_game_over()  # repeated request must not double-finalize
	var ended_still := int(counts.get("run_ended", 0)) == 1
	results.append({"name": "game over finalizes exactly once",
		"passed": GameRoot.get_current_state() == GameRoot.State.GAME_OVER and ended_once and ended_still,
		"why": ""})

	# restart from game over -> run state fully cleared (no leak)
	GameRoot.request_play()
	var run := GameRoot.get_run()
	results.append({"name": "restart clears score/currency/kills/combo/choices/modifiers",
		"passed": GameRoot.get_current_state() == GameRoot.State.PLAYING \
			and run.score == 0 and run.currency == 0 and run.kills == 0 and run.combo == 0 \
			and run.upgrade_choices.is_empty() and run.selected_upgrades.is_empty() \
			and run.active_modifiers.is_empty(),
		"why": ""})
	player.call("reset_for_new_run", Transform3D.IDENTITY)
	var prog_after := player.get_node_or_null("ProgressionComponent")
	var prog_empty := true
	if prog_after != null and prog_after.has_method("get_upgrade_stack_snapshot"):
		prog_empty = (prog_after.call("get_upgrade_stack_snapshot") as Dictionary).is_empty()
	results.append({"name": "restart resets the player's runtime progression",
		"passed": prog_empty, "why": ""})
	results.append({"name": "run_started emitted again on restart",
		"passed": int(counts.get("run_started", 0)) == 2, "why": ""})

	# Event ordering sanity
	var ordered := _is_subsequence([&"run_started", &"upgrade_choices_presented", &"upgrade_selected", &"run_ended", &"run_started"], trace)
	results.append({"name": "event ordering run_started < choices < selected < run_ended < run_started",
		"passed": ordered, "why": "trace=%s" % str(trace)})

	root.remove_child(player)
	player.queue_free()
	return results


func _distinct_ids(choices: Array) -> bool:
	var seen := {}
	for c in choices:
		var k := String(c)
		if seen.has(k):
			return false
		seen[k] = true
	return true


func _all_choices_legal(choices: Array, wave: int, player: Node) -> bool:
	var prog := player.get_node_or_null("ProgressionComponent")
	var stacks: Dictionary = {}
	if prog != null and prog.has_method("get_upgrade_stack_snapshot"):
		stacks = prog.call("get_upgrade_stack_snapshot")
	for raw in choices:
		var cfg := ContentRegistry.get_upgrade(StringName(String(raw)))
		if cfg == null or not UpgradeSelector.is_eligible(cfg, wave, stacks):
			return false
	return true


func _is_subsequence(needle: Array, haystack: Array) -> bool:
	var i := 0
	for ev in haystack:
		if i < needle.size() and ev == needle[i]:
			i += 1
	return i == needle.size()


## Spawn-accounting integration: a permanently-failing spawn is retried up to a bound and
## then counted as FAILED — never as a defeat and never under-filling the wave count.
func _run_spawn_accounting_integration() -> Array:
	var results: Array = []
	var sm := SpawnManager.new()
	root.add_child(sm)
	var host := Node3D.new()
	root.add_child(host)
	sm.configure(host, host, host, 1)  # arena+player present -> configured; enemy is bogus
	sm.queue_wave([&"ghost_missing"], 1, 0.5, 5)
	results.append({"name": "plan holds 1 pending 1 before spawn",
		"passed": sm.get_planned_count() == 1 and sm.get_pending_count() == 1,
		"why": "planned=%d pending=%d" % [sm.get_planned_count(), sm.get_pending_count()]})

	var attempts := 0
	while sm.get_pending_count() > 0 and attempts < 200:
		sm.force_spawn_one()
		attempts += 1
	results.append({"name": "bounded retries then FAILED (never a defeat, count preserved)",
		"passed": sm.get_failed_count() == 1 and sm.get_defeated_count() == 0 \
			and sm.get_pending_count() == 0 and sm.get_spawned_count() == 0,
		"why": "failed=%d defeated=%d spawned=%d attempts=%d" \
			% [sm.get_failed_count(), sm.get_defeated_count(), sm.get_spawned_count(), attempts]})
	results.append({"name": "failure retry is bounded (no infinite loop)",
		"passed": attempts <= 40, "why": "attempts=%d" % attempts})

	sm.clear()
	root.remove_child(sm)
	sm.queue_free()
	root.remove_child(host)
	host.queue_free()
	return results
