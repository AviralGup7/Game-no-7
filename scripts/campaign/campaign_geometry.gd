class_name CampaignGeometry
extends RefCounted
## Render/collision helpers for authored station modules. Exterior walls come
## from the FLOOR UNION, so shared district/causeway edges never seal a route.

const MODULE := 8.0

# The campaign used to render its station as flat-colour BoxMesh placeholders,
# even though the authored PBR module library shipped in the same build. Keep
# the 8 m gameplay grid, but batch the 1 m assets at module scale so the map and
# its collision/navigation contract remain unchanged.
const GROUND_MILITARY: PackedScene = preload("res://scenes/environment/ground.tscn")
const GROUND_HAZARD: PackedScene = preload("res://scenes/environment/ground_hazard.tscn")
const GROUND_TECH: PackedScene = preload("res://scenes/environment/ground_tech.tscn")
const WALL_MILITARY: PackedScene = preload("res://scenes/environment/wall.tscn")
const WALL_HAZARD: PackedScene = preload("res://scenes/environment/wall_hazard.tscn")
const WALL_TECH: PackedScene = preload("res://scenes/environment/wall_tech.tscn")
const WALL_RUSTED: PackedScene = preload("res://scenes/environment/wall_rusted.tscn")


static func floor_cells(regions: Array[Rect2]) -> Dictionary:
	var cells: Dictionary = {}
	for region in regions:
		for z in range(roundi(region.position.y / MODULE), roundi(region.end.y / MODULE)):
			for x in range(roundi(region.position.x / MODULE), roundi(region.end.x / MODULE)):
				cells[Vector2i(x, z)] = true
	return cells


static func perimeter(regions: Array[Rect2]) -> Array[AABB]:
	var cells := floor_cells(regions)
	var horizontal: Dictionary = {}
	var vertical: Dictionary = {}
	for raw in cells:
		var cell: Vector2i = raw
		if not cells.has(cell + Vector2i.UP):
			_edge(horizontal, cell.y, cell.x)
		if not cells.has(cell + Vector2i.DOWN):
			_edge(horizontal, cell.y + 1, cell.x)
		if not cells.has(cell + Vector2i.LEFT):
			_edge(vertical, cell.x, cell.y)
		if not cells.has(cell + Vector2i.RIGHT):
			_edge(vertical, cell.x + 1, cell.y)
	var boxes: Array[AABB] = []
	_merge_edges(horizontal, false, boxes)
	_merge_edges(vertical, true, boxes)
	return boxes


static func _edge(lines: Dictionary, line: int, start: int) -> void:
	if not lines.has(line):
		lines[line] = []
	lines[line].append(start)


static func _merge_edges(lines: Dictionary, vertical: bool, boxes: Array[AABB]) -> void:
	for line in lines:
		var points: Array = lines[line]
		points.sort()
		var begin := int(points[0])
		var end := begin + 1
		for i in range(1, points.size() + 1):
			if i < points.size() and int(points[i]) == end:
				end += 1
				continue
			var length := float(end - begin) * MODULE
			var pos := Vector3(float(begin) * MODULE, 0.0, float(line) * MODULE - 0.35)
			var size := Vector3(length, 1.8, 0.7)
			if vertical:
				pos = Vector3(float(line) * MODULE - 0.35, 0.0, float(begin) * MODULE)
				size = Vector3(0.7, 1.8, length)
			boxes.append(AABB(pos, size))
			if i < points.size():
				begin = int(points[i])
				end = begin + 1


