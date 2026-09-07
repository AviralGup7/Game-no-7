class_name SpawnManager
extends Node3D

## Owns the physical spawning of enemies for the current wave: a flattened spawn
## queue, point selection/validation, maximum simultaneous cap, spawn pacing, active
## enemy tracking, registration/removal and wave-clear detection. It does NOT own
## score, upgrades, global saves or wave generation — those belong to WaveManager /
## GameRoot. WaveManager hands it a queue and listens to its signals.

signal spawn_plan_created(wave_number: int, total_count: int)
signal enemy_spawn_failed(archetype_id: StringName, reason: StringName)
signal all_cleared()

const SPAWN_POINT_GROUP := &"enemy_spawn_point"

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
	spawn_plan_created.emit(_current_wave, _pending.size())
	if _timer != null:
		_timer.wait_time = _spawn_interval
		_timer.start()


func get_pending_count() -> int:
	return _pending.size()


func set_difficulty_scalars(scalars: Dictionary) -> void:
	_difficulty = {
		"hp": float(scalars.get("hp", 1.0)),
		"damage": float(scalars.get("damage", 1.0)),
		"speed": float(scalars.get("speed", 1.0)),
	}


func get_active_count() -> int:
	# Prune any freed references before counting.
	_prune_active()
	return _active.size()


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
	var archetype: StringName = _pending.pop_front()
	var config: EnemyConfig = ContentRegistry.get_enemy(archetype)
	if config == null or config.scene == null:
		enemy_spawn_failed.emit(archetype, &"no_config")
		return false
	var point := _pick_spawn_point(config)
	if point == null:
		enemy_spawn_failed.emit(archetype, &"no_valid_point")
		return false
	var instance := config.scene.instantiate() as EnemyBase
	if instance == null:
		enemy_spawn_failed.emit(archetype, &"bad_scene")
		return false
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
	EventBus.enemy_spawned.emit(instance, archetype)
	return true


func _on_enemy_despawn_requested(enemy: Node) -> void:
	var idx := _active.find(enemy)
	if idx >= 0:
		_active.remove_at(idx)
	_check_cleared()


func _check_cleared() -> void:
	if _pending.is_empty() and _active.is_empty():
		all_cleared.emit()


func _prune_active() -> void:
	var i := _active.size() - 1
	while i >= 0:
		if not is_instance_valid(_active[i]) or not _active[i].is_inside_tree():
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
	if _timer != null:
		_timer.stop()


func force_spawn_one() -> bool:
	return _spawn_one()


func get_debug_snapshot() -> Dictionary:
	return {
		"wave": _current_wave,
		"pending": _pending.size(),
		"active": get_active_count(),
		"max_simultaneous": _max_simultaneous,
		"interval": _spawn_interval,
		"configured": _configured,
	}


func _hash_seed(run_seed: int, wave_number: int) -> int:
	return (run_seed * 31 + wave_number * 17) & 0x7FFFFFFF
