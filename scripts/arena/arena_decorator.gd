class_name ArenaDecorator
extends Node3D

## Deterministic cosmetic dressing built from the approved KayKit dungeon prop library
## (assets/environment/dungeon/**), giving each arena a distinct silhouette while
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
## Sanity clamps for a prop collider derived from imported art. A corrupt/huge
## import must never produce a room-sized invisible wall.
const MIN_PROP_HALF := 0.18
const MAX_PROP_HALF_XZ := 1.4
const MAX_PROP_HALF_Y := 2.2

const DUNGEON := "res://assets/environment/dungeon/"
const SC_PILLAR := DUNGEON + "pillar.glb"
const SC_PILLAR_DECOR := DUNGEON + "pillar_decorated.glb"
const SC_COLUMN := DUNGEON + "column.glb"
## Per-arena wall identity: champion shield banners, one colour per arena (same hang
## convention as the plain banners they replace, so the wall ring code is untouched).
const SC_BANNER := {
	&"red": DUNGEON + "banner_shield_red.glb",
	&"blue": DUNGEON + "banner_shield_blue.glb",
	&"green": DUNGEON + "banner_green.glb",
	&"yellow": DUNGEON + "banner_shield_yellow.glb",
}
const SC_TORCH := DUNGEON + "torch_lit.glb"
const SC_BOX := DUNGEON + "box_large.glb"
const SC_BOX_DECOR := DUNGEON + "box_small_decorated.glb"
const SC_BOXSTACK := DUNGEON + "box_stacked.glb"
const SC_CRATES := DUNGEON + "crates_stacked.glb"
const SC_BARREL := DUNGEON + "barrel_large.glb"
const SC_BARREL_DECOR := DUNGEON + "barrel_large_decorated.glb"
const SC_BARREL_STACK := DUNGEON + "barrel_small_stack.glb"
const SC_RUBBLE := DUNGEON + "rubble_large.glb"
const SC_TRUNK := DUNGEON + "trunk_medium_A.glb"
const SC_CANDLE3 := DUNGEON + "candle_triple.glb"
const SC_CANDLELIT := DUNGEON + "candle_thin_lit.glb"
const SC_SWORD := DUNGEON + "sword_shield.glb"
const SC_SWORD_GOLD := DUNGEON + "sword_shield_gold.glb"
## Sword trophies are centre-origin wall art (1.67 m tall): this seats their base on the floor.
const TROPHY_LIFT := 0.82

var _spawned: Array[Node3D] = []
var _rng := RngService.new()
## Arena-local XZ footprints of every solid prop, published to the Arena so the
## shared nav grid blocks the same cells the colliders occupy.
var _blockers: Array[AABB] = []


func decorate(arena_id: StringName, arena_half: float, run_seed: int) -> void:
	clear()
	_rng.reseed(run_seed + hash(String(arena_id)) * 3)
	match String(arena_id):
		"ember_crucible":
			_compose_ember(arena_half)
		"frost_hollow":
			_compose_frost(arena_half)
		_:
			_compose_default(arena_half)
	_publish_blockers()


func clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	_blockers.clear()


## Solid-prop footprints as world-space boxes, the shape `ArenaNavGrid.build()` and
## `Arena.register_decoration_blockers` take. AABB rather than a `{"pos","half_size"}` key-bag because
## the repo's rule for anything crossing a boundary is a typed record: a Dictionary key nobody reads is
## invisible, and a typo'd key is a runtime miss rather than a parse error. The authored obstacle
## placements in `Arena` travel the same way (as `ArenaObstaclePlacement`).
func get_nav_blockers() -> Array[AABB]:
	return _blockers


## Hand the footprints to the owning Arena (the decorator is its direct child) so the
## nav grid is rebuilt with them. Null-safe for headless fixtures without an Arena.
func _publish_blockers() -> void:
	var arena := get_parent() as Arena
	if arena == null:
		return
	arena.register_decoration_blockers(_blockers)


func spawned_count() -> int:
	return _spawned.size()


# ---------------------- per-arena compositions — distinct silhouettes ----------------------

func _compose_default(half: float) -> void:
	# Ancient coliseum: balanced, readable — landmarks + scattered ruins.
	# Champion trophies flank the north gate first, so the scatter below routes around them.
	_mount_trophy_pair(3.0, -11.3, SC_SWORD_GOLD, SC_SWORD)
	_mount_trophy_pair(-3.0, -11.3, SC_SWORD, SC_SWORD_GOLD)
	_place_structural(5, half, SC_PILLAR)
	_scatter(16, half, [SC_RUBBLE, SC_BOX_DECOR, SC_TRUNK, SC_BARREL, SC_CRATES, SC_CANDLE3])
	_wall_props(half, &"red", false)
	# Weathered stone circle around the obelisk (4 small shards).
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
		_spawned.append(holder)
		_add_prop_collision(holder)
	# Lit candle ring interleaved with the shards — cold light points, emissive only.
	for i in range(3):
		var candle_angle := float(i) * TAU / 3.0 + PI / 2.0
		var candle_at := Vector3(cos(candle_angle) * 2.55, 0, sin(candle_angle) * 2.55)
		_mount_prop(SC_CANDLELIT, candle_at, 1.0)


