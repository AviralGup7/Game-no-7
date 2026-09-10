extends Node3D
class_name Arena

## Composes the static environment + markers for one arena. Contains NO wave or score
## logic. Exposes metadata and marker lookup so GameRoot / SpawnManager (later) can
## drive gameplay without scene-specific knowledge.
##
## "Additional arenas = a new scene + an ArenaConfig" is a promise this file only started
## keeping now. It used to hold the arena identities itself, in three id-keyed places:
## `THEMES` (sky/fog/sun/tints/landmark per arena id string), `PANORAMA_SKIES` (the HDRI
## per id) and `ArenaObstacles.layout_for(arena_id, …)`. An ArenaConfig for an arena none of
## them knew produced a playable arena in the *default* look with the *default* pillars, and
## no line of code was in error. All three are fields on the config now (theme / landmark /
## obstacle_layout), so this file has no arena ids in it at all: it resolves one config for
## the live arena and builds the world from it. Unknown id, no .tres, or `theme == null` is
## still a working arena — it just keeps the look the scene authors, which is now an honest
## fallback instead of a table miss.

const SPAWN_POINT_GROUP := &"enemy_spawn_point"
## Lookup group for the live arena. UI (minimap) and any layout-agnostic consumer
## resolve the arena through this instead of scene paths — main.gd rebuilds the
## world synchronously and nodes may be renamed by the engine mid-frame, so path
## lookups against `WorldRoot/Arena` are the fragile pattern this group replaces.
const ARENA_GROUP := &"arena"

@export var arena_id: StringName = &"default_arena"
## Interior half-extent used to keep actors in-bounds and build the nav floor.
@export var interior_half: float = 12.0
@export var min_spawn_distance: float = 6.0
## Nav grid cell size (meters). 0.5 keeps paths smooth on a 24 m arena at a
## trivial cost (one shared grid, rebuilt only when the player crosses a cell).
@export var nav_cell_size: float = 0.5

const ARENA_CONFIG_DIR := "res://data/arenas/"
const OBSTACLE_MATERIAL := "res://assets/materials/arena_wall_stone.tres"

var _nav_grid: ArenaNavGrid = null
## The one source of truth for the interior: the authored placements, expanded for symmetry.
## Collision bodies, meshes and nav blockers are all built from this array, never re-derived.
var _obstacles: Array[ArenaObstaclePlacement] = []
var _landmark: ArenaLandmark = null
var _config: ArenaConfig = null
## Half-extents of the box the spawn solver keeps clear of. Production fills it from the built
## landmark (see `_build_landmark`) and nothing else writes it, which is the whole difference from the
## `_landmark_half` this file used to author alongside the landmark: that one was a second copy of a
## shape another object owns, and it went stale the moment the config moved. `set_landmark_block_half`
## is the suite seam for the solver's input when there is no scene graph to build.
var _landmark_block_half := Vector3.ZERO
## The solid decoration props' footprints (barrels, crates, rubble, braziers), published by
## `ArenaDecorator` after `decorate()`. They block nav cells exactly like the hand-authored obstacles,
## so AI routes around a barrel instead of pathing straight through it — and they arrive as the same
## typed `Array[AABB]` the authored placements are flattened into for `ArenaNavGrid.build`, so one
## grid is fed from two sources and neither of them speaks Dictionary.
var _decoration_blockers: Array[AABB] = []
var _flow_tick := 0.0


func _ready() -> void:
	add_to_group(ARENA_GROUP)
	_config = _resolve_config(_resolve_arena_id())
	# Order matters: theme (landmark) and obstacles must exist before the
	# navigation floor is built from their footprints.
	_spawn_obstacles()
	# Presentation: give the active arena its authored lighting/sky/mood + centrepiece.
	apply_theme()
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

## The authored pillar/rubble set (ArenaConfig.obstacle_layout, expanded for symmetry).
## Every entry becomes a StaticBody3D on CollisionLayers.WORLD_BODY_LAYER — the one layer
## both PLAYER_BODY_MASK and ENEMY_BODY_MASK collide with — plus a stone mesh,
## and is registered with the nav grid so AI routes around it instead of
## clipping through. Nothing can walk through objects anymore: physics for the
## bodies, nav grid for the intent.
func _spawn_obstacles() -> void:
	_obstacles = ArenaObstacles.layout_for(_config, interior_half)
	var parent := get_node_or_null("Obstacles") as Node3D
	if parent == null:
		parent = Node3D.new()
		parent.name = "Obstacles"
		add_child(parent)
	else:
		for c in parent.get_children():
			c.queue_free()
	var mat: Material = null
	var res := load(OBSTACLE_MATERIAL)
	if res is Material:
		mat = res
	ArenaObstacles.build_nodes(parent, _obstacles, mat)


