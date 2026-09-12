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
var _world_min := Vector2(-12.0, -12.0)
var _conservative_los := false

# Fixed 8-neighbor order. South (+z / +cell.y) is first so equal-cost detours
# around a wall symmetric about z=0 pick the cheap south lane deterministically
# (the start cell sits at z=+0.25, so south is the short way around).
const NEIGHBORS: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, 0),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, -1),
]


## `blockers` are world-space AABBs in arena-local metres — the same boxes the collision
## bodies are built from (ArenaObstaclePlacement.footprint, ArenaLandmarkConfig.footprint).
## They used to arrive as `{"pos", "half_size"}` Dictionaries, and the convention was read
## wrong once: `pos` treated as the min corner silently shifted every footprint by +half on
## each axis (a wall at x∈[4,8] became x∈[5.75,10.75]), blocking cells nothing occupied and
## leaving the real ones open. An AABB has no second reading.
func build(half_extent: float, cell_size_value: float, blockers: Array[AABB]) -> void:
	half = clampf(half_extent, 2.0, 200.0)
	_world_min = Vector2(-half, -half)
	_conservative_los = false
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
	for box in blockers:
		var p := box.position
		var s := box.size
		if not (is_finite(p.x) and is_finite(p.z) and is_finite(s.x) and is_finite(s.z)):
			continue
		_mark_blocked(box.grow(AGENT_MARGIN))
		obstacle_count += 1
	_built = true


## Coarse shared campaign navigation. Unauthored void is blocked, rather than
## treating the huge bounding rectangle as a walkable square. At 4 m/cell the
## full station is under 6,000 cells; one field serves every active encounter.
func build_world(bounds: Rect2, regions: Array[Rect2], blockers: Array[AABB]) -> void:
	_built = false
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x <= 0 or bounds.size.y <= 0 or bounds.size.x > 512 or bounds.size.y > 512:
		return
	_world_min = bounds.position
	_conservative_los = true
	half = maxf(bounds.size.x, bounds.size.y) * 0.5
	cell_size = 4.0
	width = ceili(bounds.size.x / cell_size)
	depth = ceili(bounds.size.y / cell_size)
	_built = false
	if width <= 0 or depth <= 0 or width * depth > 8192:
		return
	_blocked.resize(width * depth)
	_blocked.fill(1)
	_flow_dist.resize(width * depth)
	_flow_dist.fill(INF)
	_flow_target = Vector2i(-1, -1)
	for z in range(depth):
		for x in range(width):
			var at := cell_center(Vector2i(x, z))
			for region in regions:
				if region.has_point(Vector2(at.x, at.z)):
					_blocked[z * width + x] = 0
					break
	obstacle_count = blockers.size()
	for box in blockers:
		_mark_blocked(box.grow(AGENT_MARGIN + cell_size * 0.5))
	_built = true



## Mark every cell whose CENTER falls inside `aabb` as blocked.
##
## Naively converting the box corners to their containing cells is off by one:
## cell_center(c) == (c+0.5)*cell_size - half, so the cell that merely CONTAINS
## the max corner has its center up to one cell OUTSIDE the box. That overshoot
## blocked one extra row/column per face, so a ray that cleared the wall by a
## few tenths of a cell (e.g. "LOS open over the wall") was still reported as
## intersecting a blocked cell. Mark exactly the cells whose centers lie inside.
func _mark_blocked(aabb: AABB) -> void:
	var c0 := _clamp_cell(Vector2i(
		ceili((aabb.position.x - _world_min.x) / cell_size - 0.5),
		ceili((aabb.position.z - _world_min.y) / cell_size - 0.5)))
	var c1 := _clamp_cell(Vector2i(
		floori((aabb.end.x - _world_min.x) / cell_size - 0.5),
		floori((aabb.end.z - _world_min.y) / cell_size - 0.5)))
	for z in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			_blocked[z * width + x] = 1


func is_built() -> bool:
	return _built


func to_cell(pos: Vector3) -> Vector2i:
	var cx := int(floorf((pos.x - _world_min.x) / cell_size))
	var cz := int(floorf((pos.z - _world_min.y) / cell_size))
	return Vector2i(clampi(cx, 0, width - 1), clampi(cz, 0, depth - 1))


func cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * cell_size + _world_min.x, 0.0, (c.y + 0.5) * cell_size + _world_min.y)