# ---------------------- builders ----------------------

## Structural pillars get collision (LOS blockers). Uses model when available, else the
## legacy primitive pillar of matching footprint. Their footprint also joins the nav
## grid: previously only ArenaObstacles + the landmark were registered, so the AI's
## INTENT walked straight through these pillars even though physics stopped the body
## (the enemy then leaned on the pillar until the stuck-nudge freed it).
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
		if not _mount_model(body, scene_path, 0.0, 1.0):
			_primitive_pillar(body)
		add_child(body)
		_spawned.append(body)
		# `foot_half`, not `half`: the enclosing function's own parameter is the arena's half-extent and
		# shadowing it is a parse error ("There is already a parameter named \"half\"").
		var foot_half := Vector3(box.size.x * 0.5, box.size.y * 0.5, box.size.z * 0.5)
		# The collider is offset up by shape.position.y, so the box is too. `ArenaNavGrid` reads only x
		# and z, but a footprint that lies about height is a bug waiting for the next reader.
		_blockers.append(AABB(at + Vector3(0.0, shape.position.y, 0.0) - foot_half, foot_half * 2.0))


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
		if not _mount_model(holder, path, 0.0, s):
			_primitive_rock(holder, s)
		holder.rotation.y = yaw
		add_child(holder)
		_spawned.append(holder)
		# After the yaw is final: the collider inherits the holder's rotation, and the
		# nav footprint below is expanded to the rotated box's axis-aligned bounds.
		_add_prop_collision(holder)


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
		if not _mount_model(holder, path, 0.0, 1.0):
			if add_torches and i % 2 == 1:
				_primitive_brazier(holder)
			else:
				_primitive_banner(holder)
		add_child(holder)
		_spawned.append(holder)


func _centerish(_half: float, radius: float) -> Vector3:
	for _attempt in range(12):
		var p := _rng.point_in_disc(RngService.STREAM_ARENA, radius)
		if p.length() > CENTER_CLEAR_RADIUS * 0.9:
			return p
	return Vector3(radius * 0.7, 0, 0)


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
		for n in _spawned:
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
	if not _mount_model(holder, path, 0.0, scale_factor):
		_primitive_brazier(holder)
	add_child(holder)
	_spawned.append(holder)
	_add_prop_collision(holder)


## Two flat trophy pieces mounted back to back so a front face reads from either side
## (KayKit sword trophies are single-sided wall art with a centre origin: one mount
## would be invisible from behind). One collider + one nav footprint for the pair.
func _mount_trophy_pair(x: float, z: float, face_a: String, face_b: String) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(x, 0.0, z)
	var south := Node3D.new()
	holder.add_child(south)
	if not _mount_model(south, face_a, TROPHY_LIFT, 1.0):
		_primitive_rock(south, 1.2)
	var north := Node3D.new()
	north.rotation.y = PI
	holder.add_child(north)
	if not _mount_model(north, face_b, TROPHY_LIFT, 1.0):
		_primitive_rock(north, 1.2)
	add_child(holder)
	_spawned.append(holder)
	_add_prop_collision(holder)


# ---------------------- prop collision (solid decoration) ----------------------

## Give a floor-standing prop a real collider + a nav-grid footprint, sized from the
## model's OWN imported AABB so the invisible wall always matches the visible mesh
## (KayKit props vary in footprint, and a hardcoded box would clip or float).
func _add_prop_collision(holder: Node3D) -> void:
	if holder == null or not is_instance_valid(holder):
		return
	var bounds := _combined_local_aabb(holder)
	var center := bounds.position + bounds.size * 0.5
	var half := Vector3(
		clampf(bounds.size.x * 0.5, MIN_PROP_HALF, MAX_PROP_HALF_XZ),
		clampf(bounds.size.y * 0.5, MIN_PROP_HALF, MAX_PROP_HALF_Y),
		clampf(bounds.size.z * 0.5, MIN_PROP_HALF, MAX_PROP_HALF_XZ))
	var body := StaticBody3D.new()
	body.name = "PropCollision"
	# The world layer is what the player and every enemy are masked against, and a static
	# prop queries nothing itself. Named, not written as bits: `collision_layer = 1` reads as a
	# constant to keep and stops meaning anything the moment a layer is renumbered, which is the bug
	# class `tool/validate_guards.py` and `tests/python/test_regress_collision_contract.py` refuse.
	body.collision_layer = CollisionLayers.WORLD_BODY_LAYER
	body.collision_mask = CollisionLayers.NO_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = half * 2.0
	shape.shape = box
	shape.position = center
	body.add_child(shape)
	holder.add_child(body)
	# Nav footprint, expanded to the axis-aligned bounds of the YAW-ROTATED box (the
	# collider inherits the holder's rotation; the nav grid is axis-aligned). The
	# centre offset is rotated by the same yaw so an off-centre model's footprint
	# lands where the mesh actually is.
	var yaw := holder.rotation.y
	var cs := absf(cos(yaw))
	var sn := absf(sin(yaw))
	var foot := Vector3(half.x * cs + half.z * sn, half.y, half.x * sn + half.z * cs)
	var local_center := holder.transform.basis * center
	_blockers.append(AABB(holder.position + local_center - foot, foot * 2.0))


