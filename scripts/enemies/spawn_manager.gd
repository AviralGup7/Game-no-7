class_name SpawnManager
extends Node3D

## Owns the physical spawning of enemies for the current wave: a flattened spawn queue,
## weighted point selection/validation, maximum simultaneous cap, spawn pacing, active
## enemy tracking, and authoritative planned/spawned/pending/active/defeated/failed
## accounting. It does NOT own score, upgrades, global saves or wave generation — those
## belong to WaveManager / GameRoot.
##
## Accounting is authoritative and event-driven: an entry is removed from the plan ONLY
## after a spawn succeeds; a defeated count increments ONLY when a genuinely killed enemy
## is removed via its death path. Failed spawn attempts are retried up to a bound and then
## counted as "failed" (never as defeated), so a bad spawn cannot silently under-fill a
## wave or falsely complete it.
##
## Extended responsibilities: elite rolling (EliteAffix), wave-modifier scaling
## (mutators + director, via set_wave_modifiers), death-effect dispatch (volatile
## blasts, splitter children — which EXTEND the plan so accounting stays exact),
## and boss fight kickoff (BossController.begin_fight).

signal spawn_plan_created(wave_number: int, total_count: int)
signal enemy_spawn_failed(archetype_id: StringName, reason: StringName)
signal enemy_defeated(archetype_id: StringName)
signal elite_spawned(enemy: EnemyBase, affixes: Array)
signal all_cleared()

const SPAWN_POINT_GROUP := &"enemy_spawn_point"
## Bounded retries per queue-head before it is counted as a failed spawn (prevents
## infinite retry loops while never treating a failed spawn as a defeat).
const MAX_FAILED_ATTEMPTS := 6

var _arena: Node3D = null
var _player: Node = null
var _container: Node3D = null
var _rng := RandomNumberGenerator.new()

var _pending: Array[StringName] = []          # archetype ids still to spawn
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

## Authoritative accounting counters (event-driven, never inferred from differences).
var _planned_count := 0
var _spawned_count := 0
var _defeated_count := 0
var _failed_count := 0

var _attempt_head: StringName = &""
var _attempt_count := 0


func _ready() -> void:
	_timer = get_node_or_null("SpawnTimer") as Timer
	if _timer != null:
		_timer.timeout.connect(_on_spawn_tick)


func configure(arena: Node3D, player: Node, container: Node3D, run_seed: int = 0) -> void:
	_arena = arena
	_player = player
	_container = container
	_run_seed = run_seed
	_configured = arena != null and player != null
	clear()


## Register a new spawn plan. `archetypes` is an ordered flat queue; entry count and
## composition are decided by the WaveManager / WavePlanner.
func queue_wave(archetypes: Array[StringName], wave_number: int, interval: float, max_simultaneous: int) -> void:
	clear()
	_current_wave = wave_number
	_spawn_interval = maxf(interval, 0.15)
	_max_simultaneous = maxi(1, max_simultaneous)
	_rng.seed = _hash_seed(_run_seed, wave_number)
	_pending = archetypes.duplicate()
	_planned_count = _pending.size()
	_spawn_index = 0
	spawn_plan_created.emit(_current_wave, _planned_count)
	if _timer != null:
		_timer.wait_time = _spawn_interval
		_timer.start()


func get_planned_count() -> int:
	return _planned_count


func get_pending_count() -> int:
	return _pending.size()


func get_spawned_count() -> int:
	return _spawned_count


func get_active_count() -> int:
	_prune_active()
	return _active.size()


func get_defeated_count() -> int:
	return _defeated_count


func get_failed_count() -> int:
	return _failed_count


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
	return not _pending.is_empty() or get_active_count() > 0


func _on_spawn_tick() -> void:
	if not _configured:
		_timer.stop()
		return
	if _pending.is_empty():
		_timer.stop()
		_check_cleared()
		return
	if get_active_count() >= _max_simultaneous:
		return  # timer keeps ticking; wait for room
	_spawn_one()


