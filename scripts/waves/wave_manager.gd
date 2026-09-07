class_name WaveManager
extends Node

## Orchestrates a run's wave progression. Generation is delegated to the deterministic
## WavePlanner; authored overrides come from ContentRegistry wave resources; physical
## spawning/accounting is delegated to a SpawnManager (which is authoritative for
## planned/pending/active/defeated/failed). This manager owns the phase state
## (Preparing -> Spawning -> Combat -> Completed -> [Upgrade/Transition] -> next),
## completion bonuses (routed through GameRoot, exactly-once), the inter-wave break,
## mutator selection/announcement, and the adaptive DifficultyDirector feed.
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
## Active mutators for the current wave (ids).
var _active_mutators: Array[StringName] = []
var _director := DifficultyDirector.new()
var _director_wired := false


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
	_active_mutators.clear()
	_wire_director()
	_launch_next_wave()


func stop() -> void:
	_active = false
	_awaiting_upgrade = false
	_phase = PHASE_PREPARING
	_active_mutators.clear()
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


func get_active_mutators() -> Array[StringName]:
	return _active_mutators.duplicate()


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


## Resolve the wave config: authored override wins, else the deterministic planner.
func _wave_config(wave_number: int) -> WaveConfig:
	if ContentRegistry != null and ContentRegistry.has_authored_wave(wave_number):
		var authored := ContentRegistry.get_wave(wave_number)
		if authored != null:
			return authored
	return WavePlanner.generate_wave(wave_number, _seed)


## Resolve the flat spawn queue: authored entries expanded (weighted shuffle), else
## the planner queue (extended with new archetypes from wave 6).
func _wave_queue(wave_number: int, cfg: WaveConfig) -> Array[StringName]:
	if ContentRegistry != null and ContentRegistry.has_authored_wave(wave_number):
		return WavePlanner.expand_authored_entries(cfg, _seed)
	return WavePlanner.extended_queue_for_wave(wave_number, _seed)


func _launch_wave(wave_number: int) -> void:
	if _spawn == null:
		EventBus.report_warning("WaveManager has no spawn manager")
		return
	var cfg := _wave_config(wave_number)
	var queue := _wave_queue(wave_number, cfg)
	_apply_director_count_nudge(queue)
	if queue.is_empty():
		EventBus.report_warning("Wave %d has an empty plan; stopping" % wave_number)
		stop()
		return
	_planned_count = queue.size()
	_wave_completed_flag = false
	_phase = PHASE_SPAWNING
	_last_delay = cfg.transition_delay
	_resolve_mutators(wave_number, cfg)
	_push_scaling_to_spawner(wave_number, cfg)
	_spawn.queue_wave(queue, wave_number, cfg.spawn_interval, cfg.maximum_simultaneous_enemies)
	GameRoot.record_current_wave(wave_number)
	EventBus.wave_started.emit(wave_number, _planned_count)
	EventBus.report_info("Wave %d started (%d planned)%s" % [wave_number, _planned_count,
		(" [" + WaveMutators.banner_text(_active_mutators) + "]") if not _active_mutators.is_empty() else ""])


func _resolve_mutators(wave_number: int, cfg: WaveConfig) -> void:
	_active_mutators.clear()
	# Authored waves declare their own; generated waves roll (director may veto).
	var declared: Array = []
	if cfg != null:
		declared = cfg.arena_modifier_ids.duplicate()
	if declared.is_empty():
		if _director.suggest_breather():
			EventBus.report_info("Director grants a breather: no mutators for wave %d" % wave_number)
		else:
			for m in WaveMutators.roll_for_wave(wave_number, _seed):
				declared.append(m)
			if _director.suggest_spice() and declared.size() < 2:
				var extra := WaveMutators.roll_for_wave(wave_number + 100, _seed)
				for m in extra:
					if m not in declared:
						declared.append(m)
						break
	for raw in declared:
		var id := StringName(String(raw))
		if WaveMutators.is_known(id) and id not in _active_mutators:
			_active_mutators.append(id)
			EventBus.wave_mutator_applied.emit(id, wave_number)


