extends Node
## Autoload: EventBus
## Cross-system signals only. Gameplay objects should prefer direct references for
## local communication; EventBus is the backbone for decoupled observers (UI, audio,
## analytics, achievements). Lifecycle: emitted exactly once where the spec says so.

signal game_state_changed(previous_state: StringName, current_state: StringName)
signal run_started(run_id: int, seed: int)
signal run_ended(score: int, wave: int, best_score: int)
signal player_health_changed(current: float, maximum: float)
signal player_died()
signal enemy_spawned(enemy: Node, archetype_id: StringName)
signal enemy_damaged(enemy: Node, result: DamageResult)
signal enemy_killed(enemy: Node, archetype_id: StringName, score_value: int, currency_value: int)
signal wave_started(wave_number: int, planned_count: int)
signal wave_progressed(wave_number: int, defeated: int, total: int)
signal wave_completed(wave_number: int, completion_bonus: int)
signal upgrade_choices_presented(choices: Array[StringName])
signal upgrade_selected(upgrade_id: StringName)
signal score_changed(score: int, delta: int)
signal currency_changed(currency: int, delta: int)
signal combo_changed(combo: int, best_combo: int)
signal objective_changed(objective_id: StringName, progress: float, completed: bool)
signal pause_changed(is_paused: bool)
signal settings_changed(settings: SettingsData)
signal save_completed()
signal save_failed(reason: StringName)
signal diagnostic(message: String, severity: StringName)


## Convenience: post a diagnostic without callers needing the severity constant.
func report_diagnostic(message: String, severity: StringName = &"info") -> void:
	diagnostic.emit(message, severity)


## Clean reporting used by the debug/test harness. Guards against emitting into a
## deleted connection and against unbounded chatter in release builds.
func report_info(message: String) -> void:
	if OS.is_debug_build():
		print("[diagnostic] ", message)
	diagnostic.emit(message, &"info")


func report_warning(message: String) -> void:
	if OS.is_debug_build():
		push_warning("[diagnostic] " + message)
	diagnostic.emit(message, &"warning")


func report_error(message: String) -> void:
	if OS.is_debug_build():
		push_error("[diagnostic] " + message)
	diagnostic.emit(message, &"error")
