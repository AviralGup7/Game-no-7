class_name SpawnManager
extends Node3D

## Owns the physical spawning of enemies for the current wave: pacing, the
## simultaneous cap, point selection (SpawnPlacer), instantiation + scaling, and
## active-enemy tracking. Authoritative planned/spawned/pending/active/defeated/
## failed accounting lives in SpawnLedger; this manager drives it event-first so a
## bad spawn can never under-fill a wave or falsely complete it. It does NOT own
## score, upgrades, global saves or wave generation — those belong to WaveManager /
## GameRoot.
##
## Extended responsibilities: elite rolling (EliteAffix), wave-modifier scaling
## (mutators + director, via set_wave_modifiers), death-effect dispatch (volatile
## blasts, splitter children — which EXTEND the plan so accounting stays exact),
## and boss fight kickoff (BossController.begin_fight, seeded for determinism).
##
## Pacing: waves open with a small immediate burst (up to INITIAL_BURST) so the
## arena fills promptly; the rest trickle on the SpawnTimer. Spawn order and
## placement stay deterministic in (run_seed, wave_number).

signal spawn_plan_created(wave_number: int, total_count: int)
signal enemy_spawned(enemy: EnemyBase, archetype_id: StringName)
signal enemy_spawn_failed(archetype_id: StringName, reason: StringName)
signal enemy_defeated(archetype_id: StringName)
signal elite_spawned(enemy: EnemyBase, affixes: Array)
signal all_cleared()

const SPAWN_POINT_GROUP := &"enemy_spawn_point"
const INITIAL_BURST := 3
const SPAWN_JITTER_RADIUS := 1.2
const SPLIT_BURST_RADIUS := 0.9
const SPLIT_BURST_PUSH := 3.0

var _arena: Node3D = null
var _player: Node = null
var _container: Node3D = null
var _rng := RandomNumberGenerator.new()
var _ledger := SpawnLedger.new()

var _active: Array[EnemyBase] = []
var _timer: Timer = null
var _spawn_interval := 0.6
var _max_simultaneous := 12
var _current_wave := 0
var _configured := false
var _run_seed := 0
var _difficulty := {"hp": 1.0, "damage": 1.0, "speed": 1.0}
## Wave-modifier multipliers (mutators + director). Neutral by default.
var _wave_mods := {"hp_mult": 1.0, "damage_mult": 1.0, "speed_mult": 1.0, "score_mult": 1.0, "elite_bonus": 0.0, "explode_chance": 0.0}
var _spawn_index := 0
## Optional test/tooling seam: a Callable(StringName) -> EnemyConfig. When invalid,
## the ContentRegistry autoload is used (normal game path).
var _content_provider: Callable = Callable()

var _event_bus: Node = null
var _event_bus_resolved := false


func _ready() -> void:
	_timer = get_node_or_null("SpawnTimer") as Timer
	if _timer != null:
		_timer.timeout.connect(_on_spawn_tick)


func _eb() -> Node:
	if not _event_bus_resolved:
		_event_bus_resolved = true
		if is_inside_tree():
			_event_bus = get_node_or_null("/root/EventBus")
	return _event_bus


func configure(arena: Node3D, player: Node, container: Node3D, run_seed: int = 0) -> void:
	_arena = arena
	_player = player
	_container = container
	_run_seed = run_seed
	_configured = arena != null and player != null
	clear()


## Point ContentRegistry lookups at a custom provider (headless tests / tooling).
func set_content_provider(provider: Callable) -> void:
	_content_provider = provider


func _resolve_enemy_config(archetype_id: StringName) -> EnemyConfig:
	if _content_provider.is_valid():
		var provided: Variant = _content_provider.call(archetype_id)
		if provided is EnemyConfig:
			return provided
		return null
	if is_inside_tree():
		var registry := get_node_or_null("/root/ContentRegistry")
		if registry != null and registry.has_method("get_enemy"):
			return registry.call("get_enemy", archetype_id)
	return null


