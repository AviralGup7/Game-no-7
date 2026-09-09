class_name ArenaObstacles
extends RefCounted

## Deterministic interior obstacle layouts per arena. Pure data + static math —
## the Arena node turns each entry into a StaticBody3D (collision_layer 1, so
## BOTH the player and every enemy collide with it) + a stone mesh, and feeds
## the same entries to ArenaNavGrid so AI routes around what it cannot clip.
##
## Layouts are hand-tuned against each arena's hazard layout (see
## ArenaHazards._layout_defaults) and its spawn markers: every obstacle keeps a
## comfortable clearance from spawn points, player start, hazard footprints and
## the central landmark so no actor can ever spawn or path onto them.

## Entry shape: {"pos": Vector3(center), "half_size": Vector3(half extent), "kind": StringName}
## kind "pillar" = full stone column, "block" = low rubble wall.
static func layout_for(arena_id: StringName, half: float) -> Array:
	var s := clampf(half / 12.0, 0.25, 4.0)
	var out: Array = []
	var pillar := Vector3(0.8, 1.5, 0.8)
	var block := Vector3(0.7, 1.15, 0.7)
	match String(arena_id):
		"ember_crucible":
			# Cardinal pillars make four approach lanes to the forge; the four
			# corner pillars break diagonal rushes. Clears all (±5,±5) vents
			# (r 2.2) and the (0,0) heal circle (r 2.5).
			# The four cardinal pillars ring the forge at radius 8.0 (was 8.5):
			# radius 8.5 sat each exactly 2.5 m from an axis enemy spawn at +-11
			# (interior half 12) = foot 0.8 + jitter 1.2 + safety 0.5, i.e. zero
			# margin; and f32 0.8 pushed the f64 threshold over 2.5, so the
			# jitter-proof spawn check tripped. Radius 8.0 leaves a real 0.5 m
			# margin while still clearing the center forge and its vents.
			_add(out, Vector3(8.0 * s, 0.0, 0.0), pillar, "pillar")
			_add(out, Vector3(-8.0 * s, 0.0, 0.0), pillar, "pillar")
			_add(out, Vector3(0.0, 0.0, 8.0 * s), pillar, "pillar")
			_add(out, Vector3(0.0, 0.0, -8.0 * s), pillar, "pillar")
			_add(out, Vector3(8.5 * s, 0.0, 8.5 * s), block, "block")
			_add(out, Vector3(-8.5 * s, 0.0, 8.5 * s), block, "block")
			_add(out, Vector3(8.5 * s, 0.0, -8.5 * s), block, "block")
			_add(out, Vector3(-8.5 * s, 0.0, -8.5 * s), block, "block")
		"frost_hollow":
			# Corner pillars + staggered mid pillars create two interleaved
			# lanes; clears ichor pools (±4,0) and heal circles (0,±4) r 2.5.
			_add(out, Vector3(7.5 * s, 0.0, 7.5 * s), pillar, "pillar")
			_add(out, Vector3(-7.5 * s, 0.0, 7.5 * s), pillar, "pillar")
			_add(out, Vector3(7.5 * s, 0.0, -7.5 * s), pillar, "pillar")
			_add(out, Vector3(-7.5 * s, 0.0, -7.5 * s), pillar, "pillar")
			_add(out, Vector3(4.5 * s, 0.0, 7.5 * s), block, "block")
			_add(out, Vector3(-4.5 * s, 0.0, 7.5 * s), block, "block")
			_add(out, Vector3(4.5 * s, 0.0, -7.5 * s), block, "block")
			_add(out, Vector3(-4.5 * s, 0.0, -7.5 * s), block, "block")
		_:
			# The Pit: four corner pillars + a twin-tower gate across the center
			# (a 4.4 m wide throat flanking the obelisk) that forces flanking.
			_add(out, Vector3(6.5 * s, 0.0, 6.5 * s), pillar, "pillar")
			_add(out, Vector3(-6.5 * s, 0.0, 6.5 * s), pillar, "pillar")
			_add(out, Vector3(6.5 * s, 0.0, -6.5 * s), pillar, "pillar")
			_add(out, Vector3(-6.5 * s, 0.0, -6.5 * s), pillar, "pillar")
			_add(out, Vector3(3.0 * s, 0.0, 0.0), block, "block")
			_add(out, Vector3(-3.0 * s, 0.0, 0.0), block, "block")
	return out


## Turn a layout into StaticBody3D nodes under `parent` (collision_layer 1 —
## the world layer BOTH the player (mask 1) and every enemy (mask 5) collide
## with) with a stone box mesh. Returns the number of bodies created.
## Deterministic function of (parent, layout, material) — no autoload access,
## so headless node tests can build the real obstacle set and assert on it.
static func build_nodes(parent: Node3D, layout: Array, material: Material = null) -> int:
	var count := 0
	for raw in layout:
		var ob: Dictionary = raw if raw is Dictionary else {}
		var hs: Vector3 = ob.get("half_size", Vector3(0.8, 1.5, 0.8))
		var pos: Vector3 = ob.get("pos", Vector3.ZERO)
		var body := StaticBody3D.new()
		body.name = "Obstacle"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = hs * 2.0
		shape.shape = box
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = hs * 2.0
		mesh.mesh = bm
		if material != null:
			mesh.material_override = material
		body.add_child(mesh)
		body.position = Vector3(pos.x, hs.y, pos.z)
		parent.add_child(body)
		count += 1
	return count


static func _add(out: Array, pos: Vector3, half_size: Vector3, kind: StringName) -> void:
	out.append({"pos": pos, "half_size": half_size, "kind": kind})
