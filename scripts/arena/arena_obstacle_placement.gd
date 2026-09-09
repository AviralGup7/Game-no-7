class_name ArenaObstaclePlacement
extends Resource

## One obstacle in an arena's interior layout: where it is, how big it is, what it looks
## like, and how it repeats. Lives in `ArenaConfig.obstacle_layout`.
##
## Before this existed the layouts were a `match String(arena_id)` table in
## `ArenaObstacles` emitting `{"pos":…, "half_size":…, "kind":…}` Dictionaries, which both
## arenas and consumers read with `ob.get("pos", Vector3.ZERO)`. Two failure modes came from
## that shape: a layout for an arena nobody added silently got *The Pit's* obstacles at a
## scaled distance (wrong for any other floor), and a typo'd or missing key silently became a
## default — an obstacle at the origin, inside the landmark, that nothing complained about.
## `ArenaNavGrid.build`'s own comment records the day a footprint convention was already
## misread once. This type is the fix on both sides: the numbers are authored data, validated
## at load, and the geometry crosses API boundaries as an `AABB`, not as a bag of keys.
##
## There is deliberately no `kind` field: the old records carried one that nothing read (the
## builder picked nothing by it — a column and a rubble block were only ever different sizes),
## and an unread field is a field that can lie. Height and material are authored where they are
## used: `half_size_y` and the arena's one stone material.
##
## Same shape as HazardPlacement / WaveSpawnEntry: nested typed entry resource, own
## validate(), own duplicate for expansion, one geometry override rather than a re-declaration.

## Symmetry ids are shared with HazardPlacement on purpose (see the python regression suite,
## which pins the two vocabularies against each other): one arena reads as one coordinate
## system, and a 4-fold symmetric layout is one line per distinct obstacle, not four.
const MIRROR_NONE := &"none"
const MIRROR_X := &"x"              ## plus the copy at (-x, z)
const MIRROR_Z := &"z"              ## plus the copy at (x, -z)
const MIRROR_BOTH := &"both"        ## all four quadrants
const MIRROR_ROT180 := &"rot180"    ## plus the point-symmetric copy at (-x, -z)
const VALID_MIRRORS := [MIRROR_NONE, MIRROR_X, MIRROR_Z, MIRROR_BOTH, MIRROR_ROT180]

## Authored centre in arena-local metres. Y is ignored for the footprint: obstacles stand on
## the floor and their height is `half_size_y` above it.
@export var position: Vector3 = Vector3.ZERO
@export_range(0.05, 8.0, 0.05) var half_size_x: float = 0.8
@export_range(0.05, 8.0, 0.05) var half_size_y: float = 1.5
@export_range(0.05, 8.0, 0.05) var half_size_z: float = 0.8
@export var mirror: StringName = MIRROR_NONE


func half_extents() -> Vector3:
	return Vector3(half_size_x, half_size_y, half_size_z)


func mirrored_positions() -> Array[Vector3]:
	var out: Array[Vector3] = [position]
	match mirror:
		MIRROR_X:
			out.append(Vector3(-position.x, position.y, position.z))
		MIRROR_Z:
			out.append(Vector3(position.x, position.y, -position.z))
		MIRROR_ROT180:
			out.append(Vector3(-position.x, position.y, -position.z))
		MIRROR_BOTH:
			out.append(Vector3(-position.x, position.y, position.z))
			out.append(Vector3(position.x, position.y, -position.z))
			out.append(Vector3(-position.x, position.y, -position.z))
	return out


## The single geometry the nav grid and the collision body agree on. An AABB, because that
## is the question the grid asks ("which cells are covered") and the old (pos, half_size)
## pair invited the centre-vs-min-corner misreading documented above.
func footprint() -> AABB:
	var hs := half_extents()
	return AABB(position - hs, hs * 2.0)


func duplicate_at(at: Vector3) -> ArenaObstaclePlacement:
	var copy := duplicate(true) as ArenaObstaclePlacement
	copy.position = at
	copy.mirror = MIRROR_NONE
	return copy


func validate() -> Array[String]:
	var problems: Array[String] = []
	if mirror not in VALID_MIRRORS:
		problems.append("unknown obstacle mirror '%s'" % String(mirror))
	if half_size_x <= 0.05 or half_size_z <= 0.05 or half_size_y <= 0.05:
		problems.append("obstacle half extents must be > 0.05 on every axis (a flat box blocks nothing and trips the shape server)")
	if not is_finite(position.x) or not is_finite(position.z) or not is_finite(half_size_x) \
			or not is_finite(half_size_y) or not is_finite(half_size_z):
		problems.append("an obstacle geometry number is not finite")
	return problems