## Register a new spawn plan. `archetypes` is an ordered flat queue; entry count and
## composition are decided by the WaveManager / WavePlanner.
func queue_wave(archetypes: Array[StringName], wave_number: int, interval: float, max_simultaneous: int) -> void:
	clear()
	_current_wave = wave_number
	_spawn_interval = maxf(interval, 0.15)
	_max_simultaneous = maxi(1, max_simultaneous)
	_rng.seed = _hash_seed(_run_seed, wave_number)
	_ledger.reset(archetypes)
	_spawn_index = 0
	spawn_plan_created.emit(_current_wave, _ledger.planned_count())
	if _timer != null:
		_timer.wait_time = _spawn_interval
		_timer.start()
	# Opening burst: drop the first few enemies immediately so the wave reads as
	# an encounter, not a trickle. Same order/accounting as timer spawns.
	for _i in range(mini(INITIAL_BURST, _max_simultaneous)):
		if not _spawn_one():
			break


func get_planned_count() -> int:
	return _ledger.planned_count()


func get_pending_count() -> int:
	return _ledger.pending_count()


func get_spawned_count() -> int:
	return _ledger.spawned_count()


func get_active_count() -> int:
	_prune_active()
	return _active.size()


func get_defeated_count() -> int:
	return _ledger.defeated_count()


func get_failed_count() -> int:
	return _ledger.failed_count()


func set_difficulty_scalars(scalars: Dictionary) -> void:
	_difficulty = {
		"hp": float(scalars.get("hp", 1.0)),
		"damage": float(scalars.get("damage", 1.0)),
		"speed": float(scalars.get("speed", 1.0)),
	}


## Wave-modifier multipliers from mutators + director (see WaveMutators.combine).
## Missing keys default to neutral; unknown keys are ignored.
func set_wave_modifiers(mods: Dictionary) -> void:
	for key in ["hp_mult", "damage_mult", "speed_mult", "score_mult"]:
		_wave_mods[key] = maxf(float(mods.get(key, 1.0)), 0.01)
	_wave_mods["elite_bonus"] = clampf(float(mods.get("elite_bonus", 0.0)), 0.0, 0.5)
	_wave_mods["explode_chance"] = clampf(float(mods.get("explode_chance", 0.0)), 0.0, 1.0)


func get_wave_modifiers() -> Dictionary:
	return _wave_mods.duplicate()


func is_spawning() -> bool:
	return not _ledger.is_empty() or get_active_count() > 0


func _on_spawn_tick() -> void:
	if not _configured:
		_timer.stop()
		return
	if _ledger.is_empty():
		_timer.stop()
		_check_cleared()
		return
	if get_active_count() >= _max_simultaneous:
		return  # timer keeps ticking; wait for room
	_spawn_one()


func _spawn_one() -> bool:
	if _ledger.is_empty() or not _configured:
		return false
	# PEEK, don't pop: the ledger removes the entry ONLY after a spawn succeeds.
	var archetype: StringName = _ledger.peek()
	_ledger.note_head(archetype)

	var config: EnemyConfig = _resolve_enemy_config(archetype)
	if config == null or config.scene == null:
		return _count_failure(archetype, &"no_config",
			"Missing config/scene for %s; retried up to bound then counted failed." % String(archetype))
	var point := _pick_spawn_point(config)
	if point == null:
		# Fallback: allow any in-bounds point (relax the min-distance rule) so a player
		# camping every marker cannot cause an infinite no-point stall.
		point = SpawnPlacer.fallback_point(_arena)
	if point == null:
		return _count_failure(archetype, &"no_valid_point",
			"No valid spawn point for %s; retried up to bound then counted failed." % String(archetype))
	var instance := config.scene.instantiate() as EnemyBase
	if instance == null:
		return _count_failure(archetype, &"bad_scene", "Scene did not yield an EnemyBase for %s." % String(archetype))
	var parent := _container if _container != null else self
	parent.add_child(instance)
	# Deterministic jitter around the marker so simultaneous spawns on the same
	# point do not stack into one body.
	instance.global_transform = point.global_transform
	instance.global_position = point.global_position + _spawn_jitter()
	instance.set_bounds(SpawnPlacer.interior_half(_arena))
	instance.initialize(config, _player as Node3D, _run_seed)
	instance.set_spawn_serial(_spawn_index)
	_apply_spawn_scaling(instance, config)
	_maybe_make_elite(instance, config)
	_maybe_begin_boss_fight(instance)
	_activate_enemy(instance, archetype)
	# Success: only now remove the entry from the plan.
	_ledger.pop_on_success()
	_spawn_index += 1
	return true


