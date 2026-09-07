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
	_steps_append(steps, &"enemy_spawns", false, "pending: phase 3 (enemy spawning)")
	_steps_append(steps, &"enemy_takes_damage", false, "pending: phase 2 (combat)")
	_steps_append(steps, &"enemy_dies", false, "pending: phase 2 (combat)")
	_steps_append(steps, &"score_increases", false, "pending: phase 4 (scoring loop)")
	_steps_append(steps, &"wave_progresses", false, "pending: phase 3 (wave system)")
	_steps_append(steps, &"upgrade_appears", false, "pending: phase 4 (progression)")
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


func _restart_command_ok() -> bool:
	if GameRoot == null:
		return false
	var from_gameover: Array = GameRoot.LEGAL_TRANSITIONS[GameRoot.State.GAME_OVER]
	return from_gameover.has(GameRoot.State.STARTING_RUN)


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


func select_test_upgrade(_index: int) -> bool:
	return false


func force_test_game_over() -> void:
	GameRoot.request_game_over()


func get_test_snapshot() -> Dictionary:
	return {
		"game_root": GameRoot.get_debug_snapshot(),
		"content": ContentRegistry.get_debug_snapshot(),
		"save": {
			"best_score": SaveManager.get_best_score(),
			"best_wave": SaveManager.get_best_wave(),
		},
	}