func _push_scaling_to_spawner(wave_number: int, _cfg: WaveConfig) -> void:
	var scalars := WavePlanner.calculate_difficulty_scalars(wave_number)
	var director_mods := _director.next_wave_multipliers()
	# Director nudges fold into the difficulty scalars (bounded ±25% by design).
	scalars["hp"] = float(scalars["hp"]) * float(director_mods["hp_mult"])
	scalars["damage"] = float(scalars["damage"]) * float(director_mods["damage_mult"])
	scalars["speed"] = float(scalars["speed"]) * float(director_mods["speed_mult"])
	if _spawn.has_method("set_difficulty_scalars"):
		_spawn.call("set_difficulty_scalars", scalars)
	# Mutators ride the dedicated wave-modifier channel (plus director elites).
	var mods := WaveMutators.combine(_active_mutators)
	mods["elite_bonus"] = float(mods.get("elite_bonus", 0.0)) + float(director_mods.get("elite_bonus", 0.0))
	if _spawn.has_method("set_wave_modifiers"):
		_spawn.call("set_wave_modifiers", mods)


func _apply_director_count_nudge(queue: Array[StringName]) -> void:
	var bonus := int(_director.next_wave_multipliers().get("count_bonus", 0))
	if bonus > 0:
		for i in range(bonus):
			if not queue.is_empty():
				queue.append(queue[i % queue.size()])
	elif bonus < 0:
		for i in range(mini(-bonus, queue.size() - 1)):
			queue.pop_back()


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
	var cfg := _wave_config(_current_wave)
	var bonus := cfg.completion_bonus
	# Completion bonus is centralized in GameRoot (exactly-once via EventBus.wave_completed).
	EventBus.wave_completed.emit(_current_wave, bonus)
	EventBus.report_info("Wave %d completed (bonus %d)" % [_current_wave, bonus])
	_tick_director_clock()
	if cfg.upgrade_after_completion:
		# Open a deterministic upgrade selection; GameRoot routes PLAYING -> UPGRADE_SELECTION.
		if GameRoot.present_upgrade_selection_for_wave(_current_wave):
			_awaiting_upgrade = true
			EventBus.report_info("Awaiting upgrade selection before wave %d" % (_current_wave + 1))
			return
		EventBus.report_info("No upgrade to present after wave %d; continuing" % _current_wave)
	# Otherwise, take a short inter-wave break then start the next wave.
	_arm_next_wave_transition()


func _tick_director_clock() -> void:
	if GameRoot != null:
		_director.set_time(GameRoot.get_run().elapsed_seconds)


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


func _wire_director() -> void:
	if _director_wired:
		_director.reset(_player_max_hp())
		return
	_director_wired = true
	_director.reset(_player_max_hp())
	if not EventBus.enemy_killed.is_connected(_on_director_kill):
		EventBus.enemy_killed.connect(_on_director_kill)


func _player_max_hp() -> float:
	if GameRoot != null and GameRoot.get_active_player() != null:
		var hp := (GameRoot.get_active_player() as Node).get_node_or_null("HealthComponent")
		if hp != null and hp.has_method("get_max"):
			return maxf(float(hp.call("get_max")), 1.0)
	return 100.0


func _on_director_kill(_enemy: Node, _archetype: StringName, _score: int, _currency: int) -> void:
	if not _active:
		return
	_tick_director_clock()
	_director.record_kill()


## Called by damage observers (Player routes hurt events here via GameRoot in
## future wiring; safe to call directly from UI/debug too).
func record_player_damage(amount: float) -> void:
	if not _active:
		return
	_tick_director_clock()
	_director.record_damage_taken(amount)


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
		"mutators": _active_mutators.duplicate(),
		"director": _director.get_debug_snapshot(),
	}