func _spawn_one() -> bool:
	if _pending.is_empty() or not _configured:
		return false
	# PEEK, don't pop: an entry is removed from the plan ONLY after a spawn succeeds.
	var archetype: StringName = _pending[0]
	_reset_attempt_if_new_head(archetype)

	var config: EnemyConfig = ContentRegistry.get_enemy(archetype)
	if config == null or config.scene == null:
		return _count_failure(archetype, &"no_config",
			"Missing config/scene for %s; retried up to bound then counted failed." % String(archetype))
	var point := _pick_spawn_point(config)
	if point == null:
		# Fallback: allow any in-bounds point (relax the min-distance rule) so a player
		# camping every marker cannot cause an infinite no-point stall.
		point = _fallback_spawn_point()
	if point == null:
		return _count_failure(archetype, &"no_valid_point",
			"No valid spawn point for %s; retried up to bound then counted failed." % String(archetype))
	var instance := config.scene.instantiate() as EnemyBase
	if instance == null:
		return _count_failure(archetype, &"bad_scene", "Scene did not yield an EnemyBase for %s." % String(archetype))
	var parent := _container if _container != null else self
	parent.add_child(instance)
	instance.global_transform = point.global_transform
	instance.set_bounds(_arena_half())
	instance.initialize(config, _player as Node3D, _run_seed)
	_apply_spawn_scaling(instance, config)
	_maybe_make_elite(instance, config)
	_maybe_begin_boss_fight(instance)
	instance.despawn_requested.connect(_on_enemy_despawn_requested)
	_active.append(instance)
	# Success: only now remove the entry from the plan.
	_pending.pop_front()
	_spawned_count += 1
	_spawn_index += 1
	_attempt_head = &""
	_attempt_count = 0
	EventBus.enemy_spawned.emit(instance, archetype)
	return true


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
	EventBus.report_info("Elite %s spawned (%s)" % [String(instance.get_archetype_id()), str(affixes)])


func _maybe_begin_boss_fight(instance: EnemyBase) -> void:
	var boss := instance.get_node_or_null("BossController")
	if boss != null and boss.has_method("begin_fight"):
		boss.call("begin_fight")


func _reset_attempt_if_new_head(archetype: StringName) -> void:
	if archetype != _attempt_head:
		_attempt_head = archetype
		_attempt_count = 0


## A spawn attempt failed. Retry up to MAX_FAILED_ATTEMPTS then drop the head as a FAILED
## spawn (recorded separately from defeats so completion accounting stays consistent).
func _count_failure(archetype: StringName, reason: StringName, message: String) -> bool:
	_attempt_count += 1
	if _attempt_count < MAX_FAILED_ATTEMPTS:
		enemy_spawn_failed.emit(archetype, reason)
		EventBus.report_warning("%s (attempt %d/%d)" % [message, _attempt_count, MAX_FAILED_ATTEMPTS])
		return false
	# Bounded retries exhausted: record the entry as failed and move past it.
	_pending.pop_front()
	_failed_count += 1
	_attempt_head = &""
	_attempt_count = 0
	enemy_spawn_failed.emit(archetype, reason)
	EventBus.report_error("%s (permanently failed after %d attempts)" % [message, MAX_FAILED_ATTEMPTS])
	return false


## A genuinely killed enemy is removed from the active set and counted as defeated.
## Death effects (volatile blasts, splitter children) dispatch BEFORE the defeat is
## recorded so observers see a consistent world.
func _on_enemy_despawn_requested(enemy: Node) -> void:
	var idx := _active.find(enemy)
	if idx >= 0:
		_active.remove_at(idx)
		_dispatch_death_effects(enemy)
		_defeated_count += 1
		var archetype := &""
		if enemy is EnemyBase:
			archetype = (enemy as EnemyBase).get_archetype_id()
		enemy_defeated.emit(archetype)
		EventBus.wave_progressed.emit(_current_wave, _defeated_count, _planned_count)
	_check_cleared()


## Volatile explosions + splitter children. Children EXTEND the plan (planned and
## pending both grow) so wave completion still requires killing everything.
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
	# Splitter children join the pending queue (plan extended, accounting exact).
	if config != null and config.split_count > 0 and not String(config.splits_into).is_empty():
		var child_cfg: EnemyConfig = ContentRegistry.get_enemy(config.splits_into)
		if child_cfg != null:
			for i in range(config.split_count):
				_pending.append(config.splits_into)
				_planned_count += 1
			EventBus.report_info("%s split into %d x %s" % [String(base.get_archetype_id()), config.split_count, String(config.splits_into)])


