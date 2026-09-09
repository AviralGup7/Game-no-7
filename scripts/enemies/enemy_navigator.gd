class_name EnemyNavigator
extends RefCounted

## Navigation-aware steering, extracted from EnemyBase. Resolution order:
##
##   1. ArenaNavGrid (shared flow field + A*). When the grid has line of sight
##      to the goal, steer direct (fast, human); otherwise follow the shared
##      flow field toward the player, or a cached A* path for one-off goals
##      (investigating a last-seen point). This is what keeps enemies out of
##      pillars, the central landmark and each arena's obstacle set.
##   2. NavigationAgent3D navmesh — kept as a legacy fallback for scenes that
##      have no grid wired (the old flat convex floor).
##   3. The caller's direct direction (physics collision still protects the
##      body in the worst case).

const PHYSICS_INTERVAL := 1.0 / 60.0
const PATH_REFRESH := 0.45
const PATH_TARGET_RADIUS := 0.9
const PATH_RETARGET_DIST := 1.0

var _agent: NavigationAgent3D = null
var _grid: ArenaNavGrid = null
var _recompute := 0.0

# A* cache for one-off goals (investigate points, waypoint maneuvers).
var _path_cache: PackedVector3Array = PackedVector3Array()
var _path_anchor := Vector3.ZERO
var _path_goal := Vector3.ZERO
var _path_index := 0
var _path_age := 999.0


func bind(agent: NavigationAgent3D) -> void:
	_agent = agent


func set_grid(grid: ArenaNavGrid) -> void:
	_grid = grid
	invalidate_path()


func reset(target: Node3D) -> void:
	_recompute = 0.0
	invalidate_path()
	if _agent != null and target != null:
		_agent.target_position = target.global_position


func invalidate_path() -> void:
	_path_cache = PackedVector3Array()
	_path_index = 0
	_path_age = 999.0


## Steer toward a live target node (the player). Grid flow field first, then
## navmesh, then the caller's fallback direction.
func direction(body_position: Vector3, target: Node3D, fallback: Vector3, update_interval: float) -> Vector3:
	if target == null or not is_instance_valid(target):
		return fallback
	var tp: Vector3 = target.global_position
	if _grid != null and _grid.is_built():
		if _grid.has_line_of_sight(body_position, tp):
			var direct := _flat_dir(body_position, tp)
			if direct != Vector3.ZERO:
				return direct
		var fd := _grid.flow_field_direction(body_position)
		if fd != Vector3.ZERO:
			return fd
		# Grid says nothing (unreachable cell, stale field): fall through.
	if _agent != null and _nav_usable():
		_recompute -= PHYSICS_INTERVAL
		if _recompute <= 0.0:
			_agent.target_position = tp
			_recompute = update_interval
		if _agent.is_navigation_finished():
			return fallback
		var next := _agent.get_next_path_position()
		var offset := next - body_position
		offset.y = 0.0
		if offset.length_squared() < 0.0001:
			return fallback
		return offset.normalized()
	return fallback


## Steer toward a fixed world point (investigate / waypoint). Uses a cached A*
## path that refreshes on a timer or when the point moves; direct steering
## when the line is open.
func direction_toward(body_position: Vector3, point: Vector3, fallback: Vector3, delta: float) -> Vector3:
	if not is_finite(point.x) or not is_finite(point.z):
		return fallback
	if body_position.distance_to(point) < PATH_TARGET_RADIUS:
		return fallback  # arrived; caller handles the linger
	if _grid == null or not _grid.is_built():
		return _flat_dir(body_position, point) if _flat_dir(body_position, point) != Vector3.ZERO else fallback
	if _grid.has_line_of_sight(body_position, point):
		return _flat_dir(body_position, point)
	_path_age += delta
	var stale := _path_cache.is_empty() or _path_age > PATH_REFRESH \
			or (point - _path_goal).length() > PATH_RETARGET_DIST \
			or (body_position - _path_anchor).length() > 2.5
	if stale:
		_path_cache = _grid.find_path(body_position, point)
		_path_anchor = body_position
		_path_goal = point
		_path_index = 0
		_path_age = 0.0
	while _path_index < _path_cache.size() \
			and body_position.distance_to(_path_cache[_path_index]) < PATH_TARGET_RADIUS:
		_path_index += 1
	if _path_index < _path_cache.size():
		var d := _flat_dir(body_position, _path_cache[_path_index])
		if d != Vector3.ZERO:
			return d
	return _flat_dir(body_position, point)


func _flat_dir(from: Vector3, to: Vector3) -> Vector3:
	var d := to - from
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return Vector3.ZERO
	return d.normalized()


func _nav_usable() -> bool:
	if _agent == null:
		return false
	var map := _agent.get_navigation_map()
	if map == null or not map.is_valid():
		return false
	return NavigationServer3D.map_get_iteration_id(map) > 0
