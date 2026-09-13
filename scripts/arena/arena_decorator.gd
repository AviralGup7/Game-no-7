class_name ArenaDecorator
extends Node3D

## Deterministic cosmetic dressing built from the checksum-locked Kenney station prop subset
## (assets/environment/space_station/**), giving each arena a distinct silhouette while
## keeping run-to-run placement identical (fair + testable).
##
## EVERY floor-standing prop is solid: structural pillars (line-of-sight blockers for
## ranged enemies) AND the scattered clutter (barrels, crates, boxes, rubble) and the
## brazier/torch rings. A prop the hero visibly walks through reads as a broken game,
## so each one gets a StaticBody3D on collision_layer 1 (the layer the player's mask 1
## and every enemy's mask 5 already collide with) sized from the mounted model's OWN
## AABB, and its footprint is registered with the shared nav grid so AI routes around
## what physics blocks — the same "nothing walks through objects" invariant as
## ArenaObstacles (see docs/ENEMY_AI_RESEARCH.md §3.1). Wall-hung banners stay
## visual-only: they are flat cloth against the arena shell, not floor obstacles.
##
## Every prop load is optional: if a source model is missing/unimported the decorator
## transparently falls back to a primitive so an arena is never left undecorated.
## Budgets are clamped for mobile; nothing here allocates particles or runs per frame.
##
## Collaborators (typed RefCounted helpers): `DecoratorProps` builds, mounts and
## collides every prop and owns the spawned/blocker ledgers; `ArenaWarehouseYard`
## builds the authored compound north of the Pit. This class keeps the per-arena
## compositions, the spot picking and the Arena-facing contract (blockers, clear,
## spawned_count), so the scenes, tests and Arena only ever talk to it.

const MAX_PILLARS := 8
const MAX_CLUTTER := 22
const MAX_WALL_PROPS := 8
const CENTER_CLEAR_RADIUS := 3.0
const PILLAR_CLEARANCE := 2.3
## Props (including colliding pillars) keep this far from the player spawn so a
## run can never start with the hero stuck inside decoration collision.
const SPAWN_CLEAR_RADIUS := 2.5
## Clutter props are solid now, so they must also keep clear of the enemy spawn
## markers: a collider sitting on a spawn would have the physics server push a
## spawning enemy out of it (and could trap it against a wall).
const SPAWN_MARKER_CLEAR_RADIUS := 1.7
const DUNGEON := "res://assets/environment/space_station/"
const SC_PILLAR := DUNGEON + "support.tscn"
const SC_PILLAR_DECOR := SC_PILLAR
const SC_COLUMN := SC_PILLAR
const SC_BANNER := {
    &"red": DUNGEON + "display-wall.glb",
    &"blue": DUNGEON + "display-wall.glb",
    &"green": DUNGEON + "display-wall.glb",
    &"yellow": DUNGEON + "display-wall.glb",
}
const SC_TORCH := DUNGEON + "computer.glb"
const SC_BOX := DUNGEON + "container.glb"
const SC_BOX_DECOR := SC_BOX
const SC_BOXSTACK := DUNGEON + "container-tall.glb"
const SC_CRATES := DUNGEON + "container-wide.glb"
const SC_BARREL := SC_BOX
const SC_BARREL_DECOR := SC_BOXSTACK
const SC_BARREL_STACK := SC_CRATES
const SC_RUBBLE := DUNGEON + "rocks.glb"
const SC_TRUNK := SC_CRATES
const SC_CANDLE3 := DUNGEON + "table-display.glb"
const SC_CANDLELIT := SC_TORCH
const SC_SWORD := SC_CANDLE3
const SC_SWORD_GOLD := SC_CANDLE3
## Sword trophies are centre-origin wall art (1.67 m tall): this seats their base on the floor.
const TROPHY_LIFT := 0.82
## Typed collaborators: the prop kit (build/mount/collide + the spawned/blocker
## ledgers) and the authored warehouse yard. The decorator owns the compositions,
## the spot picking and the public Arena contract.
var _props := DecoratorProps.new()
var _yard := ArenaWarehouseYard.new(_props)
var _rng := RngService.new()


func decorate(arena_id: StringName, arena_half: float, run_seed: int) -> void:
	clear()
	_rng.reseed(run_seed + hash(String(arena_id)) * 3)
	# Composition follows the live config/theme when the decorator sits under an
	# Arena (so a new .tres that reuses ember_crucible's theme gets the forge
	# dressing without a new match arm). The public arena_id argument remains
	# the seed mixer and the headless fallback.
	match String(_composition_id(arena_id)):
		"ember_crucible":
			_compose_ember(arena_half)
		"frost_hollow":
			_compose_frost(arena_half)
		_:
			_compose_default(arena_half)
	_publish_blockers()