## Shared wiring for any enemy entering the arena (queue spawns + split bursts):
## despawn bookkeeping, active tracking, spawn sound + EventBus notification.
func _activate_enemy(instance: EnemyBase, archetype: StringName) -> void:
	instance.play_spawn_sound()
	instance.despawn_requested.connect(_on_enemy_despawn_requested)
	_active.append(instance)
	enemy_spawned.emit(instance, archetype)
	var bus := _eb()
	if bus != null:
		bus.enemy_spawned.emit(instance, archetype)


func _spawn_jitter() -> Vector3:
	var angle := _rng.randf_range(-PI, PI)
	var radius := _rng.randf_range(0.0, SPAWN_JITTER_RADIUS)
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


## Combined wave-difficulty + mutator/director scaling in one call so the shared
## EnemyConfig is never mutated.
func _apply_spawn_scaling(instance: EnemyBase, _config: EnemyConfig) -> void:
	var hp: float = float(_difficulty.get("hp", 1.0)) * float(_wave_mods.get("hp_mult", 1.0))
	var dmg: float = float(_difficulty.get("damage", 1.0)) * float(_wave_mods.get("damage_mult", 1.0))
	var spd: float = float(_difficulty.get("speed", 1.0)) * float(_wave_mods.get("speed_mult", 1.0))
	instance.apply_difficulty(hp, dmg, spd)


## Elite roll: config-gated, wave-gated, chance-boosted by mutators/director.
func _maybe_make_elite(instance: EnemyBase, config: EnemyConfig) -> void:
	if not EliteAffix.elite_allowed(config, _current_wave):
		return
	var chance: float = EliteAffix.elite_chance(_current_wave) + float(_wave_mods.get("elite_bonus", 0.0))
	if _rng.randf() > chance:
		return
	var affixes := EliteAffix.roll_affixes(config.archetype_id, _current_wave, _run_seed, _spawn_index)
	_apply_elite(instance, affixes)


## Apply a pre-rolled affix set (also used by tests / debug tooling).
func _apply_elite(instance: EnemyBase, affixes: Array) -> void:
	if affixes.is_empty():
		return
	var combo := EliteAffix.combine(affixes)
	# Re-scale on top of wave scaling (multiplicative, config untouched).
	instance.apply_difficulty(
		float(_difficulty.get("hp", 1.0)) * float(_wave_mods.get("hp_mult", 1.0)) * EliteAffix.ELITE_HP_MULT * float(combo["hp"]),
		float(_difficulty.get("damage", 1.0)) * float(_wave_mods.get("damage_mult", 1.0)) * EliteAffix.ELITE_DAMAGE_MULT * float(combo["damage"]),
		float(_difficulty.get("speed", 1.0)) * float(_wave_mods.get("speed_mult", 1.0)) * float(combo["speed"]))
	if instance.has_method("set_elite"):
		instance.call("set_elite", affixes)
	elite_spawned.emit(instance, affixes)
	var bus := _eb()
	if bus != null:
		bus.report_info("Elite %s spawned (%s)" % [String(instance.get_archetype_id()), str(affixes)])


func _maybe_begin_boss_fight(instance: EnemyBase) -> void:
	var boss := instance.get_node_or_null("BossController")
	if boss == null:
		return
	if boss.has_method("begin_fight"):
		boss.call("begin_fight", _run_seed)
	# Boss summons join the plan like splitter children (accounting stays exact).
	if boss.has_signal("summon_requested") and not boss.summon_requested.is_connected(_on_boss_summon_requested):
		boss.summon_requested.connect(_on_boss_summon_requested)


func _on_boss_summon_requested(archetype_id: StringName, count: int) -> void:
	var cfg: EnemyConfig = _resolve_enemy_config(archetype_id)
	if cfg == null:
		var bus := _eb()
		if bus != null:
			bus.report_warning("Boss summoned unknown archetype %s" % String(archetype_id))
		return
	for i in range(maxi(count, 0)):
		_ledger.extend_one(archetype_id)
	if not _ledger.is_empty() and _timer != null and _timer.is_stopped():
		_timer.start()
	var bus := _eb()
	if bus != null:
		bus.report_info("Boss summoned %d x %s" % [maxi(count, 0), String(archetype_id)])


