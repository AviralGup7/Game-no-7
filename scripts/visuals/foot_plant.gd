class_name FootPlant
extends RefCounted

## Ray-plant CharacterModel.y onto the floor. VisualRoot.y stays 0 so camera
## follow height is never fought. Hip keys still play on CharacterModel.

const WORLD_MASK := 0xFFFFFFF1
const LERP_RATE := 14.0

static func apply(body: CharacterBody3D, max_offset: float = 0.14, delta: float = 0.016) -> float:
	if body == null or not body.is_inside_tree():
		return 0.0
	var visual := body.get_node_or_null("VisualRoot") as Node3D
	var model := body.get_node_or_null("VisualRoot/CharacterModel") as Node3D
	if visual != null:
		visual.position.y = 0.0
	if model == null:
		return 0.0
	# Death clips own hip Y — do not snap the plant to 0 under a fade.
	if body is Damageable and not (body as Damageable).is_alive():
		return model.position.y
	var world := body.get_world_3d()
	if world == null or world.direct_space_state == null:
		return 0.0
	var dt := clampf(delta if is_finite(delta) and delta > 0.0 else 0.016, 0.008, 0.05)
	var scale_y := visual.scale.y if visual != null else 1.0
	var cap := max_offset * clampf(scale_y, 0.8, 2.2)
	var ground_y := _sample_ground(body, world)
	if not is_finite(ground_y):
		model.position.y = move_toward(model.position.y, 0.0, LERP_RATE * dt)
		return model.position.y
	var target := clampf(ground_y - body.global_position.y, -cap, cap)
	var alpha := clampf(1.0 - exp(-LERP_RATE * dt), 0.2, 0.85)
	model.position.y = lerpf(model.position.y, target, alpha)
	return model.position.y


static func _sample_ground(body: CharacterBody3D, world: World3D) -> float:
	var offsets: Array[Vector3] = [Vector3.ZERO, Vector3(0.18, 0.0, 0.0), Vector3(-0.18, 0.0, 0.0)]
	var best := INF
	var hit_any := false
	var dt := 0.016
	for off in offsets:
		var from: Vector3 = body.global_position + off + Vector3.UP * 0.55
		var to: Vector3 = body.global_position + off + Vector3.DOWN * 1.6
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = [body.get_rid()]
		query.collision_mask = WORLD_MASK
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.hit_from_inside = true
		var hit := world.direct_space_state.intersect_ray(query)
		if hit.is_empty() or _skip_collider(hit.get("collider")):
			continue
		hit_any = true
		var gy := float(hit.position.y)
		var collider: Variant = hit.get("collider")
		if collider is AnimatableBody3D:
			var plat := collider as AnimatableBody3D
			gy = maxf(gy, plat.global_position.y)
			gy += plat.constant_linear_velocity.y * dt
			var rel := body.global_position - plat.global_position
			var spin := plat.constant_angular_velocity
			gy += spin.cross(rel).y * dt
		if gy < best:
			best = gy
	return best if hit_any else INF


static func _skip_collider(collider: Variant) -> bool:
	if collider == null or not (collider is Node):
		return false
	var node := collider as Node
	if node is Area3D:
		return true
	if node is CharacterBody3D:
		return true
	if node.is_in_group("enemies") or node.is_in_group("player") or node.is_in_group("pickups"):
		return true
	var parent := node.get_parent()
	if parent != null and (parent.is_in_group("enemies") or parent.is_in_group("player") or parent.is_in_group("pickups")):
		return true
	return false
