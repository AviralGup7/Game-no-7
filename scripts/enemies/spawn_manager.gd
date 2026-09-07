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

signal spawn_plan_created(wave_number: int, total_count: int)
signal enemy_spawn_failed(archetype_id: StringName, reason: StringName)
signal enemy_defeated(archetype_id: StringName)
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
	instance.apply_difficulty(
		float(_difficulty.get("hp", 1.0)),
		float(_difficulty.get("damage", 1.0)),
		float(_difficulty.get("speed", 1.0)))
	instance.despawn_requested.connect(_on_enemy_despawn_requested)
	_active.append(instance)
	# Success: only now remove the entry from the plan.
	_pending.pop_front()
	_spawned_count += 1
	_attempt_head = &""
	_attempt_count = 0
	EventBus.enemy_spawned.emit(instance, archetype)
	return true


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
func _on_enemy_despawn_requested(enemy: Node) -> void:
	var idx := _active.find(enemy)
	if idx >= 0:
		_active.remove_at(idx)
		_defeated_count += 1
		var archetype := &""
		if enemy is EnemyBase:
			archetype = (enemy as EnemyBase).get_archetype_id()
		enemy_defeated.emit(archetype)
		EventBus.wave_progressed.emit(_current_wave, _defeated_count, _planned_count)
	_check_cleared()


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
	}


func _hash_seed(run_seed: int, wave_number: int) -> int:
	return (run_seed * 31 + wave_number * 17) & 0x7FFFFFFF
