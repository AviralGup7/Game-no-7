class_name ArenaLandmark
extends Node3D

## The arena's centrepiece: silhouette meshes, one collision body, one fill light. Extracted
## out of `arena.gd` (where two `match kind` statements with a `_:` fallback built it inline,
## ~150 lines of the file's 533) so that the only thing `arena.gd` has to know is a config.
##
## What stays code is the *silhouette*: a forge is a basin with lava in it, a crystal cluster
## is three prisms, an obelisk is a shaft with a cap. What became data is everything else —
## which kind, where, how big, what colour, how lit — see ArenaLandmarkConfig.
##
## Contract with `Arena`: the collision body is built from `footprint_half`, and `footprint()`
## returns the same box scaled, so the nav grid blocks exactly what physics blocks. The
## holder's own transform carries position/rotation/scale, which is why every child number
## below is local: scaling the landmark scales its body and its blocker together.

const ROCK_ALBEDO := "res://assets/textures/rock/rock_albedo.png"
const ROCK_NORMAL := "res://assets/textures/rock/rock_normal.png"
const ROCK_AO := "res://assets/textures/rock/rock_ao.png"
var config: ArenaLandmarkConfig = null

var _footprint_usable: bool = false
var _mesh_count: int = 0
var _has_light: bool = false


## Build under `parent` and return the node. Idempotent from the caller's side: `arena.gd`
## frees the previous holder before asking for a new one when a theme switches.
static func spawn(parent: Node3D, cfg: ArenaLandmarkConfig) -> ArenaLandmark:
	var holder := ArenaLandmark.new()
	holder.name = "Landmark"
	holder.build(cfg)
	parent.add_child(holder)
	return holder


func build(cfg: ArenaLandmarkConfig) -> void:
	config = cfg
	_footprint_usable = false
	_mesh_count = 0
	_has_light = false
	if cfg == null:
		return
	position = cfg.position
	rotation_degrees = cfg.rotation_degrees
	scale = Vector3.ONE * cfg.scale
	match cfg.kind:
		ArenaLandmarkConfig.KIND_FORGE:
			_build_forge(cfg)
		ArenaLandmarkConfig.KIND_CRYSTAL:
			_build_crystal(cfg)
		ArenaLandmarkConfig.KIND_OBELISK:
			_build_obelisk(cfg)
		_:
			# Unreachable for authored data (ArenaLandmarkConfig.validate() refuses it); a
			# config built in code gets nothing built, and reports it, rather than quietly
			# becoming an obelisk — which is what the old `_:` arm did.
			push_error("ArenaLandmark: kind '%s' has no builder" % String(cfg.kind))
			return
	_add_collision(cfg)
	_footprint_usable = true


## XZ+Y box the nav grid must block, in world-local arena metres, or an empty AABB when
## nothing was built (a landmark that does not exist must not block cells either).
func footprint() -> AABB:
	if not _footprint_usable or config == null:
		return AABB()
	var half := config.footprint_half * config.scale
	return AABB(config.position - half, half * 2.0)


# ------------------------------------------------------------------ silhouettes


func _build_forge(cfg: ArenaLandmarkConfig) -> void:
	# Stone basin with the emissive lava disc inside it, plus the warm point light.
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 1.8
	bm.bottom_radius = 2.1
	bm.height = 0.6
	base.mesh = bm
	base.position.y = 0.3
	base.material_override = _rock_mat(cfg.material_tint, cfg.material_roughness)
	add_child(base)
	var lava := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 1.25
	lm.bottom_radius = 1.25
	lm.height = 0.12
	lava.mesh = lm
	lava.position.y = 0.66
	lava.material_override = _emissive_mat(cfg.accent_color, cfg.emissive_energy, 0.35)
	add_child(lava)
	_add_light(cfg)
	_mesh_count = 2


func _build_crystal(cfg: ArenaLandmarkConfig) -> void:
	# Three prisms on a circle, cool translucent glow.
	for i in range(3):
		var prism := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.7, 2.2 + i * 0.6, 0.7)
		prism.mesh = pm
		prism.position = Vector3(cos(i * TAU / 3.0) * 0.5, 1.1, sin(i * TAU / 3.0) * 0.5)
		prism.rotation.y = i * 0.9
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = cfg.material_tint
		cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cmat.roughness = cfg.material_roughness
		cmat.metallic = 0.1
		cmat.emission_enabled = true
		cmat.emission = cfg.accent_color
		cmat.emission_energy_multiplier = cfg.emissive_energy
		prism.material_override = cmat
		add_child(prism)
		_mesh_count += 1
	_add_light(cfg)


func _build_obelisk(cfg: ArenaLandmarkConfig) -> void:
	# Ancient column with a metal-capped top; the default silhouette of the shared arena.
	var pillar := MeshInstance3D.new()
	var col := BoxMesh.new()
	col.size = Vector3(1.0, 4.2, 1.0)
	pillar.mesh = col
	pillar.position.y = 2.1
	pillar.material_override = _rock_mat(cfg.material_tint, cfg.material_roughness)
	add_child(pillar)
	var cap := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.25, 0.35, 1.25)
	cap.mesh = cm
	cap.position.y = 4.4
	cap.material_override = _emissive_mat(cfg.accent_color, cfg.emissive_energy, 0.25, 0.6)
	add_child(cap)
	_add_light(cfg)
	_mesh_count = 2


# ------------------------------------------------------------------ shared parts


func _add_light(cfg: ArenaLandmarkConfig) -> void:
	if cfg.light_energy <= 0.0:
		return
	var light := OmniLight3D.new()
	light.light_color = cfg.light_color
	light.light_energy = cfg.light_energy
	light.omni_range = cfg.light_range
	light.position.y = cfg.light_offset_y
	add_child(light)
	_has_light = true


## The one body: authored footprint, so `footprint()` above and the physics agree by
## construction rather than by remembering to keep two numbers aligned.
func _add_collision(cfg: ArenaLandmarkConfig) -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = CollisionLayers.WORLD_BODY_LAYER
	body.collision_mask = CollisionLayers.NO_LAYER
	var shape := CollisionShape3D.new()
	shape.position = Vector3(0.0, cfg.footprint_half.y, 0.0)
	if cfg.shape == ArenaLandmarkConfig.SHAPE_CYLINDER:
		var cyl := CylinderShape3D.new()
		cyl.radius = cfg.footprint_half.x
		cyl.height = cfg.footprint_half.y * 2.0
		shape.shape = cyl
	else:
		var box := BoxShape3D.new()
		box.size = cfg.footprint_half * 2.0
		shape.shape = box
	body.add_child(shape)
	add_child(body)


## Photo-rock material for landmark geometry (tint multiplies the photo albedo). Textures
## load lazily; before import or on missing files the tint alone still shades the mesh, so a
## landmark never disappears because an asset is absent.
func _rock_mat(tint: Color, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = load(ROCK_ALBEDO)
	mat.normal_enabled = true
	mat.normal_texture = load(ROCK_NORMAL)
	mat.ao_enabled = true
	mat.ao_texture = load(ROCK_AO)
	mat.roughness = rough
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


func _emissive_mat(accent: Color, energy: float, rough: float, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = accent
	mat.emission_enabled = true
	mat.emission = accent
	mat.emission_energy_multiplier = energy
	mat.roughness = rough
	mat.metallic = metallic
	return mat
