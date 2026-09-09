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
	if body.has_method("is_alive") and not body.is_alive():
		model.position.y = 0.0
		return 0.0
	var world := body.get_world_3d()
	if world == null or world.direct_space_state == null:
		return 0.0
	var dt := clampf(delta if is_finite(delta) and delta > 0.0 else 0.016, 0.008, 0.05)
	var scale_y := visual.scale.y if visual != null else 1.0
	var cap := max_offset * clampf(scale_y, 0.8, 2.2)
	var from := body.global_position + Vector3.UP * 0.55
	var to := body.global_position + Vector3.DOWN * 1.6
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [body.get_rid()]
	query.collision_mask = WORLD_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = true
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty() or _skip_collider(hit.get("collider")):
		model.position.y = move_toward(model.position.y, 0.0, LERP_RATE * dt)
		return model.position.y
	var ground_y := float(hit.position.y)
	var collider: Variant = hit.get("collider")
	if collider is AnimatableBody3D:
		var plat := collider as AnimatableBody3D
		ground_y = maxf(ground_y, plat.global_position.y)
		if plat is CharacterBody3D:
			pass
		ground_y += plat.constant_linear_velocity.y * dt
	var target := clampf(ground_y - body.global_position.y, -cap, cap)
	var alpha := clampf(1.0 - exp(-LERP_RATE * dt), 0.2, 0.85)
	model.position.y = lerpf(model.position.y, target, alpha)
	return model.position.y


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
