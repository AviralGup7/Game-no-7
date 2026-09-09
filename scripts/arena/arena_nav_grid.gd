class_name ArenaNavGrid
extends RefCounted

## Deterministic, precomputed navigation grid for the arena (no runtime baking).
##
## Two consumers, one shared structure (the same pattern the open-source
## Manymies project uses to steer 1500+ enemies cheaply — see
## docs/ENEMY_AI_RESEARCH.md):
##
##   * Flow field (Dijkstra from the target's cell). Rebuilt ONLY when the
##     target moves to a different cell, then read by EVERY enemy each frame
##     through flow_field_direction(). O(1) per enemy, no per-enemy path
##     allocation.
##   * A* point-to-point (find_path / has_line_of_sight) for one-off goals
##     such as investigating a last-seen position.
##
## The grid is pure RefCounted: no nodes, no scene access — headless-testable
## and shareable across all actors (enemies path on it; the player is kept
## out of objects by physics collision on the same obstacle set).
##
## Obstacles are passed to build() as Dictionaries of the form
##     {"pos": Vector3(center, y ignored), "half_size": Vector3(full half extent)}
## and are inflated by AGENT_MARGIN so medium-sized bodies cannot hug walls.

## Obstacle inflation: the enemy capsule radius (0.5), so the path centerline
## never steers a body's edge into a wall.
const AGENT_MARGIN := 0.5
const WALL_MARGIN := 0.75
const INF := 1.0e9

var half := 12.0
var cell_size := 0.5
var width := 0
var depth := 0
var obstacle_count := 0

var _blocked: PackedByteArray = PackedByteArray()
var _flow_dist: PackedFloat32Array = PackedFloat32Array()
var _flow_target := Vector2i(-1, -1)
var _built := false

# Fixed 8-neighbor order: N, NE, E, SE, S, SW, W, NW (deterministic ties).
const NEIGHBORS := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]


func build(half_extent: float, cell_size_value: float, obstacles: Array) -> void:
	half = clampf(half_extent, 2.0, 200.0)
	cell_size = clampf(cell_size_value, 0.2, 2.0)
	width = maxi(8, int(ceilf(2.0 * half / cell_size)))
	depth = width
	_blocked = PackedByteArray()
	_blocked.resize(width * depth)
	_flow_dist = PackedFloat32Array()
	_flow_dist.resize(width * depth)
	_flow_dist.fill(INF)
	_flow_target = Vector2i(-1, -1)
	_built = false

	# Boundary ring: keep paths at least WALL_MARGIN inside the real walls
	# (matches the locomotion arena clamp and the previous navmesh inset).
	var limit := half - WALL_MARGIN
	for z in range(depth):
		for x in range(width):
			var c := cell_center(Vector2i(x, z))
			if absf(c.x) > limit or absf(c.z) > limit:
				_blocked[z * width + x] = 1

	obstacle_count = 0
	for raw in obstacles:
		var ob: Dictionary = raw if raw is Dictionary else {}
		var pos: Vector3 = ob.get("pos", Vector3.ZERO)
		var hs: Vector3 = ob.get("half_size", Vector3.ONE * 0.5)
		if not is_finite(pos.x) or not is_finite(pos.z):
			continue
		var aabb := AABB(pos, hs * 2.0).grow(AGENT_MARGIN)
		_mark_blocked(aabb)
		obstacle_count += 1
	_built = true


## Mark every cell whose center falls inside `aabb` as blocked.
func _mark_blocked(aabb: AABB) -> void:
	var min_c := _clamp_cell(to_cell(aabb.position))
	var max_c := _clamp_cell(to_cell(aabb.end))
	for z in range(min_c.y, max_c.y + 1):
		for x in range(min_c.x, max_c.x + 1):
			_blocked[z * width + x] = 1


func is_built() -> bool:
	return _built


func to_cell(pos: Vector3) -> Vector2i:
	var cx := int(floorf((pos.x + half) / cell_size))
	var cz := int(floorf((pos.z + half) / cell_size))
	return Vector2i(clampi(cx, 0, width - 1), clampi(cz, 0, depth - 1))


func cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * cell_size - half, 0.0, (c.y + 0.5) * cell_size - half)


func is_walkable(pos: Vector3) -> bool:
	if not _built:
		return false
	if not is_finite(pos.x) or not is_finite(pos.z):
		return false
	var c := to_cell(pos)
	if c.x < 0 or c.y < 0 or c.x >= width or c.y >= depth:
		return false
	return _blocked[c.y * width + c.x] == 0


