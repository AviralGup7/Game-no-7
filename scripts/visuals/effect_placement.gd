class_name EffectPlacement
extends RefCounted

## World queries the EffectDirector needs to seat effects: the arena origin a wave
## tell should play at, and the floor point under an arbitrary world position.
##
## Static and node-parameterised (no state), so the director and its event handlers
## share one implementation without either owning the other.

## Ray start/end offsets used to find the floor under an effect position.
const FLOOR_PROBE_UP := 2.0
const FLOOR_PROBE_DOWN := 4.0


## Arena centre: the player's flat position when a player exists, world zero otherwise
## (wave tells are "where the fighting is", not "where the pit centre is").
static func arena_origin(node: Node) -> Vector3:
	var tree := node.get_tree() if node != null else null
	var players := tree.get_nodes_in_group(&"player") if tree != null else []
	if players.size() > 0 and players[0] is Node3D:
		var p := (players[0] as Node3D).global_position
		p.y = 0.0
		return p
	return Vector3.ZERO


## World3D the director renders into: the parent body's world when it has one
## (WorldRoot), else the viewport's — null outside the tree.
static func world_3d(node: Node) -> World3D:
	if node == null or not node.is_inside_tree():
		return null
	var parent := node.get_parent() as Node3D
	if parent != null:
		return parent.get_world_3d()
	var vp := node.get_viewport()
	return vp.world_3d if vp != null else null


## Floor probe under `at`: returns {"y": floor height, "normal": surface normal},
## falling back to the probe origin when there is no world/geometry to hit.
static func floor_hit(node: Node, at: Vector3) -> Dictionary:
	var world := world_3d(node)
	if world == null or world.direct_space_state == null:
		return {"y": at.y, "normal": Vector3.UP}
	var query := PhysicsRayQueryParameters3D.create(
			at + Vector3.UP * FLOOR_PROBE_UP, at + Vector3.DOWN * FLOOR_PROBE_DOWN)
	query.collide_with_areas = false
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"y": at.y, "normal": Vector3.UP}
	return {"y": float(hit.position.y), "normal": hit.get("normal", Vector3.UP)}
