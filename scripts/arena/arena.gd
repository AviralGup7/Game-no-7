extends Node3D
class_name Arena

## Composes the static environment + markers for one arena. Contains NO wave or score
## logic. Exposes metadata and marker lookup so GameRoot / SpawnManager (later) can
## drive gameplay without scene-specific knowledge. Additional arenas = a new scene
## following this contract + an ArenaConfig resource.

const SPAWN_POINT_GROUP := &"enemy_spawn_point"
## Lookup group for the live arena. UI (minimap) and any layout-agnostic consumer
## resolve the arena through this instead of scene paths — main.gd rebuilds the
## world synchronously and nodes may be renamed by the engine mid-frame, so path
## lookups against `WorldRoot/Arena` are the fragile pattern this group replaces.
const ARENA_GROUP := &"arena"

@export var arena_id: StringName = &"default_arena"
@export var config_path: String = &"res://data/arenas/default_arena.tres"
## Interior half-extent used to keep actors in-bounds and build the nav floor.
@export var interior_half: float = 12.0
@export var min_spawn_distance: float = 6.0
## Nav grid cell size (meters). 0.5 keeps paths smooth on a 24 m arena at a
## trivial cost (one shared grid, rebuilt only when the player crosses a cell).
@export var nav_cell_size: float = 0.5

var _nav_grid: ArenaNavGrid = null
var _obstacles: Array = []  # [{"pos","half_size","kind"}] — single source of truth
var _landmark_half := Vector3.ZERO  # XZ half-extent of the landmark footprint (0 = none)
var _flow_tick := 0.0


func _ready() -> void:
	add_to_group(ARENA_GROUP)
	# Order matters: theme (landmark) and obstacles must exist before the
	# navigation floor is built from their footprints.
	_spawn_obstacles()
	# Presentation (Agent 4): give the active arena a distinct lighting/sky/mood.
	apply_theme(_resolve_arena_id())
	_build_navigation_floor()


## Low-rate refresh of the shared flow field toward the player. Rebuilding only
## happens when the player crosses a grid cell, so this is a few hundred cheap
## ops per second at worst (the 1500-enemy flow-field pattern from Manymies).
func _process(delta: float) -> void:
	if _nav_grid == null or not is_inside_tree():
		return
	# No enemies on the field: nothing reads the flow field, so skip the 10 Hz
	# refresh entirely (the field rebuilds on the first tick of the next wave).
	if get_tree().get_nodes_in_group("enemies").is_empty():
		return
	_flow_tick -= delta
	if _flow_tick > 0.0:
		return
	_flow_tick = 0.1
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		_nav_grid.rebuild_flow_field((player as Node3D).global_position)


## Shared by every enemy (SpawnManager wires it at spawn). Null-safe.
func get_nav_grid() -> ArenaNavGrid:
	return _nav_grid


## ---------- Interior obstacles (collision + nav, one source of truth) ----------

## Deterministic pillar/block set per arena (ArenaObstacles.layout_for). Every
## entry becomes a StaticBody3D on CollisionLayers.WORLD_STATIC — the one layer
## both PLAYER_BODY_MASK and ENEMY_BODY_MASK collide with — plus a stone mesh,
## and is registered with the nav grid so AI routes around it instead of
## clipping through. Nothing can walk through objects anymore: physics for the
## bodies, nav grid for the intent.
func _spawn_obstacles() -> void:
	_obstacles = ArenaObstacles.layout_for(_resolve_arena_id(), interior_half)
	var parent := get_node_or_null("Obstacles") as Node3D
	if parent == null:
		parent = Node3D.new()
		parent.name = "Obstacles"
		add_child(parent)
	else:
		for c in parent.get_children():
			c.queue_free()
	var mat: Material = null
	var res := load("res://assets/materials/arena_wall_stone.tres")
	if res is Material:
		mat = res
	ArenaObstacles.build_nodes(parent, _obstacles, mat)


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
	# Landmark footprint changed: refresh the shared nav grid so the AI's
	# intent avoids it exactly as the physics body blocks the bodies.
	_rebuild_navigation_floor()


func _resolve_arena_id() -> StringName:
	# Look up the live autoload by path so this script compiles under a bare
	# SceneTree `--script` harness (autoload identifiers like GameRoot are not
	# injected there). The node is the real GameRoot script when autoloads ran.
	var gr := get_node_or_null("/root/GameRoot") as GameRootService
	if gr != null:
		var run := gr.get_run()
		if run != null and run.arena_id != &"":
			return run.arena_id
	return arena_id


