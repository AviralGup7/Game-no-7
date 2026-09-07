class_name WaveManager
extends Node

## Orchestrates a run's wave progression. Generation is delegated to the deterministic
## WavePlanner; physical spawning/accounting is delegated to a SpawnManager (which is
## authoritative for planned/pending/active/defeated/failed). This manager owns the phase
## state (Preparing -> Spawning -> Combat -> Completed -> [Upgrade/Transition] -> next),
## completion bonuses (routed through GameRoot, exactly-once) and the inter-wave break.
##
## Progression integration: when a completed wave config sets upgrade_after_completion,
## the manager asks GameRoot to present a deterministic selection and then WAITS — the next
## wave is only launched after the player makes a valid selection (observed as GameRoot
## returning to PLAYING). Waves without an upgrade continue through a short transition
## delay. It never launches the next wave before a required upgrade is selected.

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
## True while an upgrade selection panel is open and the next wave must wait for it.
var _awaiting_upgrade := false


func _ready() -> void:
	_transition_timer = Timer.new()
	_transition_timer.one_shot = true
	_transition_timer.timeout.connect(_on_transition_done)
	add_child(_transition_timer)
	EventBus.game_state_changed.connect(_on_game_state_changed)


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
	_awaiting_upgrade = false
	_launch_next_wave()


func stop() -> void:
	_active = false
	_awaiting_upgrade = false
	_phase = PHASE_PREPARING
	if _transition_timer != null:
		_transition_timer.stop()


func get_current_wave() -> int:
	return _current_wave


func get_phase() -> StringName:
	return _phase


func is_active() -> bool:
	return _active


func is_awaiting_upgrade() -> bool:
	return _awaiting_upgrade


## Observe the canonical state machine. When the player resolves an upgrade selection
## GameRoot returns to PLAYING; only then may the next wave launch.
func _on_game_state_changed(_previous: StringName, current: StringName) -> void:
	if not _active:
		return
	if current == GameRoot.State.PLAYING and _awaiting_upgrade:
		_awaiting_upgrade = false
		EventBus.report_info("Upgrade selection resolved; launching next wave")
		_launch_next_wave()


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
	# Completion bonus is centralized in GameRoot (exactly-once via EventBus.wave_completed).
	EventBus.wave_completed.emit(_current_wave, bonus)
	EventBus.report_info("Wave %d completed (bonus %d)" % [_current_wave, bonus])
	if cfg.upgrade_after_completion:
		# Open a deterministic upgrade selection; GameRoot routes PLAYING -> UPGRADE_SELECTION.
		if GameRoot.present_upgrade_selection_for_wave(_current_wave):
			_awaiting_upgrade = true
			EventBus.report_info("Awaiting upgrade selection before wave %d" % (_current_wave + 1))
			return
		EventBus.report_info("No upgrade to present after wave %d; continuing" % _current_wave)
	# Otherwise, take a short inter-wave break then start the next wave.
	_arm_next_wave_transition()


## PLAYING -> WAVE_TRANSITION, brief delay, then PLAYING + next wave launch.
func _arm_next_wave_transition() -> void:
	if _phase == PHASE_TRANSITION:
		return
	_phase = PHASE_TRANSITION
	GameRoot.begin_wave_transition()
	if _transition_timer != null:
		_transition_timer.wait_time = maxf(_last_delay, 0.1)
		_transition_timer.start()


func _on_transition_done() -> void:
	if not _active:
		return
	GameRoot.end_wave_transition()
	_launch_next_wave()


## Authoritative defeated count (owned by the SpawnManager, event-driven).
func get_defeated_count() -> int:
	if _spawn == null:
		return 0
	return _spawn.get_defeated_count()


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
		"awaiting_upgrade": _awaiting_upgrade,
		"seed": _seed,
	}
