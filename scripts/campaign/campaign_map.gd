class_name CampaignMap
extends Control
## Station chart drawn from the same floor rectangles, blockers and objective
## IDs as physics/navigation. No generated minimap bounds or origin assumptions.

var definition: CampaignDefinition
var director: CampaignDirector
var compact := false
var _chart := Rect2()
var _scale := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func bind(authored: CampaignDefinition, session: CampaignDirector = null) -> void:
	definition = authored
	director = session
	queue_redraw()


func _project(point: Vector3) -> Vector2:
	return _chart.position + (Vector2(point.x, point.z) - definition.bounds.position) * _scale


func _rect(area: Rect2) -> Rect2:
	return Rect2(_chart.position + (area.position - definition.bounds.position) * _scale, area.size * _scale)


func _draw() -> void:
	draw_style_box(UiTheme.box(Color(0.025, 0.05, 0.08, 0.95)), Rect2(Vector2.ZERO, size))
	if definition == null or not definition.valid or size.x < 4 or size.y < 4:
		return
	var pad := 10.0 if compact else 24.0
	_scale = minf(maxf(size.x - pad * 2, 1) / definition.bounds.size.x, maxf(size.y - pad * 2, 1) / definition.bounds.size.y)
	_chart = Rect2((size - definition.bounds.size * _scale) * 0.5, definition.bounds.size * _scale)
	for area in definition.floors:
		draw_rect(_rect(area), Color(0.16, 0.25, 0.32))
	for sector in definition.sectors:
		var accent := Color(String(sector.accent))
		var area := _rect(CampaignDefinition.rect(sector.rect))
		draw_rect(area, accent.darkened(0.8))
		draw_rect(area, accent.darkened(0.4), false, 1.0)
		if not compact and UiTheme.bold_font != null:
			draw_string(UiTheme.bold_font, area.position + Vector2(24, 18), String(sector.id).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, area.size.x - 32, 16, accent)
		var checkpoint := _project(CampaignDefinition.point(sector.checkpoint))
		draw_arc(checkpoint, 3.0 if compact else 5.0, 0, TAU, 16, UiTheme.HEALTH, 1.5)
	for prop in definition.props:
		var at := CampaignDefinition.point(prop.at)
		var extent := CampaignDefinition.point(prop.size)
		draw_rect(_rect(Rect2(at.x - extent.x * 0.5, at.z - extent.z * 0.5, extent.x, extent.z)), Color(0.26, 0.34, 0.41))
	if not is_instance_valid(director) or not is_instance_valid(director.player):
		return
	_draw_route()
	for id in director.target_ids():
		var item := definition.interaction(String(id))
		var at := _project(CampaignDefinition.point(item.at))
		draw_circle(at, 3.0 if compact else 6.0, UiTheme.GOLD)
	for item in definition.interactions:
		if item.kind == "cache" and item.id not in director.progress.interacted:
			var at := _project(CampaignDefinition.point(item.at))
			draw_rect(Rect2(at - Vector2(2, 2), Vector2(4, 4)), UiTheme.MUTED)
	var here := _project(director.player.global_position)
	draw_circle(here, 5.0 if compact else 7.0, Color.WHITE)
	draw_circle(here, 2.5 if compact else 3.5, UiTheme.CYAN)
	# Fixed north-up chart; heading rotates with the player, not the map.
	var facing := -director.player.global_basis.z
	var direction := Vector2(facing.x, facing.z).normalized()
	draw_line(here, here + direction * (10.0 if compact else 16.0), Color.WHITE, 2.0, true)


func _draw_route() -> void:
	var previous := _project(director.player.global_position)
	for point in director.route:
		var next := _project(point)
		draw_line(previous, next, UiTheme.GOLD, 1.5 if compact else 2.5, true)
		previous = next
