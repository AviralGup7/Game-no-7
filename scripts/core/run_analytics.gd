extends Node
## Autoload: RunAnalytics
## Records local, offline-only run statistics for UI, balancing, debugging and
## achievements. Never requires network access.

var _session_runs: Array[Dictionary] = []
var _live := {
	"kills": 0,
	"elites": 0,
	"bosses": 0,
	"damage_taken": 0.0,
	"waves": 0,
	"lock_ons": 0,
	"errors": 0,
}


func _ready() -> void:
	EventBus.report_info("RunAnalytics ready (offline only)")
	if EventBus.enemy_killed.is_connected(_on_kill):
		return
	EventBus.enemy_killed.connect(_on_kill)
	EventBus.boss_slain.connect(_on_boss)
	EventBus.wave_completed.connect(_on_wave)
	EventBus.player_died.connect(_on_player_died)
	EventBus.run_started.connect(_on_run_started)
	EventBus.enemy_spawned.connect(_on_spawn)


func _on_run_started(_id: int, _seed: int) -> void:
	_live = {"kills": 0, "elites": 0, "bosses": 0, "damage_taken": 0.0, "waves": 0, "lock_ons": 0, "errors": 0}
	Narrator.reset_run()


func _on_spawn(_enemy: Node, archetype_id: StringName) -> void:
	Narrator.note_enemy_spawned(archetype_id)


func _on_kill(_enemy: Node, _archetype: StringName, _score: int, _currency: int) -> void:
	_live["kills"] = int(_live["kills"]) + 1
	if _enemy is EnemyBase and (_enemy as EnemyBase).is_elite():
		_live["elites"] = int(_live["elites"]) + 1


func _on_boss(_id: StringName) -> void:
	_live["bosses"] = int(_live["bosses"]) + 1


func _on_wave(_wave: int, _bonus: int) -> void:
	_live["waves"] = int(_live["waves"]) + 1


func _on_player_died() -> void:
	pass


func note_lock_on() -> void:
	_live["lock_ons"] = int(_live["lock_ons"]) + 1


func note_damage_taken(amount: float) -> void:
	if is_finite(amount) and amount > 0.0:
		_live["damage_taken"] = float(_live["damage_taken"]) + amount


## Called by DebugErrorHandler for every real error (any flag state; self-tests
## excluded). The count rides the live row into record_run_end, so run-end rows
## say which runs hit errors. Pure increment — it must never emit, or the error
## trap recurses.
func note_error() -> void:
	_live["errors"] = int(_live["errors"]) + 1


func get_live() -> Dictionary:
	return _live.duplicate()


func record_run_end(summary: Dictionary) -> void:
	var row := summary.duplicate()
	for k in _live:
		if not row.has(k):
			row[k] = _live[k]
	_session_runs.append(row)
	if _session_runs.size() > 64:
		_session_runs.pop_front()


func get_lifetime() -> Dictionary:
	return SaveManager.get_save_dict().get("lifetime_statistics", {})


func get_session_totals() -> Dictionary:
	var runs := 0
	var kills := 0
	var seconds := 0.0
	var bosses := 0
	var errors := 0
	for run in _session_runs:
		runs += 1
		kills += int(run.get("kills", 0))
		seconds += float(run.get("elapsed_seconds", 0.0))
		bosses += int(run.get("bosses", 0))
		errors += int(run.get("errors", 0))
	return {
		"session_runs": runs,
		"session_kills": kills,
		"session_time_seconds": seconds,
		"session_bosses": bosses,
		"session_errors": errors,
	}


func get_debug_snapshot() -> Dictionary:
	return {
		"session_runs": _session_runs.size(),
		"session_totals": get_session_totals(),
		"lifetime": get_lifetime(),
		"live": get_live(),
	}