## Photorealistic panorama skies (Poly Haven CC0 HDRIs locked through the reviewed
## three.js mirror; see THIRD_PARTY_ASSETS.md). Each arena gets its own real sky and
## image-based lighting; the procedural colours below are only the graceful fallback
## used when the .hdr has not been imported on the device.
const PANORAMA_BASE := "res://assets/textures/panorama/"
const PANORAMA_SKIES := {
	"default_arena": PANORAMA_BASE + "spruit_sunrise_1k.hdr",
	"ember_crucible": PANORAMA_BASE + "venice_sunset_1k.hdr",
	"frost_hollow": PANORAMA_BASE + "moonless_golf_1k.hdr",
}
const HD_ROCK_ALBEDO := "res://assets/textures/rock/rock_albedo.png"
const HD_ROCK_NORMAL := "res://assets/textures/rock/rock_normal.png"
const HD_ROCK_AO := "res://assets/textures/rock/rock_ao.png"
const HD_MARBLE_ALBEDO := "res://assets/textures/stone/marble_albedo.png"

## Per-arena mood presets — dramatically distinct for instant readability on mobile.
## Each now has a unique central landmark + emissive accents + strong fog identity,
## driven by a real HDRI panorama (with the procedural fallback preserved below).
const THEMES := {
	"ember_crucible": {
		"panorama": PANORAMA_SKIES["ember_crucible"],
		"sky_top": Color(0.12, 0.03, 0.02),
		"sky_horizon": Color(0.85, 0.28, 0.08),
		"ground_horizon": Color(0.35, 0.12, 0.05),
		"fog_color": Color(0.62, 0.26, 0.1),
		"fog_density": 0.02,
		"sun_color": Color(1.0, 0.5, 0.2),
		"sun_energy": 1.7,
		"ambient_color": Color(0.85, 0.45, 0.28),
		"brightness": 1.0,
		"contrast": 1.1,
		"floor_tint": Color(0.88, 0.6, 0.46),
		"wall_tint": Color(0.78, 0.5, 0.38),
		"landmark": "forge",
		"emissive_accent": Color(1.0, 0.42, 0.1),
	},
	"frost_hollow": {
		"panorama": PANORAMA_SKIES["frost_hollow"],
		"sky_top": Color(0.18, 0.28, 0.48),
		"sky_horizon": Color(0.82, 0.90, 1.0),
		"ground_horizon": Color(0.42, 0.58, 0.78),
		"fog_color": Color(0.62, 0.72, 0.9),
		"fog_density": 0.017,
		"sun_color": Color(0.7, 0.8, 1.0),
		"sun_energy": 1.35,
		"ambient_color": Color(0.68, 0.8, 1.0),
		"brightness": 0.98,
		"contrast": 1.08,
		"floor_tint": Color(0.72, 0.8, 0.9),
		"wall_tint": Color(0.6, 0.7, 0.84),
		"landmark": "crystal",
		"emissive_accent": Color(0.45, 0.75, 1.0),
	},
	"default_arena": {
		"panorama": PANORAMA_SKIES["default_arena"],
		"sky_top": Color(0.22, 0.42, 0.68),
		"sky_horizon": Color(0.72, 0.82, 0.92),
		"ground_horizon": Color(0.38, 0.42, 0.48),
		"fog_color": Color(0.66, 0.68, 0.72),
		"fog_density": 0.011,
		"sun_color": Color(1.0, 0.92, 0.78),
		"sun_energy": 1.2,
		"ambient_color": Color(0.7, 0.73, 0.8),
		"brightness": 1.02,
		"contrast": 1.06,
		"floor_tint": Color(0.66, 0.64, 0.6),
		"wall_tint": Color(0.72, 0.7, 0.68),
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
	# Real HDRI panorama sky (photorealistic IBL) with procedural fallback.
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_2048
	var pano_path := String(preset.get("panorama", ""))
	var pano: Texture2D = load(pano_path) if not pano_path.is_empty() else null
	if pano != null:
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = pano
		# PanoramaSkyMaterial has no energy knob in Godot 4.4 (unlike
		# ProceduralSkyMaterial); the HDRI's exposure is governed by the
		# Environment (ambient energy + tonemap/adjustment brightness).
		sky.sky_material = pm
	else:
		# Fallback: procedural daylight (never mutate the scene's shared default).
		var pm := ProceduralSkyMaterial.new()
		pm.sky_top_color = preset.get("sky_top", Color(0.36, 0.6, 0.85))
		pm.sky_horizon_color = preset.get("sky_horizon", Color(0.72, 0.8, 0.9))
		pm.ground_horizon_color = preset.get("ground_horizon", Color(0.55, 0.6, 0.66))
		pm.ground_bottom_color = pm.sky_horizon_color.darkened(0.6)
		sky.sky_material = pm
	# Fresh environment (never mutate the scene's shared default resource).
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.background_sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = preset.get("ambient_color", Color(0.62, 0.68, 0.75))
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Cinematic look: exposure/contrast + subtle bloom on emissives (torches, lava,
	# crystals). Mobile-renderer-safe: no SSAO/SSR/volumetrics are requested.
	env.adjustment_enabled = true
	env.adjustment_brightness = float(preset.get("brightness", 1.02))
	env.adjustment_contrast = float(preset.get("contrast", 1.06))
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = preset.get("fog_color", Color(0.7, 0.7, 0.7))
	env.fog_density = float(preset.get("fog_density", 0.012))
	env.fog_sky_affect = 0.25
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


## Per-landmark collision body + XZ footprint (shared with the nav grid).
func _add_landmark_collision(holder: Node3D, kind: String) -> void:
	var old := holder.get_node_or_null("Body")
	if old != null:
		old.queue_free()
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = CollisionLayers.WORLD_BODY_LAYER
	body.collision_mask = CollisionLayers.NO_LAYER
	var shape := CollisionShape3D.new()
	var half := Vector3.ZERO
	match kind:
		"forge":
			# Stone basin; the emissive lava sits inside it.
			var cyl := CylinderShape3D.new()
			cyl.radius = 1.9
			cyl.height = 1.4
			shape.shape = cyl
			shape.position = Vector3(0.0, 0.7, 0.0)
			half = Vector3(1.9, 0.7, 1.9)
		"crystal":
			# Prism cluster.
			var cyl2 := CylinderShape3D.new()
			cyl2.radius = 1.4
			cyl2.height = 3.2
			shape.shape = cyl2
			shape.position = Vector3(0.0, 1.6, 0.0)
			half = Vector3(1.4, 1.6, 1.4)
		_:
			# Obelisk column + cap.
			var box := BoxShape3D.new()
			box.size = Vector3(1.1, 4.6, 1.1)
			shape.shape = box
			shape.position = Vector3(0.0, 2.3, 0.0)
			half = Vector3(0.55, 2.3, 0.55)
	body.add_child(shape)
	holder.add_child(body)
	_landmark_half = half


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
	# Collision footprint: the landmark is an OBJECT, not scenery — neither
	# the player nor any enemy may walk through it (physics for the bodies,
	# footprint registered with the nav grid for the AI's intent).
	_add_landmark_collision(holder, kind)
	match kind:
		"forge":
			# Central forge: photo-stone base + emissive lava basin + point light
			var base := MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.top_radius = 1.8
			bm.bottom_radius = 2.1
			bm.height = 0.6
			base.mesh = bm
			base.position.y = 0.3
			base.material_override = _hd_rock_mat(Color(0.32, 0.26, 0.24), 0.8)
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
			# Default ancient obelisk: photo-stone pillar with gold cap + warm fill light
			var pillar := MeshInstance3D.new()
			var col := BoxMesh.new()
			col.size = Vector3(1.0, 4.2, 1.0)
			pillar.mesh = col
			pillar.position.y = 2.1
			pillar.material_override = _hd_rock_mat(Color(0.6, 0.56, 0.5), 0.78)
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


## Photo-rock StandardMaterial3D for landmark geometry (tint multiplies the photo
## albedo). Textures load lazily; before import or on missing files the tint alone
## still shades the mesh, so landmarks never disappear.
func _hd_rock_mat(tint: Color, rough := 0.85) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = load(HD_ROCK_ALBEDO)
	mat.normal_enabled = true
	mat.normal_texture = load(HD_ROCK_NORMAL)
	mat.ao_enabled = true
	mat.ao_texture = load(HD_ROCK_AO)
	mat.roughness = rough
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


## Photo-marble material for landmark trim/caps.
func _hd_marble_mat(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = load(HD_MARBLE_ALBEDO)
	mat.roughness = 0.22
	mat.metallic = 0.05
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


## Deterministic, precomputed navigation floor (no runtime baking). Two layers,
## built from the same obstacle set that owns the collision shapes:
##   * ArenaNavGrid — authoritative for enemy steering: shared flow field +
##     A* that routes AROUND pillars, blocks and the landmark;
##   * the legacy flat NavigationMesh — kept for NavigationAgent3D fallback in
##     scenes without a grid (obstacle-free interiors only).
func _build_navigation_floor() -> void:
	var region := get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if region != null:
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
	_nav_grid = ArenaNavGrid.new()
	var aabbs: Array = []
	for ob in _obstacles:
		aabbs.append(ob)
	if _landmark_half.x > 0.0 or _landmark_half.z > 0.0:
		aabbs.append({"pos": Vector3.ZERO, "half_size": _landmark_half})
	_nav_grid.build(interior_half, nav_cell_size, aabbs)


## Rebuild after a theme switch swaps the landmark (idempotent, cheap).
func _rebuild_navigation_floor() -> void:
	_build_navigation_floor()


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
	var grid := {} if _nav_grid == null else _nav_grid.get_debug_snapshot()
	return {
		"arena_id": String(arena_id),
		"spawn_point_count": get_spawn_points().size(),
		"player_start": _vec_string(get_player_start()),
		"obstacles": _obstacles.size(),
		"nav_grid": grid,
	}


func _vec_string(node: Node3D) -> Vector3:
	if node == null:
		return Vector3.ZERO
	return node.global_position