func _composition_id(arena_id: StringName) -> StringName:
	var arena := get_parent() as Arena
	if arena != null:
		var cfg := arena.get_config()
		if cfg != null:
			if cfg.theme != null and not String(cfg.theme.theme_id).is_empty():
				return cfg.theme.theme_id
			if cfg.arena_id != &"":
				return cfg.arena_id
	return arena_id


func clear() -> void:
	_props.clear()


## Solid-prop footprints as world-space boxes, the shape `ArenaNavGrid.build()` and
## `Arena.register_decoration_blockers` take. AABB rather than a `{"pos","half_size"}` key-bag because
## the repo's rule for anything crossing a boundary is a typed record: a Dictionary key nobody reads is
## invisible, and a typo'd key is a runtime miss rather than a parse error. The authored obstacle
## placements in `Arena` travel the same way (as `ArenaObstaclePlacement`).
func get_nav_blockers() -> Array[AABB]:
	return _props.blockers()


## Hand the footprints to the owning Arena (the decorator is its direct child) so the
## nav grid is rebuilt with them. Null-safe for headless fixtures without an Arena.
func _publish_blockers() -> void:
	var arena := get_parent() as Arena
	if arena == null:
		return
	arena.register_decoration_blockers(_props.blockers())


func spawned_count() -> int:
	return _props.spawned().size()


# ---------------------- per-arena compositions — distinct silhouettes ----------------------

func _compose_default(half: float) -> void:
	# Warehouse sits NORTH of the Pit square. The north wall is gated so the
	# hero walks out of the yard into the docks. Coordinates are authored —
	# this composition does not scatter or pick open spots.
	_yard._build_warehouse_compound(self)
	_mount_trophy_pair(6.0, -16.0, SC_SWORD_GOLD, SC_SWORD)
	_mount_trophy_pair(-6.0, -16.0, SC_SWORD, SC_SWORD_GOLD)
	# Aisles inside the warehouse (outside the square).
	_yard._place_column_at(self, Vector3(-8.0, 0.0, -28.5), SC_PILLAR)
	_yard._place_column_at(self, Vector3(8.0, 0.0, -28.5), SC_PILLAR)
	_yard._place_column_at(self, Vector3(-8.0, 0.0, -23.5), SC_PILLAR)
	_yard._place_column_at(self, Vector3(8.0, 0.0, -23.5), SC_PILLAR)
	_mount_prop(SC_CRATES, Vector3(-11.5, 0.0, -29.5), 0.65)
	_mount_prop(SC_BOXSTACK, Vector3(-11.5, 0.0, -26.5), 0.55)
	_mount_prop(SC_CRATES, Vector3(-11.5, 0.0, -23.5), 0.65)
	_mount_prop(SC_BARREL_STACK, Vector3(-13.2, 0.0, -26.5), 0.95)
	_mount_prop(SC_CRATES, Vector3(11.5, 0.0, -29.5), 0.65)
	_mount_prop(SC_BOXSTACK, Vector3(11.5, 0.0, -26.5), 0.55)
	_mount_prop(SC_CRATES, Vector3(11.5, 0.0, -23.5), 0.65)
	_mount_prop(SC_BARREL, Vector3(13.2, 0.0, -26.5), 1.05)
	# Pit apron south of the gate, then two stacks on the south yard.
	_mount_prop(SC_BOXSTACK, Vector3(-10.0, 0.0, 8.0), 0.55)
	_mount_prop(SC_BOXSTACK, Vector3(10.0, 0.0, 8.0), 0.55)
	_mount_prop(SC_BARREL_DECOR, Vector3(-6.5, 0.0, 14.8), 1.0)
	_mount_prop(SC_BARREL, Vector3(6.5, 0.0, 14.8), 1.0)
	_wall_props(half, &"red", false)
	for i in range(4):
		var angle := i * TAU / 4.0 + 0.3
		var at := Vector3(cos(angle) * 2.8, 0, sin(angle) * 2.8)
		_mount_prop(SC_RUBBLE, at, 0.9 + float(i) * 0.12)


func _compose_ember(half: float) -> void:
	# Forge crucible: dense, hot, vertical — decorated pillars + many barrels/crates as fuel.
	_place_structural(6, half, SC_PILLAR_DECOR)
	_scatter(18, half, [SC_BARREL_DECOR, SC_BARREL, SC_BARREL_STACK, SC_CRATES, SC_BOX, SC_RUBBLE])
	_wall_props(half, &"yellow", true)
	# Ring of braziers around the central forge — strong emissive read from distance.
	for i in range(5):
		var angle := i * TAU / 5.0
		var at := Vector3(cos(angle) * 3.0, 0, sin(angle) * 3.0)
		_mount_prop(SC_TORCH, at, 1.35)
	# Extra fuel stacks near walls.
	_scatter(4, half, [SC_BARREL_STACK, SC_CRATES])
	# Crate depots: the stacked-crate model is room-scale at 1.0, so it gets deliberate
	# open-spot placements at depot scale instead of a scatter-pool slot.
	for _i in range(2):
		_mount_prop(SC_BOXSTACK, _open_spot(half, 2.5), 0.55)


