extends RefCounted

## No autoloads or live tree required. Exercises nested transforms and origin fit.
static func suite() -> Array:
	var results: Array = []
	results.append({"name": "Null art keeps fallback", "passed": ModelVisual.create(null, 0.6) == null})
	var source := Node3D.new()
	source.position = Vector3(3, 4, 5)
	var group := Node3D.new()
	group.position = Vector3(2, 1, -2)
	source.add_child(group)
	group.owner = source
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2, 4, 2)
	mesh.mesh = box
	group.add_child(mesh)
	mesh.owner = source
	var scene := PackedScene.new()
	var packed := scene.pack(source)
	results.append({"name": "Visual fixture packs", "passed": packed == OK})
	var visual := ModelVisual.create(scene, 0.6)
	results.append({"name": "Nested model fits", "passed": visual != null})
	if visual != null:
		var bounds: Array[AABB] = []
		ModelVisual._collect_bounds(visual, Transform3D.IDENTITY, bounds)
		results.append({"name": "Longest dimension normalized", "passed": is_equal_approx(bounds[0].size.y, 0.6)})
		results.append({"name": "Source origin grounded", "passed": is_zero_approx(bounds[0].position.y)})
		results.append({"name": "Source centered", "passed": is_zero_approx(bounds[0].get_center().x) and is_zero_approx(bounds[0].get_center().z)})
		visual.free()
	source.free()
	var empty := Node3D.new()
	var empty_scene := PackedScene.new()
	empty_scene.pack(empty)
	results.append({"name": "Empty art keeps fallback", "passed": ModelVisual.create(empty_scene, 0.6) == null})
	empty.free()
	return results
