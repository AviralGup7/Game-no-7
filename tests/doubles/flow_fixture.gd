extends RefCounted
## Place locomotion checks on a genuinely open lane, not a hard-coded spawn
## point whose nearby authored geometry/hazards can legitimately block motion.

static func place_on_clear_lane(world: Node, player: Player) -> bool:
	var arena := world.get_node_or_null("Arena") as Arena
	var controller := player.get_node_or_null("CharacterController") as CharacterController
	if arena == null or controller == null:
		return false
	var grid := arena.get_nav_grid()
	if grid == null:
		return false
	var hazards := arena.get_node_or_null("ArenaHazards") as ArenaHazards
	var direction := controller.screen_to_world_dir(Vector2.RIGHT)
	if direction.length_squared() < 0.5:
		return false
	var extent := floori(arena.get_interior_half() - 2.0)
	for z in range(-extent, extent + 1):
		for x in range(-extent, extent + 1):
			var start := Vector3(x, 0.2, z)
			var clear := true
			for step in range(25):
				var at := start + direction * float(step) * 0.25
				if not grid.is_walkable(at) or (hazards != null and not hazards.is_spawn_clear(at)):
					clear = false
					break
			if not clear:
				continue
			player.global_position = start
			player.velocity = Vector3.ZERO
			player.reset_physics_interpolation()
			var camera := world.get_node_or_null("CameraRig") as CameraRig
			if camera != null:
				camera.reset_transform()
			return true
	return false
