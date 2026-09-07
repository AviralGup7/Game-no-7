class_name WaveManager
extends Node

## Orchestrates a run's wave progression. Generation is delegated to the deterministic
## WavePlanner; physical spawning is delegated to a SpawnManager. This manager owns the
## phase state (Preparing -> Spawning -> Combat -> Completed -> Transition -> next),
## planned/defeated accounting, completion bonus and the inter-wave GameRoot transition.
## It does not own score/saves directly — bonuses are routed through GameRoot so scoring
## stays centralized and exactly-once.

const PHASE_PREPARING := &"preparing"
const PHASE_SPAWNING := &"spawning"
const PHASE_COMBAT := &"combat"
const PHASE_COMPLETED := &"completed"
const PHASE_TRANSITION := &"transition"

var _spawn: SpawnManager = null
var _seed := 0
var _active := false
var _current_wave := 0
var _planned_count := 0
var _phase: StringName = PHASE_PREPARING
var _transition_timer: Timer = null
var _last_delay := 2.5
var _wave_completed_flag := false


func _ready() -> void:
	_transition_timer = Timer.new()
	_transition_timer.one_shot = true
	_transition_timer.timeout.connect(_on_transition_done)
	add_child(_transition_timer)


func setup(spawn_manager: SpawnManager) -> void:
	_spawn = spawn_manager
	if _spawn != null and not _spawn.all_cleared.is_connected(_on_all_cleared):
		_spawn.all_cleared.connect(_on_all_cleared)


func start_run(seed: int) -> void:
	_active = true
	_seed = seed
	_current_wave = 0
	_planned_count = 0
	_phase = PHASE_PREPARING
	_launch_next_wave()


func stop() -> void:
	_active = false
	_phase = PHASE_PREPARING
	if _transition_timer != null:
		_transition_timer.stop()


func get_current_wave() -> int:
	return _current_wave


func get_phase() -> StringName:
	return _phase


func is_active() -> bool:
	return _active


func _launch_next_wave() -> void:
	if not _active:
		return
	_current_wave += 1
	_launch_wave(_current_wave)


func _launch_wave(wave_number: int) -> void:
	if _spawn == null:
		EventBus.report_warning("WaveManager has no spawn manager")
		return
	var cfg := WavePlanner.generate_wave(wave_number, _seed)
	var queue := WavePlanner.spawn_queue_for_wave(wave_number)
	if queue.is_empty():
		EventBus.report_warning("Wave %d has an empty plan; stopping" % wave_number)
		stop()
		return
	_planned_count = queue.size()
	_wave_completed_flag = false
	_phase = PHASE_SPAWNING
	_last_delay = cfg.transition_delay
	var scalars := WavePlanner.calculate_difficulty_scalars(wave_number)
	if _spawn.has_method("set_difficulty_scalars"):
		_spawn.call("set_difficulty_scalars", scalars)
	_spawn.queue_wave(queue, wave_number, cfg.spawn_interval, cfg.maximum_simultaneous_enemies)
	GameRoot.record_current_wave(wave_number)
	EventBus.wave_started.emit(wave_number, _planned_count)
	EventBus.report_info("Wave %d started (%d planned)" % [wave_number, _planned_count])


func _on_all_cleared() -> void:
	if not _active:
		return
	if _phase not in [PHASE_SPAWNING, PHASE_COMBAT]:
		return
	_complete_current_wave()


func _complete_current_wave() -> void:
	if _wave_completed_flag:
		return
	_wave_completed_flag = true
	_phase = PHASE_COMPLETED
	var cfg := WavePlanner.generate_wave(_current_wave, _seed)
	var bonus := cfg.completion_bonus
	# Scoring is centralized in GameRoot via the wave_completed signal so it stays
	# exactly-once (GameRoot._on_wave_completed awards it); this manager only announces.
	EventBus.wave_completed.emit(_current_wave, bonus)
	EventBus.report_info("Wave %d completed (bonus %d)" % [_current_wave, bonus])
	# Move through the GameRoot state machine for a clean inter-wave break.
	GameRoot.begin_wave_transition()
	_phase = PHASE_TRANSITION
	if _transition_timer != null:
		_transition_timer.wait_time = maxf(_last_delay, 0.1)
		_transition_timer.start()


func _on_transition_done() -> void:
	if not _active:
		return
	GameRoot.end_wave_transition()
	_launch_next_wave()


## Counts for observers / debug (kept cheap; the spawn manager is authoritative on
## pending/active).
func get_defeated_count() -> int:
	if _spawn == null:
		return 0
	if _phase in [PHASE_SPAWNING, PHASE_COMBAT]:
		var pending := _spawn.get_pending_count()
		var active := _spawn.get_active_count()
		return maxi(_planned_count - pending - active, 0)
	return _planned_count


func get_debug_snapshot() -> Dictionary:
	var d := {}
	if _spawn != null:
		d = _spawn.get_debug_snapshot()
	return {
		"phase": String(_phase),
		"current_wave": _current_wave,
		"planned_count": _planned_count,
		"defeated_count": get_defeated_count(),
		"pending_count": d.get("pending", 0) if _spawn != null else 0,
		"active_count": d.get("active", 0) if _spawn != null else 0,
		"active": _active,
		"seed": _seed,
	}