static func material(color: Color, luminous: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.75
	result.metallic = 0.35
	if luminous:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = 1.4
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return result


static func box(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = at
	parent.add_child(instance)
	return instance


static func cylinder(parent: Node3D, at: Vector3, radius: float, height: float, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = at
	parent.add_child(instance)


static func collider(parent: Node3D, bounds: AABB) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = CollisionLayers.WORLD_BODY_LAYER
	body.collision_mask = CollisionLayers.NO_LAYER
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	body.position = bounds.get_center()
	parent.add_child(body)


static func floor_batch(parent: Node3D, area: Rect2, style: StringName, fallback: Material) -> void:
	var cells := floor_cells([area])
	var mesh := _module_mesh(_ground_scene(style))
	if mesh == null:
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(MODULE - 0.12, 0.22, MODULE - 0.12)
		mesh = box_mesh
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = cells.size()
	var index := 0
	for raw in cells:
		var cell: Vector2i = raw
		var at := Vector3((cell.x + 0.5) * MODULE, 0.0, (cell.y + 0.5) * MODULE)
		var basis := Basis.IDENTITY.scaled(Vector3(MODULE, 1.0, MODULE))
		multi.set_instance_transform(index, Transform3D(basis, at))
		index += 1
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	if mesh is BoxMesh:
		instance.material_override = fallback
	elif mesh.get_surface_count() > 0:
		var surface_material := mesh.surface_get_material(0)
		if surface_material is BaseMaterial3D:
			var repeated := (surface_material as BaseMaterial3D).duplicate() as BaseMaterial3D
			repeated.uv1_scale = Vector3(MODULE, MODULE, MODULE)
			instance.material_override = repeated
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


static func wall_batch(parent: Node3D, bounds: AABB, style: StringName, fallback: Material) -> void:
	var mesh := _module_mesh(_wall_scene(style))
	if mesh == null:
		box(parent, bounds.get_center(), bounds.size, fallback)
		return
	var vertical := bounds.size.z > bounds.size.x
	var length := bounds.size.z if vertical else bounds.size.x
	var count := maxi(1, roundi(length / MODULE))
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count
	for index in range(count):
		var offset := (float(index) + 0.5) * length / float(count)
		var at := Vector3(bounds.position.x + offset, bounds.position.y + bounds.size.y * 0.5, bounds.get_center().z)
		var basis := Basis.IDENTITY.scaled(Vector3(length / float(count), bounds.size.y / 0.27, 1.0))
		if vertical:
			at = Vector3(bounds.get_center().x, bounds.position.y + bounds.size.y * 0.5, bounds.position.z + offset)
			basis = Basis(Vector3.UP, PI * 0.5).scaled(Vector3(length / float(count), bounds.size.y / 0.27, 1.0))
		multi.set_instance_transform(index, Transform3D(basis, at))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	parent.add_child(instance)


static func _ground_scene(style: StringName) -> PackedScene:
	if style == &"hazard":
		return GROUND_HAZARD
	if style == &"tech":
		return GROUND_TECH
	return GROUND_MILITARY


static func _wall_scene(style: StringName) -> PackedScene:
	if style == &"hazard":
		return WALL_HAZARD
	if style == &"tech":
		return WALL_TECH
	if style == &"rusted":
		return WALL_RUSTED
	return WALL_MILITARY


static func _module_mesh(source: PackedScene) -> Mesh:
	var root := source.instantiate()
	var result := _find_mesh(root)
	root.free()
	if result == null:
		push_warning("CampaignGeometry: environment module has no MeshInstance3D; using fallback geometry")
	return result


static func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


static func landmark(parent: Node3D, prop: Dictionary, accent: Color) -> void:
	var at := CampaignDefinition.point(prop.at)
	var size := CampaignDefinition.point(prop.size)
	var root := Node3D.new()
	root.name = String(prop.id)
	root.position = at
	parent.add_child(root)
	var steel := material(Color(0.14, 0.2, 0.25))
	var trim := material(accent.darkened(0.55))
	var glow := material(accent, true)
	var kind := String(prop.kind)
	# A full plinth makes every solid AABB visibly occupied, including the
	# square clearance footprint around a cylindrical reactor or antenna.
	box(root, Vector3(0, -size.y * 0.5 + 0.35, 0), Vector3(size.x, 0.7, size.z), steel)
	match kind:
		"reactor", "antenna", "generator":
			cylinder(root, Vector3.ZERO, minf(size.x, size.z) * 0.42, size.y, steel)
			for level in [-0.28, 0.05, 0.35]:
				cylinder(root, Vector3(0, size.y * level, 0), minf(size.x, size.z) * 0.45, 0.3, glow)
			if kind == "antenna":
				cylinder(root, Vector3(0, size.y * 0.2, 0), size.x * 0.42, 1.4, trim)
		"shuttle":
			box(root, Vector3.ZERO, Vector3(size.x * 0.86, size.y * 0.85, size.z * 0.65), steel)
			box(root, Vector3(-size.x * 0.26, size.y * 0.22, 0), Vector3(5, 1.2, 5), glow)
			for side in [-1, 1]:
				box(root, Vector3(size.x * 0.2, 0, side * size.z * 0.36), Vector3(7, 1.0, 3), trim)
		"crane":
			box(root, Vector3.ZERO, Vector3(size.x * 0.5, size.y, size.z * 0.5), trim)
			box(root, Vector3(0, size.y * 0.4, 0), Vector3(size.x, 1, size.z), glow)
		"planter":
			box(root, Vector3.ZERO, size * Vector3(0.95, 0.65, 0.95), trim)
			for x in [-0.3, 0.0, 0.3]:
				cylinder(root, Vector3(size.x * x, size.y * 0.2, 0), 1.6, 1.8, material(Color(0.2, 0.5, 0.34)))
		_:
			box(root, Vector3.ZERO, size * 0.96, trim)
			box(root, Vector3(0, size.y * 0.3, size.z * 0.485), Vector3(size.x * 0.75, 0.35, 0.12), glow)
			for x in [-0.32, 0.32]:
				box(root, Vector3(size.x * x, 0, 0), Vector3(0.3, size.y, size.z), steel)
