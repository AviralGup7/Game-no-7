class_name CampaignWorld
extends Node3D
## One continuous physical world. Small, merged static collision remains loaded;
## district visual batches are distance-culled. Actor streaming has its own owner.

var definition: CampaignDefinition
var nav := ArenaNavGrid.new()
var _visuals: Dictionary = {}
var _markers: Dictionary = {}
var _checkpoints: Dictionary = {}
var _visible_ids: Array[String] = []
var _solids: Array[AABB] = []
# Service causeways / ring decks: rendered, distance-culled, never simulated.
var _connectors: Array[Dictionary] = []


func build(authored: CampaignDefinition) -> bool:
	definition = authored
	if definition == null or not definition.valid:
		return false
	add_to_group("campaign_world")
	_lighting()
	var collision := Node3D.new()
	collision.name = "StaticCollision"
	add_child(collision)
	_solids = definition.solid_boxes()
	nav.build_world(definition.bounds, definition.floors, _solids)
	if not nav.is_built() or not _navigation_is_connected():
		return false
	for region in definition.floors:
		CampaignGeometry.collider(collision, AABB(Vector3(region.position.x, -0.5, region.position.y), Vector3(region.size.x, 0.5, region.size.y)))
	for solid in _solids:
		CampaignGeometry.collider(collision, solid)
	var rails := Node3D.new()
	rails.name = "PerimeterRails"
	add_child(rails)
	var rail_mat := CampaignGeometry.material(Color(0.22, 0.3, 0.36))
	for wall in CampaignGeometry.perimeter(definition.floors):
		CampaignGeometry.collider(collision, wall)
		_render_perimeter_wall(rails, wall, rail_mat)
	for sector in definition.sectors:
		_build_district(sector)
	# Connector decks are distance-culled like districts: at 6x the station size
	# they are most of the always-drawn geometry, and the depth fog hides them
	# long before their culling distance. Collision stays merged and loaded.
	var routes := Node3D.new()
	routes.name = "ServiceCauseways"
	add_child(routes)
	for region in definition.floors:
		var is_district := false
		for sector in definition.sectors:
			is_district = is_district or CampaignDefinition.rect(sector.rect) == region
		if not is_district:
			var deck := Node3D.new()
			deck.name = "Causeway%s" % [region]
			routes.add_child(deck)
			CampaignGeometry.floor_batch(deck, region, &"military", CampaignGeometry.material(Color(0.18, 0.25, 0.3)))
			_connectors.append({"root": deck, "area": region})
	update_visibility(definition.checkpoint("docks").origin)
	return true


func _render_perimeter_wall(parent: Node3D, bounds: AABB, fallback: Material) -> void:
	# Collision remains merged, while render runs split at the gameplay module
	# boundary so a long perimeter can change theme at district boundaries.
	var vertical := bounds.size.z > bounds.size.x
	var length := bounds.size.z if vertical else bounds.size.x
	var count := maxi(1, roundi(length / CampaignGeometry.MODULE))
	for index in range(count):
		var start := float(index) * length / float(count)
		var segment_length := length / float(count)
		var segment := AABB(bounds.position, bounds.size)
		if vertical:
			segment.position.z += start
			segment.size.z = segment_length
		else:
			segment.position.x += start
			segment.size.x = segment_length
		CampaignGeometry.wall_batch(parent, segment, _wall_style_at(segment.get_center()), fallback)


func _floor_style(sector_id: StringName) -> StringName:
	# Hazard plating belongs around heat/cargo machinery; clean powered panels
	# mark transit, habitation and life support. Docks/command retain military tread.
	if sector_id == &"reactor" or sector_id == &"cargo" or sector_id == &"foundry" or sector_id == &"salvage":
		return &"hazard"
	if sector_id == &"transit" or sector_id == &"habitat" or sector_id == &"medbay" or sector_id == &"hydroponics":
		return &"tech"
	return &"military"


func _wall_style_at(at: Vector3) -> StringName:
	var nearest_id := &"docks"
	var nearest_distance := INF
	for sector in definition.sectors:
		var area := CampaignDefinition.rect(sector.rect)
		var nearest := Vector2(clampf(at.x, area.position.x, area.end.x), clampf(at.z, area.position.y, area.end.y))
		var distance := nearest.distance_squared_to(Vector2(at.x, at.z))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = StringName(String(sector.id))
	if nearest_id == &"reactor" or nearest_id == &"foundry":
		return &"hazard"
	if nearest_id == &"transit" or nearest_id == &"habitat" or nearest_id == &"hydroponics" or nearest_id == &"medbay":
		return &"tech"
	if nearest_id == &"cargo" or nearest_id == &"command" or nearest_id == &"salvage":
		return &"rusted"
	return &"military"


func _navigation_is_connected() -> bool:
	nav.rebuild_flow_field(definition.checkpoint("docks").origin)
	var points: Array[Vector3] = []
	for sector in definition.sectors:
		points.append(CampaignDefinition.point(sector.checkpoint))
	for item in definition.interactions:
		points.append(CampaignDefinition.point(item.at))
	for group in definition.encounters:
		for member in group.members:
			points.append(CampaignDefinition.point(member.at))
	for point in points:
		if not nav.is_walkable(point) or not nav.flow_field_reachable(point):
			return false
	return true


