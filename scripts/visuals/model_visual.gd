class_name ModelVisual
extends RefCounted

## Fit source art inside a cosmetic wrapper without changing physics dimensions,
## skeleton transforms, source bytes or shared materials. No runtime downloads.

static func create(scene: PackedScene, extent: float) -> Node3D:
	if scene == null:
		return null
	var instance := scene.instantiate()
	if not instance is Node3D:
		instance.free()
		return null
	var wrapper := Node3D.new()
	wrapper.add_child(instance)
	var bounds: Array[AABB] = []
	_collect_bounds(instance, Transform3D.IDENTITY, bounds)
	if bounds.is_empty():
		wrapper.free()
		return null
	var box := bounds[0]
	for index in range(1, bounds.size()):
		box = box.merge(bounds[index])
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest <= 0.0001:
		wrapper.free()
		return null
	var factor := maxf(extent, 0.01) / longest
	var pivot := box.get_center()
	pivot.y = box.position.y
	wrapper.scale = Vector3.ONE * factor
	# Move the source root, leaving all internal mesh/skeleton relationships intact.
	(instance as Node3D).position -= pivot
	return wrapper


static func _collect_bounds(node: Node, parent_transform: Transform3D, out: Array[AABB]) -> void:
	var local := parent_transform
	if node is Node3D:
		local = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.mesh != null:
			out.append(local * mesh.mesh.get_aabb())
	for child in node.get_children():
		_collect_bounds(child, local, out)

## Hardened: validate model path.
func _validated_model_path(p: String) -> bool:
	if p.is_empty():
		return false
	return p.begins_with("res://")