func _compose_frost(half: float) -> void:
	# Frost hollow: sparse, cold, tall columns — open sightlines for ranged.
	_place_structural(7, half, SC_COLUMN)
	_scatter(12, half, [SC_RUBBLE, SC_TRUNK, SC_BOX, SC_RUBBLE])
	_wall_props(half, &"blue", false)
	# Ice shard ring around the crystal cluster (blue banners already on walls).
	for i in range(3):
		var angle := i * TAU / 3.0 + PI / 6.0
		var at := Vector3(cos(angle) * 2.2, 0, sin(angle) * 2.2)
		var holder := Node3D.new()
		holder.position = at
		var prism := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.45, 1.1, 0.45)
		prism.mesh = pm
		prism.rotation.y = angle
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.68, 0.82, 1.0, 0.85)
		cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cmat.roughness = 0.12
		cmat.emission_enabled = true
		cmat.emission = Color(0.35, 0.65, 1.0)
		cmat.emission_energy_multiplier = 1.2
		prism.material_override = cmat
		holder.add_child(prism)
		add_child(holder)
		_props.adopt(holder)
		_props._add_prop_collision(holder)
	# Lit candle ring interleaved with the shards — cold light points, emissive only.
	for i in range(3):
		var candle_angle := float(i) * TAU / 3.0 + PI / 2.0
		var candle_at := Vector3(cos(candle_angle) * 2.55, 0, sin(candle_angle) * 2.55)
		_mount_prop(SC_CANDLELIT, candle_at, 1.0)


# ---------------------- builders ----------------------



func _place_structural(count: int, half: float, scene_path: String) -> void:
	for i in range(mini(count, MAX_PILLARS)):
		var at := _open_spot(half, 2.0)
		var body := StaticBody3D.new()
		body.position = at
		body.add_to_group("world_static")
		body.collision_layer = CollisionLayers.WORLD_BODY_LAYER
		body.collision_mask = CollisionLayers.NO_LAYER
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.4, 4.0, 1.4)
		shape.shape = box
		shape.position.y = 2.0
		body.add_child(shape)
		# Model visual (idempotent: falls back to primitives automatically).
		if not _props._mount_model(body, scene_path, 0.0, 1.0):
			_props._primitive_pillar(body)
		add_child(body)
		_props.adopt(body)
		# `foot_half`, not `half`: the enclosing function's own parameter is the arena's half-extent and
		# shadowing it is a parse error ("There is already a parameter named \"half\"").
		var foot_half := Vector3(box.size.x * 0.5, box.size.y * 0.5, box.size.z * 0.5)
		# The collider is offset up by shape.position.y, so the box is too. `ArenaNavGrid` reads only x
		# and z, but a footprint that lies about height is a bug waiting for the next reader.
		_props.add_blocker(AABB(at + Vector3(0.0, shape.position.y, 0.0) - foot_half, foot_half * 2.0))


## Scattered floor clutter (barrels / crates / boxes / rubble). Solid: each prop gets
## a collider sized from its own imported mesh plus a nav-grid footprint.
func _scatter(count: int, half: float, choices: Array) -> void:
	for i in range(mini(count, MAX_CLUTTER)):
		var at := _open_spot(half, 1.0)
		var path: String = choices[i % choices.size()]
		var s := _rng.randf_range(RngService.STREAM_ARENA, 0.85, 1.25)
		var yaw := _rng.randf_range(RngService.STREAM_COSMETIC, -PI, PI)
		var holder := Node3D.new()
		holder.position = at
		if not _props._mount_model(holder, path, 0.0, s):
			_props._primitive_rock(holder, s)
		holder.rotation.y = yaw
		add_child(holder)
		_props.adopt(holder)
		# After the yaw is final: the collider inherits the holder's rotation, and the
		# nav footprint below is expanded to the rotated box's axis-aligned bounds.
		_props._add_prop_collision(holder)


