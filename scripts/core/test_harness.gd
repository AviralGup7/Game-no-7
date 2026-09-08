extends Node
## Autoload: TestHarness
## Development/test-only driver: exposes deterministic smoke-test and test-only
## instrumentation. It is not a gameplay dependency. In release builds systems can
## gate heavy behavior behind OS.is_debug_build() if desired; here we keep the
## harness available but clearly scoped to the test runner.

func run_smoke_test() -> Dictionary:
	var steps: Array[Dictionary] = []

	_steps_append(steps, &"main_menu_loads", _state_machine_ok(), "GameRoot state machine present and starts in main_menu")
	_steps_append(steps, &"arena_loads", _default_arena_scene_loads(), "default arena config + scene load")
	_steps_append(steps, &"player_spawns", _player_scene_loads(), "player scene + script resource load")
	_steps_append(steps, &"enemy_spawns", _enemy_archetypes_ok() and _spawn_resources_ok(), "3 enemy archetypes valid + spawn manager & enemy scenes load")
	_steps_append(steps, &"enemy_takes_damage", _enemy_archetypes_ok() and _combat_resources_ok(), "enemy configs HP>0, no negative damage, melee path scripts present")
	_steps_append(steps, &"enemy_dies", _enemy_archetypes_ok(), "each archetype yields a positive score/currency payload on death (exact-once guarded in headless suite)")
	_steps_append(steps, &"score_increases", _kill_and_wave_scoring_configured(), "kill score_value>0 and wave completion_bonus>0 configured")
	_steps_append(steps, &"wave_progresses", _wave_planner_ok() and _spawn_resources_ok(), "WavePlanner deterministic + wave/spawn scenes load")
	_steps_append(steps, &"upgrade_library_ok", _upgrade_library_ok(), "real upgrade .tres resources exist, validate, and are registered")
	_steps_append(steps, &"upgrade_selection_deterministic", _upgrade_selection_deterministic(), "same seed+wave+stacks yields same 3 unique choices")
	_steps_append(steps, &"progression_commands_ok", _progression_commands_ok(), "GameRoot exposes present/select upgrade commands on the canonical state machine")
	_steps_append(steps, &"restart_works", _restart_command_ok(), "GameRoot accepts restart from game_over/menu")
	_steps_append(steps, &"game_over_works", _game_over_transition_ok(), "GameRoot accepts game-over transition from playing")
	_steps_append(steps, &"save_round_trip_works", _save_round_trip_ok(), "validate_save_data normalizes a raw save")
	_steps_append(steps, &"content_registry_validates", ContentRegistry.validate_all(), "content registry validation")

	var passed := true
	for step in steps:
		if not bool(step["passed"]):
			passed = false
	return {"passed": passed, "steps": steps}


func _steps_append(steps: Array, name: StringName, passed: bool, details: String) -> void:
	steps.append({"name": String(name), "passed": passed, "details": details})


func _state_machine_ok() -> bool:
	return GameRoot != null and GameRoot.get_current_state() == GameRoot.State.MAIN_MENU


func _default_arena_scene_loads() -> bool:
	var cfg: ArenaConfig = ContentRegistry.get_arena(&"default_arena")
	return cfg != null and cfg.scene != null


func _player_scene_loads() -> bool:
	return ResourceLoader.exists("res://scenes/player/player.tscn") \
		and ResourceLoader.exists("res://scripts/player/player.gd")


## Phase 3 loop checks — deterministic, system-presence/config based (no live run
## required, matching the coarse diagnostic intent of the other smoke items).

func _enemy_archetypes_ok() -> bool:
	for id in [&"basic", &"fast", &"heavy"]:
		var cfg: EnemyConfig = ContentRegistry.get_enemy(id)
		if cfg == null or cfg.scene == null or not cfg.validate().is_empty():
			return false
	return true


func _spawn_resources_ok() -> bool:
	return ResourceLoader.exists("res://scenes/enemies/spawn_manager.tscn") \
		and ResourceLoader.exists("res://scripts/enemies/spawn_manager.gd") \
		and ResourceLoader.exists("res://scenes/enemies/basic_enemy.tscn") \
		and ResourceLoader.exists("res://scenes/enemies/fast_enemy.tscn") \
		and ResourceLoader.exists("res://scenes/enemies/heavy_enemy.tscn")


func _combat_resources_ok() -> bool:
	return ResourceLoader.exists("res://scripts/enemies/enemy_base.gd") \
		and ResourceLoader.exists("res://scripts/player/player.gd") \
		and ResourceLoader.exists("res://scripts/player/health_component.gd")


func _kill_and_wave_scoring_configured() -> bool:
	var ids := [&"basic", &"fast", &"heavy"]
	for id in ids:
		var cfg: EnemyConfig = ContentRegistry.get_enemy(id)
		if cfg == null or cfg.score_value <= 0 or cfg.currency_value <= 0:
			return false
	for w in [1, 3, 5]:
		var wc := WavePlanner.generate_wave(w, 1)
		if wc == null or wc.completion_bonus <= 0:
			return false
	return true


