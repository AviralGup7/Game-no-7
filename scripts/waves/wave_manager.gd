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
## The current wave's folded rules: plan scalars × director nudge × mutators, plus the elite bonus,
## volatile chance, status stamp, severity and count adjustment. Built ONCE per wave by
## `_fold_modifiers` and read by the spawner push, the banner and the run mirror. It replaces three
## Dictionary hand-offs that each re-implemented (or, five times over, forgot) the same keys.
var _wave_mods: WaveModifiers = WaveModifiers.neutral()
## Forced mutator set (daily challenge): when non-empty, replaces the normal
## resolve every wave so the whole run shares one deterministic pair.
var _forced_mutators: Array[StringName] = []
var _director := DifficultyDirector.new()
var _director_wired := false
var _wired_health: HealthComponent = null
var _bus := EventBindings.new()


func _ready() -> void:
	_transition_timer = Timer.new()
	_transition_timer.one_shot = true
	_transition_timer.timeout.connect(_on_transition_done)
	add_child(_transition_timer)
	_bus.bind(EventBus.game_state_changed, _on_game_state_changed)


func setup(spawn_manager: SpawnManager) -> void:
	_spawn = spawn_manager
	if _spawn != null and not _spawn.all_cleared.is_connected(_on_all_cleared):
		_spawn.all_cleared.connect(_on_all_cleared)


func set_forced_mutators(ids: Array[StringName]) -> void:
	_forced_mutators = ids.duplicate()


func start_run(run_seed: int) -> void:
	_active = true
	_seed = run_seed
	_current_wave = 0
	_planned_count = 0
	_phase = PHASE_PREPARING
	_awaiting_upgrade = false
	_active_mutators.clear()
	_wave_mods = WaveModifiers.neutral()
	_wire_director()
	_launch_next_wave()


func stop() -> void:
	_active = false
	_awaiting_upgrade = false
	_phase = PHASE_PREPARING
	_active_mutators.clear()
	_wave_mods = WaveModifiers.neutral()
	if _transition_timer != null:
		_transition_timer.stop()
	if _wired_health != null and is_instance_valid(_wired_health) and _wired_health.has_signal("damaged") and _wired_health.damaged.is_connected(_on_player_damaged):
		_wired_health.damaged.disconnect(_on_player_damaged)
	_wired_health = null


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


## Resolve the flat spawn queue: mode override > authored entries > planner.
func _wave_queue(wave_number: int, cfg: WaveConfig) -> Array[StringName]:
	var mode_id := _run_mode()
	var mode_queue := GameMode.spawn_queue(mode_id, wave_number, _seed)
	if not mode_queue.is_empty():
		return mode_queue
	if ContentRegistry != null and ContentRegistry.has_authored_wave(wave_number):
		# Boss-rush / campaign still prefer mode queues; authored waves apply to standard.
		if mode_id == GameMode.MODE_STANDARD or mode_id == GameMode.MODE_CHALLENGE:
			return WavePlanner.expand_authored_entries(cfg, _seed)
	return WavePlanner.extended_queue_for_wave(wave_number, _seed)


func _run_mode() -> StringName:
	if GameRoot != null:
		return GameRoot.get_run_mode()
	return GameMode.MODE_STANDARD


## Player's prestige tier, consulted for prestige-scaling modes (Challenge).
func _prestige_rank() -> int:
	if GameRoot != null:
		return GameRoot.get_prestige_rank()
	return 0


func _launch_wave(wave_number: int) -> void:
	if _spawn == null:
		EventBus.report_warning("WaveManager has no spawn manager")
		return
	var cfg := _wave_config(wave_number)
	# Mutators resolve FIRST: the count nudge below and the banner both read the folded record, so
	# the wave's rules have to exist before anything else asks what the wave is.
	_resolve_mutators(wave_number, cfg)
	_fold_modifiers(wave_number)
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
	# The run only hears about a wave that is actually launching: an empty plan aborts above, and
	# a save written after that must not carry mutators the player never faced.
	_mirror_to_run(_wave_mods)
	_push_scaling_to_spawner()
	# The governor may lower the live population, never raise it: the authored cap is the ceiling and
	# an ultra-tier arena under load asks for fewer bodies on screen at once.
	var live_cap := cfg.maximum_simultaneous_enemies
	var monitors := get_tree().get_nodes_in_group("performance_monitor") if get_tree() != null else []
	if not monitors.is_empty() and monitors[0] is PerformanceMonitor:
		live_cap = mini(live_cap, (monitors[0] as PerformanceMonitor).max_simultaneous_enemies())
	_spawn.queue_wave(queue, wave_number, cfg.spawn_interval, live_cap)
	GameRoot.record_current_wave(wave_number)
	EventBus.wave_started.emit(wave_number, _planned_count)
	EventBus.report_info("Wave %d started (%d planned)%s" % [wave_number, _planned_count,
		(" [" + WaveMutators.banner_text(_active_mutators) + "]") if not _active_mutators.is_empty() else ""])
	_announce_wave(wave_number)
	AudioManager.play_sfx(&"wave_started", -8.0, 1.0 + 0.02 * (wave_number % 5))


