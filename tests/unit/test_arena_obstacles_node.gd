extends RefCounted

## Node-level test for the "no pass-through" guarantee: instantiate the REAL
## arena scene headless and assert, end to end, that
##
##   * every interior-obstacle layout entry became a StaticBody3D under
##     "Obstacles" on collision_layer 1 (the world layer the player (mask 1)
##     and every enemy (mask 5) collide with), with a box shape AND a box mesh
##     that match the layout entry;
##   * the central landmark has a collision body on the same layer (an object,
##     not scenery);
##   * the arena's wall/floor geometry and its boundary collision body
##     survived instantiation;
##   * the shared nav grid is built from the SAME footprints — every obstacle
##     and the landmark block the grid, the gate gap and the player start stay
##     walkable, and the flow field still steers — so the AI's intent routes
##     around exactly what physics blocks.
##
## The arena is removed and freed BEFORE returning so its "enemy_spawn_point"
## group markers and lights cannot leak into the later integration stages.
## Registered in run_tests.gd's NODE_SUITES (deferred phase, live tree).

const ARENA_SCENE := "res://scenes/arena/arena.tscn"


static func suite() -> Array:
	var results: Array = []
	var scene: PackedScene = load(ARENA_SCENE)
	if scene == null:
		results.append({"name": "arena scene loads", "passed": false, "why": "load failed"})
		return results
	var arena := scene.instantiate() as Node3D
	if arena == null:
		results.append({"name": "arena instantiates", "passed": false, "why": "instantiate failed"})
		return results
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(arena)
	_run_checks(results, arena)
	# Immediate (not queued) teardown: the integration stages run in the SAME
	# frame, and the scene's spawn markers are grouped "enemy_spawn_point".
	tree.root.remove_child(arena)
	arena.free()
	return results


static func _run_checks(results: Array, arena: Node3D) -> void:
	var half := float(arena.get("interior_half"))
	var expected := ArenaObstacles.layout_for(StringName(arena.get("arena_id")), half)
	var obstacles := arena.get_node_or_null("Obstacles") as Node3D
	results.append({
		"name": "arena: Obstacles node is created",
		"passed": obstacles != null,
		"why": "",
	})
	if obstacles == null:
		return
	results.append({
		"name": "arena: one body per layout entry (%d)" % expected.size(),
		"passed": obstacles.get_child_count() == expected.size(),
		"why": "found=%d" % obstacles.get_child_count(),
	})
	var layers_ok := true
	var shapes_ok := true
	var pos_ok := true
	var n := mini(obstacles.get_child_count(), expected.size())
	for i in range(n):
		var body := obstacles.get_child(i) as StaticBody3D
		var hs: Vector3 = expected[i]["half_size"]
		var want_pos: Vector3 = expected[i]["pos"]
		if body == null or body.collision_layer != 1 or body.collision_mask != 0:
			layers_ok = false
			continue
		if absf(body.position.x - want_pos.x) > 0.001 \
				or absf(body.position.z - want_pos.z) > 0.001 \
				or absf(body.position.y - hs.y) > 0.001:
			pos_ok = false
		var box: BoxShape3D = null
		var mesh_box: BoxMesh = null
		for c in body.get_children():
			if c is CollisionShape3D:
				box = (c as CollisionShape3D).shape as BoxShape3D
			elif c is MeshInstance3D:
				mesh_box = (c as MeshInstance3D).mesh as BoxMesh
		if box == null or mesh_box == null:
			shapes_ok = false
			continue
		if not box.size.is_equal_approx(hs * 2.0) or not mesh_box.size.is_equal_approx(hs * 2.0):
			shapes_ok = false
	results.append({
		"name": "arena: obstacle bodies sit on collision layer 1 (player+enemy mask hits)",
		"passed": layers_ok,
		"why": "",
	})
	results.append({
		"name": "arena: obstacle box shape + mesh match the layout",
		"passed": shapes_ok,
		"why": "",
	})
	results.append({
		"name": "arena: obstacle bodies at the layout positions (y = center height)",
		"passed": pos_ok,
		"why": "",
	})

	# The landmark is an OBJECT: it must have a collision body on the same layer.
	var landmark_body := arena.get_node_or_null("Landmark/Body") as StaticBody3D
	results.append({
		"name": "arena: landmark has a collision body on layer 1",
		"passed": landmark_body != null and landmark_body.collision_layer == 1,
		"why": "",
	})

	# Static environment survived: floor + 4 walls with meshes, boundary body
	# with 5 shapes (floor + 4 walls).
	var floor_mi := arena.get_node_or_null("Geometry/Floor") as MeshInstance3D
	var walls_ok := floor_mi != null and floor_mi.mesh != null
	for wn in ["Wall_N", "Wall_S", "Wall_E", "Wall_W"]:
		var wmi := arena.get_node_or_null("Geometry/" + wn) as MeshInstance3D
		if wmi == null or wmi.mesh == null:
			walls_ok = false
	var boundary := arena.get_node_or_null("Collision") as StaticBody3D
	var boundary_shapes := 0
	if boundary != null:
		for c in boundary.get_children():
			if c is CollisionShape3D:
				boundary_shapes += 1
	results.append({
		"name": "arena: wall/floor geometry intact",
		"passed": walls_ok,
		"why": "",
	})
	results.append({
		"name": "arena: boundary collision has floor + 4 wall shapes",
		"passed": boundary != null and boundary_shapes == 5,
		"why": "shapes=%d" % boundary_shapes,
	})

	# The shared nav grid is built from the SAME footprints as the bodies.
	var nav := arena.call("get_nav_grid") as ArenaNavGrid
	results.append({
		"name": "arena: shared nav grid is built",
		"passed": nav != null and nav.is_built(),
		"why": "",
	})
	if nav == null or not nav.is_built():
		return
	results.append({
		"name": "arena: nav grid registered obstacles + landmark footprint",
		"passed": nav.obstacle_count == expected.size() + 1,
		"why": "count=%d" % nav.obstacle_count,
	})
	var blocked_ok := true
	for ob in expected:
		if nav.is_walkable(ob["pos"] as Vector3):
			blocked_ok = false
	# The obelisk footprint blocks the very center; the gate gap and the
	# player start stay open (both inside the boundary ring).
	var landmark_blocks_center := not nav.is_walkable(Vector3.ZERO)
	var gate_open := nav.is_walkable(Vector3(1.2, 0.0, 0.0))
	var player_start_open := nav.is_walkable(Vector3(0.0, 0.0, 4.5))
	results.append({
		"name": "arena: grid blocks every obstacle footprint",
		"passed": blocked_ok,
		"why": "",
	})
	results.append({
		"name": "arena: grid blocks the landmark footprint",
		"passed": landmark_blocks_center,
		"why": "",
	})
	results.append({
		"name": "arena: gate gap + player start stay walkable",
		"passed": gate_open and player_start_open,
		"why": "gate=%s start=%s" % [gate_open, player_start_open],
	})
	# Sight through the obelisk is blocked too (perception LOS uses this grid).
	var center_los := nav.has_line_of_sight(Vector3(0.0, 0.0, 4.5), Vector3.ZERO)
	results.append({
		"name": "arena: line of sight through the landmark is blocked",
		"passed": not center_los,
		"why": "",
	})
	# The flow field still steers toward the player from an open corner region.
	nav.rebuild_flow_field(Vector3(0.0, 0.0, 4.5))
	var d := nav.flow_field_direction(Vector3(9.0, 0.0, 9.0))
	results.append({
		"name": "arena: flow field steers toward the player start",
		"passed": d != Vector3.ZERO,
		"why": str(d),
	})