func is_blocked_cell(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= width or c.y >= depth:
		return true
	return _blocked[c.y * width + c.x] != 0


func _clamp_cell(c: Vector2i) -> Vector2i:
	return Vector2i(clampi(c.x, 0, width - 1), clampi(c.y, 0, depth - 1))


## Nearest walkable cell to `c` within a `radius` cell ring (spiral, fixed
## order so results are deterministic). Returns Vector2i(-1,-1) when none.
func _nearest_walkable_cell(c: Vector2i, radius: int) -> Vector2i:
	var clamped := _clamp_cell(c)
	if not is_blocked_cell(clamped):
		return clamped
	for r in range(1, maxi(radius, 0) + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue  # inner rings already covered
				var n := Vector2i(clamped.x + dx, clamped.y + dz)
				if not is_blocked_cell(n):
					return n
	return Vector2i(-1, -1)


## ---------- Flow field (shared by every chaser) ----------

## Rebuild the flow field from `target_pos`. No-op when the target is still in
## the same cell — callers may invoke this at a fixed low rate each frame.
func rebuild_flow_field(target_pos: Vector3) -> void:
	if not _built:
		return
	var tc := _nearest_walkable_cell(to_cell(target_pos), 4)
	if tc == Vector2i(-1, -1):
		_flow_target = Vector2i(-1, -1)
		return
	if tc == _flow_target:
		return
	_flow_target = tc
	_flow_dist.fill(INF)
	_flow_dist[tc.y * width + tc.x] = 0.0
	var heap: Array = []
	_heap_push(heap, Vector2(0.0, float(tc.y * width + tc.x)))
	while not heap.is_empty():
		var top := _heap_pop(heap)
		var i := int(top.y)
		var cost := top.x
		if cost > _flow_dist[i] + 1.0e-6:
			continue  # stale entry
		var c := Vector2i(i % width, i / width)
		for n in NEIGHBORS:
			var nc := c + n
			if nc.x < 0 or nc.y < 0 or nc.x >= width or nc.y >= depth:
				continue
			if _blocked[nc.y * width + nc.x] != 0:
				continue
			# No corner cutting: a diagonal is only legal when both orthogonal
			# neighbors are walkable, otherwise bodies would clip pillar corners.
			if n.x != 0 and n.y != 0:
				if _blocked[(c.y + n.y) * width + c.x] != 0 or _blocked[c.y * width + (c.x + n.x)] != 0:
					continue
			var step := sqrt(2.0) if (n.x != 0 and n.y != 0) else 1.0
			var ni := nc.y * width + nc.x
			var nc_cost := cost + step
			if nc_cost < _flow_dist[ni] - 1.0e-6:
				_flow_dist[ni] = nc_cost
				_heap_push(heap, Vector2(nc_cost, float(ni)))


## Walk direction from `pos` along the flow field (flat, normalized). Zero
## when there is no field, the cell is unreachable, or `pos` is already at
## the target.
func flow_field_direction(pos: Vector3) -> Vector3:
	if not _built or _flow_target == Vector2i(-1, -1):
		return Vector3.ZERO
	var c := to_cell(pos)
	if is_blocked_cell(c):
		c = _nearest_walkable_cell(c, 3)
		if c == Vector2i(-1, -1):
			return Vector3.ZERO
	var i := c.y * width + c.x
	var d := _flow_dist[i]
	if d >= INF / 2.0 or d <= 0.001:
		return Vector3.ZERO
	var best := i
	var best_d := d
	for n in NEIGHBORS:
		var nc := c + n
		if nc.x < 0 or nc.y < 0 or nc.x >= width or nc.y >= depth:
			continue
		var ni := nc.y * width + nc.x
		if _blocked[ni] != 0:
			continue
		var nd := _flow_dist[ni]
		if nd < best_d - 1.0e-6:
			best = ni
			best_d = nd
	if best == i:
		return Vector3.ZERO
	var center := cell_center(c)
	var next_center := cell_center(Vector2i(best % width, best / width))
	var dir := Vector3(next_center.x - center.x, 0.0, next_center.z - center.z)
	if dir.length_squared() < 0.0001:
		return Vector3.ZERO
	return dir.normalized()


func flow_field_reachable(pos: Vector3) -> bool:
	if not _built or _flow_target == Vector2i(-1, -1):
		return false
	var c := to_cell(pos)
	if is_blocked_cell(c):
		c = _nearest_walkable_cell(c, 3)
		if c == Vector2i(-1, -1):
			return false
	return _flow_dist[c.y * width + c.x] < INF / 2.0


## ---------- Line of sight ----------

## Sampled walkability check between two world points. Used to skip pathing
## entirely when a straight line is legal (fast, human-looking direct pursuit)
## and by string-pulling to smooth A* paths.
func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	if not _built:
		return true  # no grid -> assume open (callers fall back to physics)
	if not is_walkable(from) or not is_walkable(to):
		return false
	var delta := to - from
	delta.y = 0.0
	var dist := delta.length()
	if dist < 0.001:
		return true
	var steps := ceili(dist / (cell_size * 0.5))
	for s in range(1, steps):
		var p := from + delta * (float(s) / float(steps))
		if not is_walkable(p):
			return false
	return true


## ---------- A* point-to-point ----------

## World-space waypoints from `from_pos` toward `to_pos` (start excluded, goal
## included, string-pulled). Empty when the endpoints are co-located or no
## route exists. Deterministic for identical grid + endpoints.
func find_path(from_pos: Vector3, to_pos: Vector3) -> PackedVector3Array:
	var empty := PackedVector3Array()
	if not _built:
		return empty
	var sc := _nearest_walkable_cell(to_cell(from_pos), 3)
	var tc := _nearest_walkable_cell(to_cell(to_pos), 3)
	if sc == Vector2i(-1, -1) or tc == Vector2i(-1, -1):
		return empty
	if sc == tc:
		return empty
	var size := width * depth
	var g: PackedFloat32Array = PackedFloat32Array()
	g.resize(size)
	g.fill(INF)
	var came: PackedInt32Array = PackedInt32Array()
	came.resize(size)
	came.fill(-1)
	var closed: PackedByteArray = PackedByteArray()
	closed.resize(size)
	var start_i := sc.y * width + sc.x
	var goal_i := tc.y * width + tc.x
	g[start_i] = 0.0
	var heap: Array = []
	_heap_push(heap, Vector2(_heuristic(sc, tc), float(start_i)))
	while not heap.is_empty():
		var top := _heap_pop(heap)
		var i := int(top.y)
		if closed[i] != 0:
			continue
		closed[i] = 1
		if i == goal_i:
			break
		var c := Vector2i(i % width, i / width)
		for n in NEIGHBORS:
			var nc := c + n
			if nc.x < 0 or nc.y < 0 or nc.x >= width or nc.y >= depth:
				continue
			if _blocked[nc.y * width + nc.x] != 0:
				continue
			if n.x != 0 and n.y != 0:
				if _blocked[(c.y + n.y) * width + c.x] != 0 or _blocked[c.y * width + (c.x + n.x)] != 0:
					continue
			var ni := nc.y * width + nc.x
			if closed[ni] != 0:
				continue
			var step := sqrt(2.0) if (n.x != 0 and n.y != 0) else 1.0
			var ng := g[i] + step
			if ng < g[ni] - 1.0e-6:
				g[ni] = ng
				came[ni] = i
				_heap_push(heap, Vector2(ng + _heuristic(nc, tc), float(ni)))
	if came[goal_i] == -1:
		return empty
	# Reconstruct (goal -> start), convert to world waypoints (start excluded).
	var cells: PackedVector3Array = PackedVector3Array()
	var cur := goal_i
	while cur != start_i and cur != -1:
		cells.append(cell_center(Vector2i(cur % width, cur / width)))
		cur = came[cur]
	cells.reverse()
	# Greedy string-pulling: jump to the farthest visible waypoint, skipping
	# the square-cornered A* staircase.
	var out := PackedVector3Array()
	var anchor := from_pos
	var i := 0
	while i < cells.size():
		var j := cells.size() - 1
		while j > i and not has_line_of_sight(anchor, cells[j]):
			j -= 1
		out.append(cells[j])
		anchor = cells[j]
		i = j + 1
	return out


## Octile distance (admissible for 8-direction movement with sqrt(2) diagonals).
func _heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx := absf(float(a.x - b.x))
	var dz := absf(float(a.y - b.y))
	return maxf(dx, dz) + (sqrt(2.0) - 1.0) * minf(dx, dz)


func get_debug_snapshot() -> Dictionary:
	return {
		"built": _built,
		"half": half,
		"cell_size": cell_size,
		"cells": width * depth,
		"obstacles": obstacle_count,
		"flow_target": _flow_target,
	}


## ---------- Tiny binary min-heap on Vector2(cost, packed_index) ----------

static func _heap_push(h: Array, v: Vector2) -> void:
	h.append(v)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if h[p].x <= h[i].x:
			break
		var tmp: Variant = h[p]
		h[p] = h[i]
		h[i] = tmp
		i = p


static func _heap_pop(h: Array) -> Vector2:
	var top: Vector2 = h[0]
	var last: Vector2 = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := 2 * i + 2
			var m := i
			if l < h.size() and h[l].x < h[m].x:
				m = l
			if r < h.size() and h[r].x < h[m].x:
				m = r
			if m == i:
				break
			var tmp: Variant = h[i]
			h[i] = h[m]
			h[m] = tmp
			i = m
	return top