## A spawn attempt failed. Retry up to the ledger bound then drop the head as a
## FAILED spawn (recorded separately from defeats so completion stays consistent).
func _count_failure(archetype: StringName, reason: StringName, message: String) -> bool:
	enemy_spawn_failed.emit(archetype, reason)
	var bus := _eb()
	if _ledger.note_attempt():
		# Bounded retries exhausted: the entry was dropped as failed, move past it.
		if bus != null:
			bus.report_error("%s (permanently failed after %d attempts)" % [message, SpawnLedger.MAX_FAILED_ATTEMPTS])
	else:
		if bus != null:
			bus.report_warning("%s (attempt %d/%d)" % [message, _ledger.attempt_count(), SpawnLedger.MAX_FAILED_ATTEMPTS])
	return false


## A genuinely killed enemy is removed from the active set and counted as defeated.
## Death effects (volatile blasts, splitter children) dispatch BEFORE the defeat is
## recorded so observers see a consistent world.
func _on_enemy_despawn_requested(enemy: Node) -> void:
	var idx := _active.find(enemy)
	if idx >= 0:
		_active.remove_at(idx)
		_dispatch_death_effects(enemy)
		# Splitter children can extend the plan after the pacing timer stopped
		# (the ledger was momentarily empty); restart it so the wave can't stall.
		if not _ledger.is_empty() and _timer != null and _timer.is_stopped():
			_timer.start()
		_ledger.record_defeat()
		var archetype := &""
		if enemy is EnemyBase:
			archetype = (enemy as EnemyBase).get_archetype_id()
		enemy_defeated.emit(archetype)
		var bus := _eb()
		if bus != null:
			bus.wave_progressed.emit(_current_wave, _ledger.defeated_count(), _ledger.planned_count())
	_check_cleared()


## Volatile explosions + splitter children. Children EXTEND the plan (planned grows)
## so wave completion still requires killing everything; when split_burst is enabled
## they are spawned immediately around the parent's death position, otherwise they
## join the pending queue like normal spawns.
func _dispatch_death_effects(enemy: Node) -> void:
	if enemy == null or not (enemy is EnemyBase):
		return
	var base := enemy as EnemyBase
	var config := base.get_config()
	var pos := base.global_position
	# Volatile: config flag, volatile-affix elites, or the Volatile Mix mutator.
	var volatile := false
	if config != null and config.explodes_on_death:
		volatile = true
	if base.has_method("get_elite_affixes") and EliteAffix.VOLATILE in base.call("get_elite_affixes"):
		volatile = true
	if not volatile and float(_wave_mods.get("explode_chance", 0.0)) > 0.0 and _rng.randf() < float(_wave_mods.get("explode_chance", 0.0)):
		volatile = true
	if volatile:
		_detonate(base, pos, config)
	if config != null and config.split_count > 0 and not String(config.splits_into).is_empty():
		_dispatch_split(base, config, pos)


func _dispatch_split(base: EnemyBase, config: EnemyConfig, at: Vector3) -> void:
	var child_cfg: EnemyConfig = _resolve_enemy_config(config.splits_into)
	if child_cfg == null:
		# Unknown child archetype: keep the plan honest — queue the entries so the
		# normal bounded-retry path records them as FAILED (never silently skipped).
		var bus := _eb()
		if bus != null:
			bus.report_warning("%s splits into unknown archetype %s" % [String(config.archetype_id), String(config.splits_into)])
		for i in range(config.split_count):
			_ledger.extend_one(config.splits_into)
		return
	if config.split_burst and _configured:
		# Burst at the parent: immediate spawns, direct ledger registration.
		for i in range(config.split_count):
			if not _spawn_split_child(child_cfg, at, i, config.split_count):
				_ledger.extend_one(config.splits_into)
	else:
		for i in range(config.split_count):
			_ledger.extend_one(config.splits_into)
	var bus := _eb()
	if bus != null:
		bus.report_info("%s split into %d x %s" % [String(base.get_archetype_id()), config.split_count, String(config.splits_into)])


