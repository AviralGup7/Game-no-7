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
	_spawn_landmark(preset)


func _resolve_arena_id() -> StringName:
	if GameRoot != null and GameRoot.has_method("get_run"):
		var run: Variant = GameRoot.call("get_run")
		if run != null:
			var idn: StringName = &""
			if run is Dictionary:
				idn = StringName(String((run as Dictionary).get("arena_id", &"")))
			elif run is Object and "arena_id" in run:
				idn = (run as Object).get("arena_id")
				if typeof(idn) == TYPE_STRING:
					idn = StringName(String(idn))
			if idn != &"" and String(idn) != "":
				return idn
	return arena_id


## Per-arena mood presets — dramatically distinct for instant readability on mobile.
## Each now has a unique central landmark + emissive accents + strong fog identity.
const THEMES := {
	"ember_crucible": {
		"sky_top": Color(0.12, 0.03, 0.02),
		"sky_horizon": Color(0.85, 0.28, 0.08),
		"ground_horizon": Color(0.35, 0.12, 0.05),
		"fog_color": Color(0.65, 0.25, 0.08),
		"fog_density": 0.028,
		"sun_color": Color(1.0, 0.45, 0.15),
		"sun_energy": 1.85,
		"ambient_color": Color(0.85, 0.38, 0.22),
		"floor_tint": Color(0.72, 0.42, 0.32),
		"wall_tint": Color(0.55, 0.24, 0.18),
		"landmark": "forge",
		"emissive_accent": Color(1.0, 0.42, 0.1),
	},
	"frost_hollow": {
		"sky_top": Color(0.18, 0.28, 0.48),
		"sky_horizon": Color(0.82, 0.90, 1.0),
		"ground_horizon": Color(0.42, 0.58, 0.78),
		"fog_color": Color(0.78, 0.88, 1.0),
		"fog_density": 0.024,
		"sun_color": Color(0.65, 0.78, 1.0),
		"sun_energy": 1.45,
		"ambient_color": Color(0.68, 0.80, 1.0),
		"floor_tint": Color(0.70, 0.78, 0.88),
		"wall_tint": Color(0.52, 0.62, 0.78),
		"landmark": "crystal",
		"emissive_accent": Color(0.45, 0.75, 1.0),
	},
	"default_arena": {
		"sky_top": Color(0.22, 0.42, 0.68),
		"sky_horizon": Color(0.72, 0.82, 0.92),
		"ground_horizon": Color(0.38, 0.42, 0.48),
		"fog_color": Color(0.68, 0.72, 0.78),
		"fog_density": 0.015,
		"sun_color": Color(1.0, 0.95, 0.85),
		"sun_energy": 1.25,
		"ambient_color": Color(0.72, 0.75, 0.82),
		"floor_tint": Color(0.58, 0.55, 0.52),
		"wall_tint": Color(0.45, 0.42, 0.40),
		"landmark": "obelisk",
		"emissive_accent": Color(0.85, 0.75, 0.45),
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


func _spawn_landmark(preset: Dictionary) -> void:
	# Remove any previous landmark (idempotent for theme switches / headless re-entry).
	var old := get_node_or_null("Landmark")
	if old != null:
		old.queue_free()
	var kind := String(preset.get("landmark", ""))
	var accent: Color = preset.get("emissive_accent", Color(1, 0.8, 0.4))
	var holder := Node3D.new()
	holder.name = "Landmark"
	add_child(holder)
	match kind:
		"forge":
			# Central forge: dark stone base + emissive lava basin + point light
			var base := MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.top_radius = 1.8
			bm.bottom_radius = 2.1
			bm.height = 0.6
			base.mesh = bm
			base.position.y = 0.3
			var bmat := StandardMaterial3D.new()
			bmat.albedo_color = Color(0.22, 0.16, 0.14)
			bmat.roughness = 0.9
			base.material_override = bmat
			holder.add_child(base)
			var lava := MeshInstance3D.new()
			var lm := CylinderMesh.new()
			lm.top_radius = 1.25
			lm.bottom_radius = 1.25
			lm.height = 0.12
			lava.mesh = lm
			lava.position.y = 0.66
			var lmat := StandardMaterial3D.new()
			lmat.albedo_color = accent
			lmat.emission_enabled = true
			lmat.emission = accent
			lmat.emission_energy_multiplier = 4.5
			lmat.roughness = 0.35
			lava.material_override = lmat
			holder.add_child(lava)
			var light := OmniLight3D.new()
			light.light_color = accent
			light.light_energy = 2.2
			light.omni_range = 8.0
			light.position.y = 1.2
			holder.add_child(light)
		"crystal":
			# Frost crystal cluster: three prisms + cool point light
			for i in range(3):
				var prism := MeshInstance3D.new()
				var pm := PrismMesh.new()
				pm.size = Vector3(0.7, 2.2 + i * 0.6, 0.7)
				prism.mesh = pm
				prism.position = Vector3(cos(i * TAU / 3.0) * 0.5, 1.1, sin(i * TAU / 3.0) * 0.5)
				prism.rotation.y = i * 0.9
				var cmat := StandardMaterial3D.new()
				cmat.albedo_color = Color(0.75, 0.85, 1.0, 0.9)
				cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				cmat.roughness = 0.15
				cmat.metallic = 0.1
				cmat.emission_enabled = true
				cmat.emission = accent
				cmat.emission_energy_multiplier = 1.8
				prism.material_override = cmat
				holder.add_child(prism)
			var light := OmniLight3D.new()
			light.light_color = accent
			light.light_energy = 1.8
			light.omni_range = 7.0
			light.position.y = 1.5
			holder.add_child(light)
		_:
			# Default ancient obelisk: tall stone with gold cap + warm fill light
			var pillar := MeshInstance3D.new()
			var col := BoxMesh.new()
			col.size = Vector3(1.0, 4.2, 1.0)
			pillar.mesh = col
			pillar.position.y = 2.1
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = Color(0.52, 0.48, 0.42)
			pmat.roughness = 0.75
			pillar.material_override = pmat
			holder.add_child(pillar)
			var cap := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(1.25, 0.35, 1.25)
			cap.mesh = cm
			cap.position.y = 4.4
			var cmat2 := StandardMaterial3D.new()
			cmat2.albedo_color = accent
			cmat2.metallic = 0.6
			cmat2.roughness = 0.25
			cmat2.emission_enabled = true
			cmat2.emission = accent
			cmat2.emission_energy_multiplier = 1.2
			cap.material_override = cmat2
			holder.add_child(cap)
			var light := OmniLight3D.new()
			light.light_color = accent
			light.light_energy = 1.1
			light.omni_range = 6.0
			light.position.y = 2.0
			holder.add_child(light)


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
	if is_inside_tree():
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

## Hardened: clamp arena half extent to prevent out-of-bounds placement.
func _validated_half(half: float) -> float:
	if not is_finite(half):
		return 24.0
	return clampf(half, 4.0, 100.0)