func _lighting() -> void:
	var env_node := WorldEnvironment.new()
	env_node.name = "Environment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.025, 0.042, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.64, 0.78)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Cheap depth fog hides the far culling boundary; no volumetric fog on mobile.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 55.0
	env.fog_depth_end = 100.0
	env.fog_light_color = env.background_color
	env.fog_light_energy = 1.0
	env_node.environment = env
	add_child(env_node)
	var lighting := Node3D.new()
	lighting.name = "Lighting"
	add_child(lighting)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_color = Color(0.85, 0.91, 1.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60
	lighting.add_child(sun)


func _build_district(sector: Dictionary) -> void:
	var root := Node3D.new()
	root.name = String(sector.id)
	add_child(root)
	_visuals[String(sector.id)] = root
	var accent := Color(String(sector.accent))
	var sector_id := StringName(String(sector.id))
	CampaignGeometry.floor_batch(root, CampaignDefinition.rect(sector.rect), _floor_style(sector_id), CampaignGeometry.material(accent.darkened(0.78)))
	for prop in definition.props:
		if prop.sector == sector.id:
			CampaignGeometry.landmark(root, prop, accent)
	for item in definition.interactions:
		if item.sector == sector.id:
			_markers[String(item.id)] = _beacon(root, CampaignDefinition.point(item.at), accent, String(item.name), false)
	var checkpoint := CampaignDefinition.point(sector.checkpoint)
	_checkpoints[String(sector.id)] = _beacon(root, checkpoint, Color(0.3, 0.95, 0.8), "CHECKPOINT / SAFE REST", true)
	var sign := Label3D.new()
	sign.text = String(sector.name)
	sign.font = UiTheme.bold_font
	sign.font_size = 72
	sign.pixel_size = 0.016
	sign.modulate = accent
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.no_depth_test = false
	sign.position = checkpoint + Vector3(0, 6, -3)
	root.add_child(sign)


func _beacon(parent: Node3D, at: Vector3, color: Color, caption: String, rest: bool) -> Node3D:
	var root := Node3D.new()
	root.position = at
	parent.add_child(root)
	var glow := CampaignGeometry.material(color, true)
	CampaignGeometry.cylinder(root, Vector3(0, -0.08, 0), 2.2 if rest else 1.2, 0.12, glow)
	var panel := CampaignGeometry.material(Color(0.07, 0.12, 0.16))
	if rest:
		CampaignGeometry.cylinder(root, Vector3(0, 0, 0), 1.9, 0.12, panel)
	else:
		CampaignGeometry.box(root, Vector3(0, 0.65, 0), Vector3(0.7, 1.3, 0.5), panel)
		CampaignGeometry.box(root, Vector3(0, 1.32, 0), Vector3(0.8, 0.12, 0.6), glow)
	var label := Label3D.new()
	label.text = caption.to_upper()
	label.font = UiTheme.bold_font
	label.font_size = 40
	label.pixel_size = 0.01
	label.modulate = color
	label.position.y = 2.8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 28.0
	root.add_child(label)
	return root


func update_markers(interacted: Array, targets: Array) -> void:
	for id in _markers:
		var marker: Node3D = _markers[id]
		var item := definition.interaction(String(id))
		marker.visible = id not in interacted and (id in targets or item.get("kind", "") == "cache")


func update_visibility(at: Vector3) -> void:
	var ranked: Array[Dictionary] = []
	for sector in definition.sectors:
		var area := CampaignDefinition.rect(sector.rect)
		var nearest := Vector2(clampf(at.x, area.position.x, area.end.x), clampf(at.z, area.position.y, area.end.y))
		ranked.append({"id": String(sector.id), "distance": nearest.distance_to(Vector2(at.x, at.z))})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	_visible_ids.clear()
	for i in range(ranked.size()):
		var entry := ranked[i]
		var shown := i < definition.max_visible_sectors and float(entry.distance) < 105.0
		var visual: Node3D = _visuals[entry.id]
		visual.visible = shown
		if shown:
			_visible_ids.append(String(entry.id))
	for deck in _connectors:
		var area: Rect2 = deck["area"]
		var near := Vector2(clampf(at.x, area.position.x, area.end.x), clampf(at.z, area.position.y, area.end.y))
		var root: Node3D = deck["root"]
		root.visible = near.distance_to(Vector2(at.x, at.z)) < 105.0


func point_is_on_floor(at: Vector3) -> bool:
	if not at.is_finite():
		return false
	for region in definition.floors:
		if region.has_point(Vector2(at.x, at.z)):
			return true
	return false


func get_debug_snapshot() -> Dictionary:
	return {"world_id": CampaignDefinition.WORLD_ID, "districts": _visuals.size(),
		"visible_districts": _visible_ids.duplicate(), "navigation": nav.get_debug_snapshot(),
		"solid_landmarks": _solids.size(), "floor_regions": definition.floors.size()}