func _detonate(source: EnemyBase, at: Vector3, config: EnemyConfig) -> void:
	var radius := 3.0
	var scale := 1.5
	if config != null:
		radius = config.death_blast_radius
		scale = config.death_blast_damage_scale
	var damage := source.get_effective_attack_damage() * scale
	var victims: Array = []
	if _player != null and is_instance_valid(_player):
		victims = [_player]
	# Friendly-fire the blast into nearby enemies too (exploders chain!).
	victims.append_array(_active)
	AreaDamage.apply_radial(victims, at, radius, damage, source, source.get_archetype_id(), 12.0, true, AreaDamage.FALLOFF_LINEAR, [source])


func _check_cleared() -> void:
	if _pending.is_empty() and _active.is_empty():
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
	if _arena == null:
		return null
	var player_pos := Vector3.ZERO
	if _player is Node3D and is_instance_valid(_player):
		player_pos = (_player as Node3D).global_position
	var points: Array = _arena.call("get_spawn_points")
	var min_distance: float = _arena_min_spawn_distance()
	var rng := _rng
	points = filter_spawn_points(points, player_pos, min_distance, config.archetype_id)
	if points.is_empty():
		return null
	return points[rng.randi_range(0, points.size() - 1)]


func _arena_min_spawn_distance() -> float:
	if _arena != null and _arena.has_method("get_min_spawn_distance"):
		return float(_arena.call("get_min_spawn_distance"))
	return 6.0


func _arena_half() -> float:
	if _arena != null and _arena.has_method("get_interior_half"):
		return float(_arena.call("get_interior_half"))
	return 12.0


## Fallback spawn point that ignores the min-distance rule but still keeps the spawn
## inside the arena interior (used when the player is blocking every far spawn point).
func _fallback_spawn_point() -> Node3D:
	if _arena == null:
		return null
	var half := _arena_half()
	var points: Array = _arena.call("get_spawn_points")
	for p in points:
		var node := p as Node3D
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var pos := node.global_position
		if absf(pos.x) > half - 0.5 or absf(pos.z) > half - 0.5:
			continue
		return node
	return null


## Pure, testable filtering. Keeps points that are markers in-tree, far enough from the
## player, inside the arena interior, and permitted for the archetype.
static func filter_spawn_points(points: Array, player_position: Vector3, min_distance: float, archetype: StringName) -> Array:
	var half := 12.0
	var out: Array = []
	for p in points:
		var node := p as Node3D
		if node == null or not is_instance_valid(node):
			continue
		if not node.is_inside_tree():
			continue
		if _point_allowed_for(node, archetype) == false:
			continue
		var pos := node.global_position
		var dist := Vector2(pos.x, pos.z).distance_to(Vector2(player_position.x, player_position.z))
		if dist < min_distance:
			continue
		if absf(pos.x) > half - 0.5 or absf(pos.z) > half - 0.5:
			continue
		out.append(node)
	return out


## Read optional spawn marker metadata. Returns null when the marker imposes no rule.
static func _point_allowed_for(point: Node, archetype: StringName) -> Variant:
	if point.has_meta("allowed_archetypes"):
		var allowed: Array = point.get_meta("allowed_archetypes")
		if allowed.size() > 0 and archetype not in allowed:
			return false
	if point.has_meta("blocked_archetypes"):
		var blocked: Array = point.get_meta("blocked_archetypes")
		if archetype in blocked:
			return false
	return null


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
	_pending.clear()
	_planned_count = 0
	_spawned_count = 0
	_defeated_count = 0
	_failed_count = 0
	_attempt_head = &""
	_attempt_count = 0
	_spawn_index = 0
	if _timer != null:
		_timer.stop()


func force_spawn_one() -> bool:
	return _spawn_one()


func get_debug_snapshot() -> Dictionary:
	return {
		"wave": _current_wave,
		"planned": _planned_count,
		"pending": _pending.size(),
		"spawned": _spawned_count,
		"active": get_active_count(),
		"defeated": _defeated_count,
		"failed": _failed_count,
		"max_simultaneous": _max_simultaneous,
		"interval": _spawn_interval,
		"configured": _configured,
		"wave_mods": _wave_mods.duplicate(),
	}


func _hash_seed(run_seed: int, wave_number: int) -> int:
	return (run_seed * 31 + wave_number * 17) & 0x7FFFFFFF
