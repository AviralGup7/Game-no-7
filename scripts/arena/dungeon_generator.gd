class_name DungeonGenerator
extends RefCounted

## Deterministic structural shell for the merged dungeon.
##
## The game used to ship three separate arenas (`default_arena`, `ember_crucible`,
## `frost_hollow`) as three flat, open floors. They are now one map — a single large
## dungeon — so this file owns the *structure* that turns a flat floor into rooms: a
## central Grand Hall ringed by four antechambers (north, south, east, west), each
## connected to the hall by a door gap and each carrying its own theme (see
## ArenaConfig.extra_landmarks + the merged hazard/obstacle layouts).
##
## The generator is pure and deterministic: the same call always returns the same walls.
## Every wall it emits is a floor-standing box with the same three views the authored
## obstacles have — a StaticBody3D (physics), a mesh (visual) and an AABB footprint
## (nav grid). `Arena._build_dungeon_shell` turns this one list into all three so the
## three cannot disagree, exactly as `ArenaObstacles` does for `ArenaConfig.obstacle_layout`.
##
## The outer shell (floor, perimeter walls, corner towers, north dock yard) stays as the
## scene authors it; the walls below are interior walls added inside that shell.

## Wall + door geometry. The four ring walls sit at ±HALL_HALF on the X and Z axes and
## each carries one centred 4 m doorway, so the hall opens onto every wing.
const WALL_HEIGHT := 4.0
const WALL_THICKNESS := 2.0
const DOOR_GAP := 4.0
const HALL_HALF := 10.0


## One interior wall segment. `size` is the full box extent (x, y, z); `position` is its
## centre with y already at half height so the box sits on the floor.
class Wall:
	var position: Vector3 = Vector3.ZERO
	var size: Vector3 = Vector3.ONE


	func footprint() -> AABB:
		return AABB(position - size * 0.5, size)


## The complete wall list for the merged dungeon: four ring walls, each split into the two
## segments that flank its doorway. Order is stable (north, south, west, east) so a test
## can pin the set.
static func walls() -> Array[Wall]:
	var out: Array[Wall] = []
	var length := HALL_HALF * 2.0
	var mid_y := WALL_HEIGHT * 0.5
	out.append_array(_split_with_door(Vector3(0.0, mid_y, -HALL_HALF), length, true))
	out.append_array(_split_with_door(Vector3(0.0, mid_y, HALL_HALF), length, true))
	out.append_array(_split_with_door(Vector3(-HALL_HALF, mid_y, 0.0), length, false))
	out.append_array(_split_with_door(Vector3(HALL_HALF, mid_y, 0.0), length, false))
	return out


## Footprints of every wall, ready for `ArenaNavGrid.build` (same shape `ArenaObstacles`
## produces for the authored layout).
static func footprints() -> Array[AABB]:
	var out: Array[AABB] = []
	for w in walls():
		out.append(w.footprint())
	return out


## One wall centred on `center`, running along X (`along_x`) or Z, cut into two segments by
## a centred `DOOR_GAP` doorway.
static func _split_with_door(center: Vector3, length: float, along_x: bool) -> Array[Wall]:
	var out: Array[Wall] = []
	var half := length * 0.5
	var gap_half := DOOR_GAP * 0.5
	var spans: Array[Vector2] = [
		Vector2(-half, -gap_half),
		Vector2(gap_half, half),
	]
	for pair in spans:
		var lo: float = pair.x
		var hi: float = pair.y
		var mid := (lo + hi) * 0.5
		var seg_len := hi - lo
		var w := Wall.new()
		if along_x:
			w.position = Vector3(center.x + mid, center.y, center.z)
			w.size = Vector3(seg_len, WALL_HEIGHT, WALL_THICKNESS)
		else:
			w.position = Vector3(center.x, center.y, center.z + mid)
			w.size = Vector3(WALL_THICKNESS, WALL_HEIGHT, seg_len)
		out.append(w)
	return out