## Banners / torches set along the arena walls (visual only).
func _wall_props(half: float, banner: StringName, add_torches: bool) -> void:
	var banner_scene: String = SC_BANNER.get(banner, SC_BANNER[&"red"])
	var count := mini(MAX_WALL_PROPS, 8)
	for i in range(count):
		var angle := TAU * float(i) / float(count)
		var at := Vector3(cos(angle) * (half - 0.4), 0, sin(angle) * (half - 0.4))
		var holder := Node3D.new()
		holder.position = at
		holder.rotation.y = -angle
		var path := banner_scene if not add_torches or i % 2 == 0 else SC_TORCH
		if not _props._mount_model(holder, path, 0.0, 1.0):
			if add_torches and i % 2 == 1:
				_props._primitive_brazier(holder)
			else:
				_props._primitive_banner(holder)
		add_child(holder)
		_props.adopt(holder)



## Player spawn in arena-local coordinates (the decorator sits at the arena
## origin, so marker positions compare directly). Null when unknown (headless).
func _player_spawn_local() -> Variant:
	var arena := get_parent() as Arena
	if arena != null:
		var marker := arena.get_player_start()
		if marker != null:
			return marker.position
	return null


## An open spot away from centre, the player spawn, the enemy spawn markers, and
## previously-placed props.
func _open_spot(half: float, margin: float) -> Vector3:
	var spawn: Variant = _player_spawn_local()
	var markers := _spawn_marker_positions()
	for _attempt in range(24):
		var p := _rng.point_in_disc(RngService.STREAM_ARENA, half - margin)
		if Vector2(p.x, p.z).length() < CENTER_CLEAR_RADIUS:
			continue
		if spawn != null and Vector2(p.x - spawn.x, p.z - spawn.z).length() < SPAWN_CLEAR_RADIUS:
			continue
		var on_marker := false
		for m in markers:
			if Vector2(p.x - m.x, p.z - m.z).length() < SPAWN_MARKER_CLEAR_RADIUS:
				on_marker = true
				break
		if on_marker:
			continue
		var blocked := false
		for n in _props.spawned():
			# Use local position — global_position is not yet valid for nodes
			# just added this frame (transform propagation is deferred).
			if (n as Node3D).position.distance_to(p) < PILLAR_CLEARANCE:
				blocked = true
				break
		if not blocked:
			return p
	return Vector3(half - margin, 0, half - margin)


## Enemy spawn markers in arena-local XZ (the decorator sits at the arena origin, so
## marker positions compare directly with prop positions). Empty in headless fixtures.
func _spawn_marker_positions() -> Array:
	var out: Array = []
	var arena := get_parent() as Arena
	if arena == null:
		return out
	for marker in arena.get_spawn_points():
		if is_instance_valid(marker):
			out.append((marker as Node3D).position)
	return out


## Stand-alone decorative prop (braziers / torch rings) placed at a world position.
## Solid like the scattered clutter.
func _mount_prop(path: String, at: Vector3, scale_factor: float) -> void:
	var holder := Node3D.new()
	holder.position = at
	if not _props._mount_model(holder, path, 0.0, scale_factor):
		_props._primitive_brazier(holder)
	add_child(holder)
	_props.adopt(holder)
	_props._add_prop_collision(holder)


## Two flat trophy pieces mounted back to back so a front face reads from either side
## (KayKit sword trophies are single-sided wall art with a centre origin: one mount
## would be invisible from behind). One collider + one nav footprint for the pair.
func _mount_trophy_pair(x: float, z: float, face_a: String, face_b: String) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(x, 0.0, z)
	var south := Node3D.new()
	holder.add_child(south)
	if not _props._mount_model(south, face_a, TROPHY_LIFT, 1.0):
		_props._primitive_rock(south, 1.2)
	var north := Node3D.new()
	north.rotation.y = PI
	holder.add_child(north)
	if not _props._mount_model(north, face_b, TROPHY_LIFT, 1.0):
		_props._primitive_rock(north, 1.2)
	add_child(holder)
	_props.adopt(holder)
	_props._add_prop_collision(holder)


# ---------------------- prop collision (solid decoration) ----------------------

func apply_prestige_banners(arena_half: float, unlocked: Array) -> void:
	var banners := Cosmetics.active_banners(unlocked)
	if banners.is_empty():
		return
	# Place one per banner, evenly spaced on the wall ring, offset from the
	# generic wall props so both read clearly.
	var count := banners.size()
	for i in range(count):
		var angle := TAU * float(i) / float(count) + PI / float(maxi(count, 1))
		var at := Vector3(cos(angle) * (arena_half - 0.35), 0, sin(angle) * (arena_half - 0.35))
		var holder := Node3D.new()
		holder.name = "PrestigeBanner_%d" % i
		holder.position = at
		holder.rotation.y = -angle
		_props._prestige_banner_cloth(holder, Cosmetics.color_of(banners[i]))
		add_child(holder)
		_props.adopt(holder)