## Banner line for the wave: mutator names ride along so players can adapt.
func _announce_wave(wave_number: int) -> void:
	var mode_id := _run_mode()
	var text := "Wave %d" % wave_number
	var cap := GameMode.max_waves_for(mode_id, _prestige_rank())
	if cap > 0:
		text = "Wave %d / %d" % [wave_number, cap]
	var severity := &"info"
	if not _active_mutators.is_empty():
		text += " — " + WaveMutators.banner_text(_active_mutators)
		# "major" is authored on the mutator (WaveMutatorConfig.severity) and folded into the wave's
		# record; it used to be folded too, but nothing downstream ever looked at the folded value,
		# so every mutator shouted at the same volume and a Glass Cannon wave read like a footnote.
		severity = &"danger" if _wave_mods.severity == WaveMutatorConfig.SEVERITY_MAJOR else &"warning"
	if wave_number % 10 == 0 or (cap > 0 and wave_number >= cap):
		severity = &"danger"
	EventBus.announcement.emit(&"wave_started", text, severity)
	# Narrative layer: campaign beats + arena lore on milestones.
	var arena_id := &"default_arena"
	var run := GameRoot.get_run() if GameRoot != null else null
	if run != null and run.arena_id != &"":
		arena_id = run.arena_id
	Narrator.announce_wave(mode_id, arena_id, wave_number)


func _resolve_mutators(wave_number: int, cfg: WaveConfig) -> void:
	if not _forced_mutators.is_empty():
		_active_mutators = _forced_mutators.duplicate()
		for id in _active_mutators:
			EventBus.wave_mutator_applied.emit(id, wave_number)
		return
	# Mode-forced mutators (challenge / boss rush) apply for the whole run.
	# Challenge scales its set by prestige tier; other modes keep authored lists.
	var mode_forced := GameMode.challenge_mutators(_run_mode(), _prestige_rank())
	if not mode_forced.is_empty():
		_active_mutators = mode_forced.duplicate()
		for id in _active_mutators:
			EventBus.wave_mutator_applied.emit(id, wave_number)
		return
	# Authored waves declare their own; generated waves roll (director may veto).
	var declared: Array = []
	if cfg != null:
		declared = cfg.arena_modifier_ids.duplicate()
	var breather := _director.suggest_breather()
	if declared.is_empty() and breather:
		EventBus.report_info("Director grants a breather: no mutators for wave %d" % wave_number)
	_active_mutators = WaveMutators.resolve_for_wave(declared, wave_number, _seed, breather, _director.suggest_spice())
	for id in _active_mutators:
		EventBus.wave_mutator_applied.emit(id, wave_number)


## The whole wave's rules, folded once. Order matters and is deliberate: the plan's own per-wave
## scalars, then the director's bounded adaptive nudge, then the mutators — so a mutator is always
## applied on top of the difficulty the wave already had, exactly as the two Dictionary channels
## combined before (the multiplication is unchanged; what changed is that every key now reaches the
## consumer instead of being dropped by a setter that only knew four names). Bounds are applied once
## here, so no consumer has to remember its own clamp.
func _fold_modifiers(wave_number: int) -> void:
	var mods := WaveModifiers.neutral()
	mods.apply_plan_scalars(WavePlanner.calculate_difficulty_scalars(wave_number))
	mods.fold_director(_director.next_wave_multipliers())
	WaveMutators.fold_into(mods, _active_mutators)
	_wave_mods = mods


func _push_scaling_to_spawner() -> void:
	if _spawn == null:
		return
	_spawn.set_wave_modifiers(_wave_mods)


## The count rides the same folded record as the difficulty, so the wave a struggling player gets
## fewer of cannot also be the one whose mutators made everything faster.
func _apply_director_count_nudge(queue: Array[StringName]) -> void:
	apply_count_nudge(queue, _wave_mods.count_bonus)


## Publish the wave's rules where the run summary, the save and the UI can see them.
## `RunState.active_modifiers` used to be cleared, duplicated and serialized but never WRITTEN, so
## every run summary in the game reported "no mutators" — including runs played under three of
## them. The typed record is live-only (never saved): saving ids and re-resolving them is the
## scheme, and multipliers drift with the wave they were folded for.
func _mirror_to_run(mods: WaveModifiers) -> void:
	var run := GameRoot.get_run() if GameRoot != null else null
	if run == null:
		return
	run.set_wave_modifiers(mods)