func is_walkable(pos: Vector3) -> bool:
	if not _built:
		return false
	if not is_finite(pos.x) or not is_finite(pos.z):
		return false
	if pos.x < _world_min.x or pos.z < _world_min.y or pos.x >= _world_min.x + width * cell_size or pos.z >= _world_min.y + depth * cell_size:
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
		var idx := int(top.y)
		var cost := top.x
		if cost > _flow_dist[idx] + 1.0e-6:
			continue  # stale entry
		var c := Vector2i(idx % width, int(idx / float(width)))
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
	var best_tie := -1.0e9
	for n in NEIGHBORS:
		var nc := c + n
		if nc.x < 0 or nc.y < 0 or nc.x >= width or nc.y >= depth:
			continue
		var ni := nc.y * width + nc.x
		if _blocked[ni] != 0:
			continue
		# Field lookup must obey the same no-corner-cut rule as field building.
		if n.x != 0 and n.y != 0:
			if is_blocked_cell(c + Vector2i(n.x, 0)) or is_blocked_cell(c + Vector2i(0, n.y)):
				continue
		var nd := _flow_dist[ni]
		# Tie-break: prefer south (+z) then east (+x) so a symmetric wall
		# always yields the same, cheaper southern detour.
		var tie := float(n.y) * 10.0 + float(n.x)
		if nd < best_d - 1.0e-6 or (absf(nd - best_d) <= 1.0e-6 and tie > best_tie):
			best = ni
			best_d = nd
			best_tie = tie
	if best == i:
		return Vector3.ZERO
	var center := cell_center(c)
	var next_center := cell_center(Vector2i(best % width, int(best / float(width))))
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

## Supercover / Amanatides-Woo grid walk. Sampling cell centers can clip a
## blocked cell whose square contains a sample even when the ray clears the wall.
func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	if not _built:
		return true  # no grid -> assume open (callers fall back to physics)
	if not is_walkable(from) or not is_walkable(to):
		return false
	var a := to_cell(from)
	var b := to_cell(to)
	if a == b:
		return true
	var x := a.x
	var z := a.y
	var x2 := b.x
	var z2 := b.y
	var dx := absi(x2 - x)
	var dz := absi(z2 - z)
	var sx := 1 if x2 >= x else -1
	var sz := 1 if z2 >= z else -1
	var err := dx - dz
	var n := dx + dz
	for _i in range(n + 1):
		if is_blocked_cell(Vector2i(x, z)):
			return false
		if x == x2 and z == z2:
			break
		var e2 := err * 2
		# At the coarse campaign resolution, string-pulling/vision may not
		# cut diagonally between a wall and void. Legacy fine-grid LOS retains
		# its established boundary semantics.
		if _conservative_los and e2 > -dz and e2 < dx:
			if is_blocked_cell(Vector2i(x + sx, z)) or is_blocked_cell(Vector2i(x, z + sz)):
				return false
		if e2 > -dz:
			err -= dz
			x += sx
		if e2 < dx:
			err += dx
			z += sz
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
		var idx := int(top.y)
		if closed[idx] != 0:
			continue
		closed[idx] = 1
		if idx == goal_i:
			break
		var c := Vector2i(idx % width, int(idx / float(width)))
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
			# Light clearance tax: hugging a blocked face is legal but costs extra
			# so A* prefers a one-cell lateral detour around slabs instead of
			# string-pulling a waypoint onto the inflated wall edge.
			var tax := 0.0
			if _cell_touches_blocked(nc):
				tax = 0.35
			var ng := g[idx] + step + tax
			if ng < g[ni] - 1.0e-6:
				g[ni] = ng
				came[ni] = idx
				_heap_push(heap, Vector2(ng + _heuristic(nc, tc), float(ni)))
	if came[goal_i] == -1:
		return empty
	# Reconstruct (goal -> start), convert to world waypoints (start excluded).
	var cells: PackedVector3Array = PackedVector3Array()
	var cur := goal_i
	while cur != start_i and cur != -1:
		cells.append(cell_center(Vector2i(cur % width, int(cur / float(width)))))
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


func _cell_touches_blocked(c: Vector2i) -> bool:
	for n in NEIGHBORS:
		if n.x != 0 and n.y != 0:
			continue
		var nc := c + n
		if is_blocked_cell(nc):
			return true
	return false


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
		var p := int((i - 1) / 2.0)
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