## Combined AABB of every mesh under `root`, in `root`-local space. Walks the child
## transforms explicitly: at decoration time the holder is not in the tree yet, so
## global_transform is not valid and MeshInstance3D.get_aabb() alone would ignore the
## model's own node offsets. Returns a zero AABB when nothing drawable is mounted.
func _combined_local_aabb(root: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var node := pair[0] as Node3D
		if node == null:
			continue
		var xform: Transform3D = pair[1]
		if node != root:
			xform = xform * node.transform
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh != null:
				var local: AABB = xform * mi.get_aabb()
				bounds = local if not found else bounds.merge(local)
				found = true
		for child in node.get_children():
			if child is Node3D:
				stack.append([child, xform])
	if not found:
		return AABB(Vector3.ZERO, Vector3.ZERO)
	return bounds


# ---------------------- model mounting (optional) ----------------------

var _scene_cache := {}


## Instantiate a cached PackedScene under `host`. Returns true when the model was
## actually added (falls back silently on missing/unimported art).
func _mount_model(host: Node, path: String, y_offset: float, scale_factor: float) -> bool:
	if not _scene_cache.has(path):
		var res := load(path)
		_scene_cache[path] = res if res is PackedScene else null
	var scene: PackedScene = _scene_cache.get(path)
	if scene == null:
		return false
	var inst := scene.instantiate()
	if inst == null or not inst is Node3D:
		if inst != null:
			inst.free()
		return false
	(inst as Node3D).position = Vector3(0, y_offset, 0)
	(inst as Node3D).scale = Vector3.ONE * scale_factor
	host.add_child(inst)
	# HD material pass so KayKit dungeon props share the same anisotropic, physically
	# tuned shading as the arena shell and actors.
	HdMaterials.polish(inst as Node3D)
	return true


# ---------------------- primitive fallbacks ----------------------

func _mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat


func _primitive_pillar(body: Node) -> void:
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.2, 4.0, 1.2)
	mesh.mesh = box_mesh
	mesh.position.y = 2.0
	mesh.material_override = _mat(Color(0.5, 0.45, 0.4))
	body.add_child(mesh)
	var cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(1.6, 0.4, 1.6)
	cap.mesh = cap_mesh
	cap.position.y = 4.1
	cap.material_override = _mat(Color(0.4, 0.36, 0.32))
	body.add_child(cap)


func _primitive_rock(holder: Node, s: float) -> void:
	var mesh := MeshInstance3D.new()
	var rock := BoxMesh.new()
	rock.size = Vector3(s, s * 0.7, s)
	mesh.mesh = rock
	mesh.position = Vector3(0, s * 0.3, 0)
	mesh.material_override = _mat(Color(0.45, 0.42, 0.38))
	holder.add_child(mesh)


func _primitive_brazier(holder: Node) -> void:
	var bowl := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.5
	bm.bottom_radius = 0.3
	bm.height = 0.5
	bowl.mesh = bm
	bowl.position.y = 0.6
	bowl.material_override = _mat(Color(0.2, 0.18, 0.18))
	holder.add_child(bowl)


func _primitive_banner(holder: Node) -> void:
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.08
	pm.bottom_radius = 0.08
	pm.height = 4.5
	pole.mesh = pm
	pole.position.y = 2.25
	pole.material_override = _mat(Color(0.3, 0.25, 0.2))
	holder.add_child(pole)


# ---------------------- prestige cosmetics (banners) ----------------------

## Hang the player's prestige-unlocked banners (Cosmetics KIND_BANNER) on the
## arena walls in their unlock colours. Called by Main after decorate(); a no-op
## when no banners are unlocked, so it's always safe to invoke. These are the
## in-world payoff for banner_survivor / banner_last_stand, which previously
## unlocked in save and never appeared anywhere.
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
		_prestige_banner_cloth(holder, Cosmetics.color_of(banners[i]))
		add_child(holder)
		_spawned.append(holder)


## Emissive prestige banner: a tall pole with a glowing coloured cloth.
func _prestige_banner_cloth(holder: Node, color: Color) -> void:
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07
	pm.bottom_radius = 0.07
	pm.height = 4.8
	pole.mesh = pm
	pole.position.y = 2.4
	pole.material_override = _mat(Color(0.22, 0.18, 0.15))
	holder.add_child(pole)
	var cloth := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 2.4)
	cloth.mesh = quad
	cloth.position = Vector3(0, 3.0, 0.06)
	var mat := _mat(color, 1.4)
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.material_override = mat
	holder.add_child(cloth)