## Deterministic spawn-count nudge for one resolved queue. Additions/removals are
## spread evenly across the ORIGINAL queue instead of appending its first entries
## or popping its tail, which skewed the wave toward head archetypes (weakest
## first) and silently dropped the late-wave elites/boss it was meant to keep.
## Pure + headless-testable; a +2 nudge on [a,a,a,a,b,b] adds queue[2], queue[4]
## (one of each third), and a -1 nudge removes the middle entry, never the boss.
static func apply_count_nudge(queue: Array[StringName], bonus: int) -> void:
	var n := queue.size()
	if n <= 0 or bonus == 0:
		return
	if bonus > 0:
		# Duplicate the entry at each evenly-spaced pick position of the ORIGINAL
		# queue (spacing divides the queue into bonus+1 equal segments).
		for i in range(bonus):
			queue.append(queue[_spread_position(i, bonus, n)])
		return
	# Negative: remove `drop` entries, but never empty a non-empty plan. Removing
	# evenly spaced original positions (instead of popping the tail) preserves
	# late-wave entries like elites/bosses.
	var drop := mini(-bonus, n - 1)
	if drop <= 0:
		return
	var drop_positions: Dictionary = {}
	for i in range(drop):
		drop_positions[_spread_position(i, drop, n)] = true
	var survivors: Array[StringName] = []
	for idx in range(n):
		if not drop_positions.has(idx):
			survivors.append(queue[idx])
	queue.clear()
	for idn in survivors:
		queue.append(idn)


## The i-th (0-based) of `k` evenly-spaced positions in an `n`-long sequence:
## the sequence is split into k+1 equal segments and one position per segment is
## chosen, so picks can never cluster at the head or the tail.
static func _spread_position(i: int, k: int, n: int) -> int:
	if n <= 0:
		return 0
	return mini((i + 1) * n / (k + 1), n - 1)


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
	# Mode score multiplier folds into the wave completion bonus (prestige-scaled
	# for Challenge, so a Last Stand tier pays out on its escalated curve).
	bonus = int(round(float(bonus) * GameMode.score_multiplier_for(_run_mode(), _prestige_rank())))
	# Completion bonus is centralized in GameRoot (exactly-once via EventBus.wave_completed).
	EventBus.wave_completed.emit(_current_wave, bonus)
	EventBus.report_info("Wave %d completed (bonus %d)" % [_current_wave, bonus])
	AudioManager.play_sfx(&"wave_completed", -7.0)
	_tick_director_clock()
	# Mode win condition: finishing the cap wave ends the run in victory
	# (Challenge's cap grows with prestige tier).
	if GameMode.is_victory_wave_for(_run_mode(), _current_wave, _prestige_rank()):
		if GameRoot != null:
			GameRoot.declare_victory()
		stop()
		return
	var wants_upgrade := cfg.upgrade_after_completion or GameMode.wants_upgrade(_run_mode(), _current_wave)
	if wants_upgrade:
		# Open a deterministic upgrade selection; GameRoot routes PLAYING -> UPGRADE_SELECTION.
		if GameRoot.present_upgrade_selection_for_wave(_current_wave):
			_awaiting_upgrade = true
			EventBus.report_info("Awaiting upgrade selection before wave %d" % (_current_wave + 1))
			return
		EventBus.report_info("No upgrade to present after wave %d; continuing" % _current_wave)
	# Otherwise, take a short inter-wave break then start the next wave.
	_arm_next_wave_transition()


func _tick_director_clock() -> void:
	var run := GameRoot.get_run()
	if run != null:
		_director.set_time(run.elapsed_seconds)


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
	# Always re-bind per-run state so a new run's player damage feeds the director.
	if _director_wired:
		_director.reset(_player_max_hp())
		_rebind_player_damage()
		return
	_director_wired = true
	_director.reset(_player_max_hp())
	_bus.bind(EventBus.enemy_killed, _on_director_kill)
	_rebind_player_damage()


func _rebind_player_damage() -> void:
	# Disconnect any previous player's signal so damage is never double-counted
	# across run rebuilds (old player is queue_free'd but lingers until end of frame).
	# HealthComponent is a typed ref, so the `damaged` signal is known at compile
	# time — no has_signal probing.
	if _wired_health != null and is_instance_valid(_wired_health):
		if _wired_health.damaged.is_connected(_on_player_damaged):
			_wired_health.damaged.disconnect(_on_player_damaged)
	_wired_health = null
	if GameRoot == null or GameRoot.get_active_player() == null:
		return
	var hp := GameRoot.get_active_player().get_health_component()
	if hp == null:
		return
	if not hp.damaged.is_connected(_on_player_damaged):
		hp.damaged.connect(_on_player_damaged)
	_wired_health = hp


func _on_player_damaged(result: DamageResult) -> void:
	if result != null and result.accepted:
		record_player_damage(result.final_amount)


func _exit_tree() -> void:
	if _wired_health != null and is_instance_valid(_wired_health) and _wired_health.damaged.is_connected(_on_player_damaged):
		_wired_health.damaged.disconnect(_on_player_damaged)
	_wired_health = null
	_bus.unbind_all()


func _player_max_hp() -> float:
	var player := GameRoot.get_active_player()
	if player == null or not is_instance_valid(player):
		return 100.0
	var hp := player.get_health_component()
	if hp != null:
		return maxf(hp.get_max(), 1.0)
	return 100.0


func _on_director_kill(_enemy: Node, _archetype: StringName, _score: int, _currency: int) -> void:
	if not _active:
		return
	_tick_director_clock()
	_director.record_kill()


## Player-hurt feed for the adaptive director (wired to the player HealthComponent
## in _wire_director; safe to call directly from UI/debug too).
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