## Presentation entry point: the arena's own theme + landmark, read from its config.
## Idempotent, and safe to call after a run changes the arena; a theme switch moves the
## centrepiece, so the shared nav grid is refreshed at the end of it.
func apply_theme() -> void:
	if _config == null:
		return
	if _config.theme != null:
		_apply_sky_and_light(_config.theme)
		_tint_surfaces(_config.theme)
	_spawn_landmark(_config.landmark)
	# Landmark footprint changed: refresh the shared nav grid so the AI's
	# intent avoids it exactly as the physics body blocks the bodies.
	_rebuild_navigation_floor()


## Registry first (the live, already-validated copy), disk second so the same arena id
## means the same world in the headless harness, where no autoload ran.
func _resolve_config(arena_id_value: StringName) -> ArenaConfig:
	if ContentRegistry != null:
		var registered: ArenaConfig = ContentRegistry.get_arena(arena_id_value)
		if registered != null:
			return registered
	var path := ARENA_CONFIG_DIR + String(arena_id_value) + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ArenaConfig


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


## Sky, sun, fog, tone map. Every number is authored on the theme resource; this function
## defaults nothing, so a missing field is a .tres the validator refused, not a silent colour.
## The Sky and Environment are built fresh rather than edited in place: two arenas in one
## process (or a theme switch mid-session) must not mutate a shared scene resource.
func _apply_sky_and_light(theme: ArenaThemeConfig) -> void:
	var sun := get_node_or_null("Lighting/Sun") as DirectionalLight3D
	if sun != null:
		sun.light_color = theme.sun_color
		sun.light_energy = theme.sun_energy
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_2048
	# Real HDRI panorama (photorealistic IBL) with the theme's procedural colours as the
	# fallback, so an arena still looks authored on a device where the .hdr is not imported.
	var pano: Texture2D = null
	if not theme.panorama_path.is_empty() and ResourceLoader.exists(theme.panorama_path):
		pano = load(theme.panorama_path)
	if pano != null:
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = pano
		# PanoramaSkyMaterial has no energy knob in Godot 4.4 (unlike
		# ProceduralSkyMaterial); the HDRI's exposure is governed by the Environment
		# (ambient energy + tonemap/adjustment brightness), which is why both are authored.
		sky.sky_material = pm
	else:
		var pm := ProceduralSkyMaterial.new()
		pm.sky_top_color = theme.sky_top
		pm.sky_horizon_color = theme.sky_horizon
		pm.ground_horizon_color = theme.ground_horizon
		pm.ground_bottom_color = theme.sky_horizon.darkened(0.6)
		sky.sky_material = pm
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.background_sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = theme.ambient_color
	env.ambient_light_energy = theme.ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Cinematic look: exposure/contrast + subtle bloom on emissives (torches, lava,
	# crystals). Mobile-renderer-safe: no SSAO/SSR/volumetrics are requested, and
	# glow_bloom is range-capped on the theme for the same reason (docs/ART_STYLE.md).
	env.adjustment_enabled = true
	env.adjustment_brightness = theme.brightness
	env.adjustment_contrast = theme.contrast
	env.glow_enabled = true
	env.glow_intensity = theme.glow_intensity
	env.glow_bloom = theme.glow_bloom
	env.glow_hdr_threshold = theme.glow_hdr_threshold
	env.fog_enabled = true
	env.fog_light_color = theme.fog_color
	env.fog_density = theme.fog_density
	env.fog_sky_affect = theme.fog_sky_affect
	var wenv := get_node_or_null("Environment") as WorldEnvironment
	if wenv != null:
		wenv.environment = env


## Floor + wall tints, through material_override so the shared scene material is never
## mutated. Which nodes get tinted is authored on the theme: matching on node names inside
## this file (`name == &"Floor"`, `begins_with("Wall")`) meant renaming a mesh in the editor
## silently stopped the arena being tinted, with no error and no way to retarget it.
func _tint_surfaces(theme: ArenaThemeConfig) -> void:
	if not theme.tint_floor_and_walls:
		return
	var floor_node := get_node_or_null(theme.floor_node_path)
	if floor_node is MeshInstance3D:
		_tint_mesh(floor_node as MeshInstance3D, theme.floor_tint)
	var root := get_node_or_null("Geometry")
	if root == null:
		return
	for child in root.get_children():
		if not child is MeshInstance3D:
			continue
		if not String(child.name).begins_with(theme.wall_node_prefix):
			continue
		_tint_mesh(child as MeshInstance3D, theme.wall_tint)


func _tint_mesh(mi: MeshInstance3D, tint: Color) -> void:
	if mi.mesh == null:
		return
	var base := mi.mesh.material as StandardMaterial3D
	var dup: StandardMaterial3D = (base.duplicate(true) if base != null else StandardMaterial3D.new())
	dup.albedo_color = tint
	mi.material_override = dup


## The centrepiece, if this arena wants one. Freeing the previous holder keeps this
## idempotent for theme switches and headless re-entry. `null` is authored, not a miss: an
## open-floor arena has no landmark, and after phase 5 it no longer gets an obelisk instead.
func _spawn_landmark(cfg: ArenaLandmarkConfig) -> void:
	var old := get_node_or_null("Landmark")
	if old != null:
		old.queue_free()
	_landmark = null
	_landmark_block_half = Vector3.ZERO
	if cfg == null:
		return
	_landmark = ArenaLandmark.spawn(self, cfg)
	if _landmark != null:
		# Asked once, at build: the footprint is the landmark's own answer about its shape.
		_landmark_block_half = _landmark.footprint().size * 0.5


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
	var blockers: Array[AABB] = ArenaObstacles.footprints(_obstacles)
	if _landmark != null:
		var landmark_box := _landmark.footprint()
		if ArenaObstacles.blocks_nav(landmark_box):
			blockers.append(landmark_box)
	# Solid decoration props are obstacles too: physics blocks their bodies, this blocks the AI's
	# intent through them, from the same footprints — one list, so the two cannot disagree.
	for foot in _decoration_blockers:
		blockers.append(foot)
	_nav_grid.build(interior_half, nav_cell_size, blockers)


## Register the solid decoration footprints and rebuild the shared nav grid so the AI
## routes around what the new colliders block. Called by ArenaDecorator.decorate();
## safe to call before any decoration exists (rebuilds with the current set).
## Suite/tooling seam: state the centrepiece's footprint half-extents without building a landmark.
## Not a second source of truth -- `_build_landmark` assigns the same value from the real landmark,
## and a hand-built Arena has no landmark to read.
func set_landmark_block_half(half: Vector3) -> void:
	_landmark_block_half = Vector3(
		maxf(0.0, half.x) if is_finite(half.x) else 0.0,
		maxf(0.0, half.y) if is_finite(half.y) else 0.0,
		maxf(0.0, half.z) if is_finite(half.z) else 0.0
	)


func register_decoration_blockers(blockers: Array[AABB]) -> void:
	# A copy, not a reference: `ArenaDecorator.reset()` clears and refills its own list, and a nav
	# rebuild must never observe a half-populated one. The Y extent is whatever the prop's box is, and
	# `blocks_nav` is the same rule the landmark above uses: the grid reads x and z, not height.
	_decoration_blockers.clear()
	for foot in blockers:
		if ArenaObstacles.blocks_nav(foot):
			_decoration_blockers.append(foot)
	_rebuild_navigation_floor()


## Rebuild after a theme switch swaps the landmark (idempotent, cheap).
func _rebuild_navigation_floor() -> void:
	_build_navigation_floor()


func get_arena_id() -> StringName:
	return arena_id


## The config this arena actually built itself from (null when the scene has no .tres for the
## live arena id). Exposed so a test or a debug overlay asserts against the resolution the
## game made instead of re-resolving and quietly getting a different answer.
func get_config() -> ArenaConfig:
	return _config


## The live landmark, or null when the arena authors none.
func get_landmark() -> ArenaLandmark:
	return _landmark


func get_interior_half() -> float:
	return interior_half


func get_min_spawn_distance() -> float:
	return min_spawn_distance


func get_player_start() -> Node3D:
	return get_node_or_null("PlayerStart") as Node3D


## Spawn pose that is on the floor, inside the playable box, and outside the
## central landmark. The authored marker can sit too close to the south wall
## (camera then starts in the HDRI "mountain" sky) or overlap the forge/obelisk.
func get_safe_player_spawn() -> Transform3D:
	var marker := get_player_start()
	var xf := Transform3D.IDENTITY
	if marker != null:
		xf = marker.global_transform
	xf.origin = unstuck_origin(xf.origin)
	if not xf.basis.is_conformal() or xf.basis.determinant() == 0.0:
		xf.basis = Basis.IDENTITY
	return xf


func unstuck_origin(p: Vector3) -> Vector3:
	var half := maxf(interior_half - 2.25, 3.0)
	if not is_finite(p.x):
		p.x = 0.0
	if not is_finite(p.y):
		p.y = 0.2
	if not is_finite(p.z):
		p.z = 4.5
	p.x = clampf(p.x, -half, half)
	p.z = clampf(p.z, -half, half)
	p.y = maxf(p.y, 0.15)
	# Derived from the landmark when there is one (see `_landmark_block_half`), so the solver and the
	# centrepiece cannot disagree; 1.35 m of clearance is the player's own body plus a step back.
	var need := 0.0
	if _landmark != null or _landmark_block_half != Vector3.ZERO:
		need = maxf(_landmark_block_half.x, _landmark_block_half.z) + 1.35
	var flat := Vector2(p.x, p.z)
	if need > 0.1 and flat.length() < need:
		var dir := flat.normalized() if flat.length() > 0.05 else Vector2(0.0, 1.0)
		p.x = dir.x * need
		p.z = dir.y * need
		p.x = clampf(p.x, -half, half)
		p.z = clampf(p.z, -half, half)
	return p


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
		"theme": String(_config.theme.theme_id) if _config != null and _config.theme != null else "scene",
		"landmark": String(_config.landmark.kind) if _config != null and _config.landmark != null else "none",
		"nav_grid": grid,
	}


func _vec_string(node: Node3D) -> Vector3:
	if node == null:
		return Vector3.ZERO
	return node.global_position