## Burst-spawn one child around the parent position. Returns false when the spawn
## was impossible (caller falls back to extending the pending queue).
func _spawn_split_child(child_cfg: EnemyConfig, at: Vector3, index: int, total: int) -> bool:
	if child_cfg.scene == null or not _configured:
		return false
	var instance := child_cfg.scene.instantiate() as EnemyBase
	if instance == null:
		return false
	var parent := _container if _container != null else self
	parent.add_child(instance)
	var angle := TAU * float(index) / float(maxi(total, 1)) + _rng.randf_range(-0.35, 0.35)
	var outward := Vector3(cos(angle), 0.0, sin(angle))
	instance.global_position = at + outward * SPLIT_BURST_RADIUS
	instance.set_bounds(SpawnPlacer.interior_half(_arena))
	instance.initialize(child_cfg, _player as Node3D, _run_seed)
	instance.set_spawn_serial(_spawn_index)
	_apply_spawn_scaling(instance, child_cfg)
	# Children inherit wave scaling but never roll elite (keeps burst costs legible).
	_activate_enemy(instance, child_cfg.archetype_id)
	instance.set_velocity_flat(outward * SPLIT_BURST_PUSH)
	_ledger.register_direct_spawn(child_cfg.archetype_id)
	_spawn_index += 1
	return true


func _detonate(source: EnemyBase, at: Vector3, config: EnemyConfig) -> void:
	var radius := 3.0
	var damage_scale := 1.5
	if config != null:
		radius = config.death_blast_radius
		damage_scale = config.death_blast_damage_scale
	var damage := source.get_effective_attack_damage() * damage_scale
	var victims: Array = []
	if _player != null and is_instance_valid(_player):
		victims = [_player]
	# Friendly-fire the blast into nearby enemies too (exploders chain!).
	victims.append_array(_active)
	AreaDamage.apply_radial(victims, at, radius, damage, source, source.get_archetype_id(), 12.0, true, AreaDamage.FALLOFF_LINEAR, [source])


func _check_cleared() -> void:
	if _ledger.is_empty() and _active.is_empty():
		all_cleared.emit()


func _prune_active() -> void:
	var i := _active.size() - 1
	while i >= 0:
		if not is_instance_valid(_active[i]) or not _active[i].is_inside_tree():
			# An enemy that vanished without its death path (e.g. teardown) is not a defeat;
			# it is simply dropped from the active set.
			_active.remove_at(i)
		i -= 1


func _pick_spawn_point(config: EnemyConfig) -> Node3D:
	var player_pos := Vector3.ZERO
	if _player is Node3D and is_instance_valid(_player):
		player_pos = (_player as Node3D).global_position
	return SpawnPlacer.pick_point(_arena, player_pos, config.archetype_id, _rng)


## Kept as a thin delegate: point filtering moved to SpawnPlacer.
static func filter_spawn_points(points: Array, player_position: Vector3, min_distance: float, archetype: StringName) -> Array:
	return SpawnPlacer.filter_spawn_points(points, player_position, min_distance, archetype)


## Stop AI on every active enemy (e.g. on run game-over) without freeing them.
func deactivate_all() -> void:
	_prune_active()
	for enemy in _active:
		if is_instance_valid(enemy) and enemy.has_method("set_ai_enabled"):
			enemy.call("set_ai_enabled", false)


func clear() -> void:
	_prune_active()
	for enemy in _active:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_active.clear()
	_ledger.clear()
	_spawn_index = 0
	if _timer != null:
		_timer.stop()


func force_spawn_one() -> bool:
	return _spawn_one()


func get_debug_snapshot() -> Dictionary:
	var snap := _ledger.snapshot()
	snap["wave"] = _current_wave
	snap["active"] = get_active_count()
	snap["max_simultaneous"] = _max_simultaneous
	snap["interval"] = _spawn_interval
	snap["configured"] = _configured
	snap["wave_mods"] = _wave_mods.duplicate()
	return snap


func _hash_seed(run_seed: int, wave_number: int) -> int:
	return (run_seed * 31 + wave_number * 17) & 0x7FFFFFFF
