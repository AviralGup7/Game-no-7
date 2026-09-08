extends Node3D
class_name Arena

## Composes the static environment + markers for one arena. Contains NO wave or score
## logic. Exposes metadata and marker lookup so GameRoot / SpawnManager (later) can
## drive gameplay without scene-specific knowledge. Additional arenas = a new scene
## following this contract + an ArenaConfig resource.

const SPAWN_POINT_GROUP := &"enemy_spawn_point"

@export var arena_id: StringName = &"default_arena"
@export var config_path: String = &"res://data/arenas/default_arena.tres"
## Interior half-extent used to keep actors in-bounds and build the nav floor.
@export var interior_half: float = 12.0
@export var min_spawn_distance: float = 6.0


func _ready() -> void:
	_build_navigation_floor()
	# Presentation (Agent 4): give the active arena a distinct lighting/sky/mood.
	apply_theme(_resolve_arena_id())


## Presentation entry point. Reads the run's real arena id (the shared arena scene is
## reused by every ArenaConfig, so the scene's default id is not authoritative).
func apply_theme(theme_arena_id: StringName) -> void:
	var preset: Dictionary = THEMES.get(String(theme_arena_id))
	if preset.is_empty():
		# Unknown arena keeps the scene-authored daylight preset.
		return
	_apply_sky_and_light(preset)
	_tint_surfaces(preset)


func _resolve_arena_id() -> StringName:
	if GameRoot != null and GameRoot.has_method("get_run"):
		var run := GameRoot.get_run()
		if run != null:
			var idn: StringName = run.get("arena_id")
			if idn != null and String(idn) != "":
				return idn
	return arena_id


## Per-arena mood presets. Keep dynamic lights minimal (one sun) for Android.
const THEMES := {
	"ember_crucible": {
		"sky_top": Color(0.16, 0.06, 0.05),
		"sky_horizon": Color(0.6, 0.22, 0.1),
		"ground_horizon": Color(0.2, 0.07, 0.04),
		"fog_color": Color(0.5, 0.2, 0.09),
		"fog_density": 0.02,
		"sun_color": Color(1.0, 0.58, 0.3),
		"sun_energy": 1.55,
		"ambient_color": Color(0.75, 0.42, 0.3),
		"floor_tint": Color(0.62, 0.4, 0.3),
		"wall_tint": Color(0.5, 0.28, 0.22),
	},
	"frost_hollow": {
		"sky_top": Color(0.25, 0.34, 0.5),
		"sky_horizon": Color(0.75, 0.82, 0.92),
		"ground_horizon": Color(0.45, 0.52, 0.62),
		"fog_color": Color(0.75, 0.83, 0.92),
		"fog_density": 0.018,
		"sun_color": Color(0.75, 0.85, 1.0),
		"sun_energy": 1.35,
		"ambient_color": Color(0.7, 0.78, 0.9),
		"floor_tint": Color(0.66, 0.72, 0.82),
		"wall_tint": Color(0.5, 0.56, 0.68),
	},
}


func _apply_sky_and_light(preset: Dictionary) -> void:
	# Sun
	var sun := get_node_or_null("Lighting/Sun") as DirectionalLight3D
	if sun != null:
		sun.light_color = preset.get("sun_color", sun.light_color)
		sun.light_energy = float(preset.get("sun_energy", sun.light_energy))
	# Fresh sky + fog environment (never mutate the scene's shared default resource).
	var pm := ProceduralSkyMaterial.new()
	pm.sky_top_color = preset.get("sky_top", Color(0.36, 0.6, 0.85))
	pm.sky_horizon_color = preset.get("sky_horizon", Color(0.72, 0.8, 0.9))
	pm.ground_horizon_color = preset.get("ground_horizon", Color(0.55, 0.6, 0.66))
	pm.ground_bottom_color = pm.sky_horizon_color.darkened(0.6)
	var sky := Sky.new()
	sky.sky_material = pm
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.background_sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = preset.get("ambient_color", Color(0.62, 0.68, 0.75))
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = preset.get("fog_color", Color(0.7, 0.7, 0.7))
	env.fog_density = float(preset.get("fog_density", 0.012))
	env.fog_sky_affect = 0.35
	var wenv := get_node_or_null("Environment") as WorldEnvironment
	if wenv != null:
		wenv.environment = env


func _tint_surfaces(preset: Dictionary) -> void:
	_tint_geometry(&"Geometry", preset.get("floor_tint", Color.WHITE), preset.get("wall_tint", Color.WHITE))


func _tint_geometry(root_path: String, floor_tint: Color, wall_tint: Color) -> void:
	var root := get_node_or_null(root_path)
	if root == null:
		return
	for child in root.get_children():
		if not child is MeshInstance3D:
			continue
		var mi := child as MeshInstance3D
		var name := child.name
		var tint: Color
		if name == &"Floor":
			tint = floor_tint
		elif String(name).begins_with("Wall"):
			tint = wall_tint
		else:
			continue
		var base := mi.mesh.material as StandardMaterial3D
		var dup: StandardMaterial3D = (base.duplicate(true) if base != null else StandardMaterial3D.new())
		dup.albedo_color = tint
		mi.material_override = dup


## Deterministic, precomputed navigation floor (no runtime baking). Builds a flat
## convex NavigationMesh covering the walkable interior so NavigationAgent3D enemies
## get reliable paths on mobile without the cost/fragility of runtime baking.
func _build_navigation_floor() -> void:
	var region := get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if region == null:
		return
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.4
	nm.agent_max_climb = 0.4
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_BOTH
	var h := maxf(interior_half - 0.75, 3.0)
	var verts := PackedVector3Array([
		Vector3(-h, 0.0, -h),
		Vector3(h, 0.0, -h),
		Vector3(h, 0.0, h),
		Vector3(-h, 0.0, h),
	])
	nm.vertices = verts
	nm.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = nm


func get_arena_id() -> StringName:
	return arena_id


func get_interior_half() -> float:
	return interior_half


func get_min_spawn_distance() -> float:
	return min_spawn_distance


func get_player_start() -> Node3D:
	return get_node_or_null("PlayerStart") as Node3D


func get_spawn_points() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in get_tree().get_nodes_in_group(String(SPAWN_POINT_GROUP)):
		if is_instance_valid(child) and self.is_ancestor_of(child):
			out.append(child as Node3D)
	# Fall back to direct children if not grouped in a headless context.
	if out.is_empty():
		var spawns := get_node_or_null("SpawnPoints")
		if spawns != null:
			for c in spawns.get_children():
				if c is Marker3D:
					out.append(c as Marker3D)
	return out


func get_pickup_spawn_points() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var node := get_node_or_null("PickupSpawnPoints")
	if node != null:
		for c in node.get_children():
			if c is Marker3D:
				out.append(c as Marker3D)
	return out


func get_debug_snapshot() -> Dictionary:
	return {
		"arena_id": String(arena_id),
		"spawn_point_count": get_spawn_points().size(),
		"player_start": _vec_string(get_player_start()),
	}


func _vec_string(node: Node3D) -> Vector3:
	if node == null:
		return Vector3.ZERO
	return node.global_position
