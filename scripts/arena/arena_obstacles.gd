class_name ArenaObstacles
extends RefCounted

## Builds an arena's interior obstacle set from authored data: pillars and rubble blocks that
## are simultaneously a StaticBody3D (so the player and every enemy collide with them), a
## stone mesh, and a nav-grid blocker — three views of one `ArenaObstaclePlacement`, which is
## the whole point of the type.
##
## This file used to *be* the layout system: `layout_for(arena_id, half)` opened with
## `match String(arena_id)` and returned `{"pos", "half_size", "kind"}` Dictionaries, with a
## `_:` arm handing every arena id nobody added the Pit's layout, scaled to the new floor. The
## failure modes were silent by construction: a new arena's obstacles were *borrowed*, a
## misspelt key defaulted to `Vector3.ZERO` (an obstacle at the centre, inside the landmark),
## and `test_nav_grid.gd`'s comment records the day a pos/half_size convention was already
## misread into blocking the wrong cells. Layouts are now `ArenaConfig.obstacle_layout`,
## validated at load; this file keeps only the geometry, the shared defaults and the
## documented fallback for an arena that deliberately authors none.

## The two sizes the shipped arenas author: a full-height column that blocks the lane and
## sight, and a low rubble block that reads as cover. Used by the fallback layout below.
const PILLAR_HALF := Vector3(0.8, 1.5, 0.8)
const BLOCK_HALF := Vector3(0.7, 1.15, 0.7)
## The fallback layout is expressed against a 12 m interior and scaled, because an arena that
## authors nothing has no size to contradict: the pattern is meant to be proportional.
const FALLBACK_REFERENCE_HALF := 12.0
const FALLBACK_MIN_SCALE := 0.25
const FALLBACK_MAX_SCALE := 4.0


## The set an arena will actually contain, expanded for symmetry, in authoring order.
## `config == null` (an arena scene with no .tres, e.g. a greybox) falls back too, so the
## interior is never empty-by-accident.
static func layout_for(config: ArenaConfig, half: float) -> Array[ArenaObstaclePlacement]:
	if config == null or config.obstacle_layout.is_empty():
		return expand(fallback_layout(half))
	return expand(config.obstacle_layout)


## Turn authored placements into the placed set, mirroring as each one asks. Returns copies at
## their final positions (never the authored resources) so nothing downstream can write
## through a shared resource — the rule in Godot is duplicate first, mutate second.
static func expand(placements: Array[ArenaObstaclePlacement]) -> Array[ArenaObstaclePlacement]:
	var out: Array[ArenaObstaclePlacement] = []
	for p in placements:
		if p == null:
			continue
		for pos in p.mirrored_positions():
			out.append(p.duplicate_at(pos))
	return out


## The Pit's own geometry, expressed once as two authored placements: corner pillars (mirrored
## into all four) plus a twin-block gate on the X axis. `layout_for` runs it through `expand`,
## so it is the same shape an authored layout takes. Used for any arena that authors no
## `obstacle_layout`, exactly as the old `_:` arm used the same numbers, and scaled from the
## reference half so a bigger floor keeps the same proportions.
static func fallback_layout(half: float) -> Array[ArenaObstaclePlacement]:
	var s := clampf(half / FALLBACK_REFERENCE_HALF, FALLBACK_MIN_SCALE, FALLBACK_MAX_SCALE)
	var out: Array[ArenaObstaclePlacement] = []
	var corners := _make(Vector3(6.5 * s, 0.0, 6.5 * s), PILLAR_HALF * s)
	corners.mirror = ArenaObstaclePlacement.MIRROR_BOTH
	out.append(corners)
	var gate := _make(Vector3(3.6 * s, 0.0, 0.0), BLOCK_HALF * s)
	gate.mirror = ArenaObstaclePlacement.MIRROR_X
	out.append(gate)
	return out


## The blockers handed to ArenaNavGrid. AABBs, not key-bags: the grid's job is "which cells are
## covered", and an AABB cannot be read with the wrong convention.
## Whether a footprint box actually removes cells from the nav grid. Written out rather than borrowed
## from the engine type for two reasons: `AABB` has no `has_area()` (it spells it `has_volume()`, and
## calling the wrong one is a *parse* error that fails the whole script, so the arena does not load at
## all), and neither word means what a nav grid needs. The grid is a 2D coverage map: a box's height
## cannot block a cell, while a box with no x or z extent covers nothing however tall it is. A
## non-finite size fails both comparisons, which is the same refusal `ArenaNavGrid.build` applies.
static func blocks_nav(box: AABB) -> bool:
	return box.size.x > 0.0 and box.size.z > 0.0


static func footprints(entries: Array[ArenaObstaclePlacement]) -> Array[AABB]:
	var out: Array[AABB] = []
	for e in entries:
		if e != null:
			out.append(e.footprint())
	return out


## Turn a layout into StaticBody3D nodes under `parent`, each on
## CollisionLayers.WORLD_BODY_LAYER (the layer BOTH PLAYER_BODY_MASK and ENEMY_BODY_MASK
## collide with) with a stone box mesh. Returns the number of bodies created.
## Deterministic function of (parent, layout, material) — no autoload access, no config lookup,
## so headless node tests can build the real obstacle set and assert on it.
static func build_nodes(parent: Node3D, layout: Array[ArenaObstaclePlacement], material: Material = null) -> int:
	var count := 0
	for ob in layout:
		if ob == null:
			continue
		var hs := ob.half_extents()
		var body := StaticBody3D.new()
		body.name = "Obstacle"
		body.collision_layer = CollisionLayers.WORLD_BODY_LAYER
		body.collision_mask = CollisionLayers.NO_LAYER
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = hs * 2.0
		shape.shape = box
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = hs * 2.0
		if material != null:
			mesh.material_override = material
		body.add_child(mesh)
		body.position = Vector3(ob.position.x, hs.y, ob.position.z)
		parent.add_child(body)
		count += 1
	return count


static func _make(at: Vector3, half: Vector3) -> ArenaObstaclePlacement:
	var p := ArenaObstaclePlacement.new()
	p.position = at
	p.half_size_x = half.x
	p.half_size_y = half.y
	p.half_size_z = half.z
	return p