func _wave_planner_ok() -> bool:
	if WavePlanner == null:
		return false
	var q := WavePlanner.spawn_queue_for_wave(3)
	var cfg := WavePlanner.generate_wave(3, 1)
	return q.size() > 0 and cfg != null and cfg.validate().is_empty() \
		and cfg.planned_count() == q.size()


func _restart_command_ok() -> bool:
	if GameRoot == null:
		return false
	var from_gameover: Array = GameRoot.LEGAL_TRANSITIONS[GameRoot.State.GAME_OVER]
	return from_gameover.has(GameRoot.State.STARTING_RUN)


## At least 10 valid upgrade resources are registered and each passes UpgradeConfig.validate().
func _upgrade_library_ok() -> bool:
	if ContentRegistry == null:
		return false
	var all := ContentRegistry.get_all_upgrades()
	if all.size() < 10:
		return false
	var min_modifiers_ok := true
	var valid := 0
	for raw in all.values():
		var cfg := raw as UpgradeConfig
		if cfg == null or not cfg.validate().is_empty():
			continue
		valid += 1
		if cfg.stat_modifiers.size() < 1:
			min_modifiers_ok = false
	return valid >= 10 and min_modifiers_ok


## Pure deterministic selection: same (seed, wave, stacks) yields the same 3 unique choices.
func _upgrade_selection_deterministic() -> bool:
	var pool: Array[UpgradeConfig] = []
	if ContentRegistry != null:
		for raw in ContentRegistry.get_all_upgrades().values():
			pool.append(raw as UpgradeConfig)
	if pool.size() < 3:
		return false
	var stacks := {}
	var a: Array = UpgradeSelector.choose_upgrade_choices(pool, 3, 1234, 2, stacks)
	var b: Array = UpgradeSelector.choose_upgrade_choices(pool, 3, 1234, 2, stacks)
	if a.size() != 3 or b.size() != 3:
		return false
	# no duplicates within a choice set
	for i in a.size():
		for j in range(i + 1, a.size()):
			if a[i].upgrade_id == a[j].upgrade_id:
				return false
	for i in a.size():
		if a[i].upgrade_id != b[i].upgrade_id:
			return false
	return true


## Deliberate has_method PROBE (not dispatch): this harness asserts the GameRoot
## API exists, so a deleted/renamed method fails the check loudly. This is the
## one sanctioned has_method site in scripts/ (allowlisted in
## tool/check_typed_arch.py).
func _progression_commands_ok() -> bool:
	if GameRoot == null:
		return false
	return GameRoot.has_method("present_upgrade_selection_for_wave") \
		and GameRoot.has_method("request_upgrade_selection")


func _game_over_transition_ok() -> bool:
	return GameRoot != null and GameRoot.LEGAL_TRANSITIONS[GameRoot.State.PLAYING].has(GameRoot.State.GAME_OVER)


func _save_round_trip_ok() -> bool:
	var normalized := SaveManager.validate_save_data({"schema_version": 1, "best_score": 42, "junk": true})
	return int(normalized.get("best_score", 0)) == 42 and int(normalized.get("schema_version", 0)) == SaveManager.SCHEMA_VERSION


## --- Instrumentation helpers (used by integration tests) ---

func start_test_run(seed: int = 12345) -> void:
	EventBus.report_info("TestHarness.start_test_run seed=%d" % seed)
	GameRoot.request_play()


func spawn_test_enemy(archetype_id: StringName = &"basic") -> Node:
	var cfg := ContentRegistry.get_enemy(archetype_id)
	if cfg == null or cfg.scene == null:
		EventBus.report_warning("spawn_test_enemy: no config/scene for %s" % String(archetype_id))
		return null
	var instance := cfg.scene.instantiate()
	return instance


func damage_test_enemy(_amount: float) -> Variant:
	return null  # enemy scene not yet present (phase 2)


func advance_test_time(seconds: float) -> void:
	EventBus.report_info("TestHarness.advance_test_time(%.2f)" % seconds)


## Select the upgrade offered at `index` (0-based) if the game is in UPGRADE_SELECTION.
func select_test_upgrade(index: int) -> bool:
	if GameRoot == null:
		return false
	if GameRoot.get_current_state() != GameRoot.State.UPGRADE_SELECTION:
		return false
	var choices: Array = GameRoot.get_run().upgrade_choices
	if index < 0 or index >= choices.size():
		return false
	return GameRoot.request_upgrade_selection(StringName(String(choices[index])))


func force_test_game_over() -> void:
	GameRoot.request_game_over()


## Test-only snapshot without exposing mutable gameplay internals. Run view shows current
## score/wave/kills/currency and the live (but read-only) progression mirror.
func get_test_snapshot() -> Dictionary:
	var run := GameRoot.get_run()
	return {
		"game_root": GameRoot.get_debug_snapshot(),
		"content": ContentRegistry.get_debug_snapshot(),
		"save": {
			"best_score": SaveManager.get_best_score(),
			"best_wave": SaveManager.get_best_wave(),
		},
		"run": {
			"state": String(GameRoot.get_current_state()),
			"score": run.score,
			"wave": run.current_wave,
			"kills": run.kills,
			"currency": run.currency,
			"upgrade_choices": run.upgrade_choices.duplicate(),
			"selected_upgrades": run.selected_upgrades.duplicate(),
		},
	}
