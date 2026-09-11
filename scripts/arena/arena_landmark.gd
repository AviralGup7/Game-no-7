class_name ArenaLandmark
extends Node3D

## The arena's centrepiece: silhouette meshes, one collision body, one fill light. Extracted
## out of `arena.gd` (where two `match kind` statements with a `_:` fallback built it inline,
## ~150 lines of the file's 533) so that the only thing `arena.gd` has to know is a config.
##
## What stays code is the *silhouette*: a forge is a basin with lava in it, a crystal cluster
## is five prisms, an obelisk is a shaft with a cap. What became data is everything else —
## which kind, where, how big, what colour, how lit — see ArenaLandmarkConfig.
##
## Every silhouette also carries its own floor art: a plinth disc seated on the dais, an
## emissive rim at the plinth's edge, and a wide accent ring on the arena floor outside the
## dais. The three silhouettes read differently from across the dungeon without a single texture.
##
## The landmark idles: registered emissive materials breathe on one shared pulse and the
## forge's lava (with its dark crust chips riding on top) rotates slowly. Presentation only —
## gameplay reads `footprint()` and nothing here moves a collider. The pulse pauses with the
## tree (default process mode), so hitstop and pause freeze the glow with everything else.
##
## Contract with `Arena`: the collision body is built from `footprint_half`, and `footprint()`
## returns the same box scaled, so the nav grid blocks exactly what physics blocks. The
## holder's own transform carries position/rotation/scale, which is why every child number
## below is local: scaling the landmark scales its body and its blocker together.

const ROCK_ALBEDO := "res://assets/environment/space_station/panel.png"
## Wide floor ring every silhouette wears, parked outside the dais rim (3.05 m) so it
## reads on the arena floor instead of hiding under the dais plate.
const FLOOR_RING_OUTER := 3.3
const FLOOR_RING_INNER := 3.12
var config: ArenaLandmarkConfig = null

var _footprint_usable: bool = false
var _mesh_count: int = 0
var _has_light: bool = false
## Idle-animation state. `_pulse_base[i]` is the authored emission energy `_pulse_mats[i]`
## breathes around; `_spin` is the one rotating child (the forge lava with its crust).
var _time: float = 0.0
var _pulse_mats: Array[StandardMaterial3D] = []
var _pulse_base: Array[float] = []
var _spin: MeshInstance3D = null


## Build under `parent` and return the node. Idempotent from the caller's side: `arena.gd`
## frees the previous holder before asking for a new one when a theme switches.
static func spawn(parent: Node3D, cfg: ArenaLandmarkConfig) -> ArenaLandmark:
	var holder := ArenaLandmark.new()
	holder.name = "Landmark"
	holder.build(cfg)
	parent.add_child(holder)
	return holder


func build(cfg: ArenaLandmarkConfig) -> void:
	# The lava disc rotates from _process (idle time), so opt out of physics
	# interpolation rather than fight it — the physics-timing suite requires it.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	config = cfg
	_footprint_usable = false
	_mesh_count = 0
	_has_light = false
	_time = 0.0
	_pulse_mats.clear()
	_pulse_base.clear()
	_spin = null
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


func _process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	if _pulse_mats.is_empty() and _spin == null:
		return
	_time += delta
	if _spin != null and is_instance_valid(_spin):
		_spin.rotation.y += delta * 0.35
	if _pulse_mats.is_empty():
		return
	var k := 0.86 + 0.14 * sin(_time * 2.1)
	for i in range(_pulse_mats.size()):
		var mat := _pulse_mats[i]
		if mat != null and is_instance_valid(mat):
			mat.emission_energy_multiplier = _pulse_base[i] * k


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
	_mesh_count += 1
	_torus(self, 2.08, 1.82, 0.6, _rock_mat(cfg.material_tint.darkened(0.2), cfg.material_roughness))
	_mesh_count += 1
	var lava := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 1.25
	lm.bottom_radius = 1.25
	lm.height = 0.12
	lava.mesh = lm
	lava.position.y = 0.66
	var lava_mat := _emissive_mat(cfg.accent_color, cfg.emissive_energy, 0.35)
	lava.material_override = lava_mat
	_register_pulse(lava_mat)
	add_child(lava)
	_mesh_count += 1
	# Dark crust chips riding the lava: the rotation reads only because they orbit.
	var crust_mat := _rock_mat(cfg.material_tint.darkened(0.55), 0.9)
	for i in range(3):
		var chip := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.5, 0.06, 0.34)
		chip.mesh = cm
		var chip_angle := float(i) * TAU / 3.0
		chip.position = Vector3(cos(chip_angle) * 0.68, 0.075, sin(chip_angle) * 0.68)
		chip.rotation.y = chip_angle * 1.7
		chip.material_override = crust_mat
		lava.add_child(chip)
		_mesh_count += 1
	_spin = lava
	# Scattered embers on the plinth, breathing with the lava.
	var ember_mat := _emissive_mat(cfg.accent_color.lightened(0.2), cfg.emissive_energy * 0.8, 0.4)
	_register_pulse(ember_mat)
	for i in range(3):
		var stone := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.2
		sm.height = 0.4
		stone.mesh = sm
		var stone_angle := 0.5 + float(i) * TAU / 3.0
		stone.position = Vector3(cos(stone_angle) * 2.2, 0.31, sin(stone_angle) * 2.2)
		stone.material_override = ember_mat
		add_child(stone)
		_mesh_count += 1
	_build_floor_art(cfg)
	_add_light(cfg)


func _build_crystal(cfg: ArenaLandmarkConfig) -> void:
	# Five prisms on a rock bed, cool translucent glow, one bright heart shard.
	var bed := MeshInstance3D.new()
	var bedm := CylinderMesh.new()
	bedm.top_radius = 1.45
	bedm.bottom_radius = 1.6
	bedm.height = 0.3
	bed.mesh = bedm
	bed.position.y = 0.15
	bed.material_override = _rock_mat(cfg.material_tint.darkened(0.25), cfg.material_roughness)
	add_child(bed)
	_mesh_count += 1
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = cfg.material_tint
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.roughness = cfg.material_roughness
	cmat.metallic = 0.1
	cmat.emission_enabled = true
	cmat.emission = cfg.accent_color
	cmat.emission_energy_multiplier = cfg.emissive_energy
	_register_pulse(cmat)
	var heights := [2.6, 1.7, 3.3, 2.1, 2.9]
	for i in range(5):
		var prism := MeshInstance3D.new()
		var pm := PrismMesh.new()
		var h: float = heights[i]
		pm.size = Vector3(0.62 + float(i % 3) * 0.09, h, 0.62 + float((i + 1) % 3) * 0.09)
		prism.mesh = pm
		var prism_angle := float(i) * TAU / 5.0
		prism.position = Vector3(cos(prism_angle) * 0.62, 0.15 + h * 0.5, sin(prism_angle) * 0.62)
		prism.rotation.y = prism_angle
		prism.rotation.x = 0.1 if i % 2 == 0 else -0.08
		prism.rotation.z = -0.06 if i % 3 == 0 else 0.09
		prism.material_override = cmat
		add_child(prism)
		_mesh_count += 1
	var heart := MeshInstance3D.new()
	var hm := PrismMesh.new()
	hm.size = Vector3(0.5, 3.8, 0.5)
	heart.mesh = hm
	heart.position.y = 2.05
	var heart_mat := StandardMaterial3D.new()
	heart_mat.albedo_color = cfg.material_tint.lightened(0.3)
	heart_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	heart_mat.roughness = cfg.material_roughness * 0.5
	heart_mat.metallic = 0.1
	heart_mat.emission_enabled = true
	heart_mat.emission = cfg.accent_color.lightened(0.25)
	heart_mat.emission_energy_multiplier = cfg.emissive_energy * 1.5
	_register_pulse(heart_mat)
	heart.material_override = heart_mat
	add_child(heart)
	_mesh_count += 1
	_build_floor_art(cfg)
	_add_light(cfg)


func _build_obelisk(cfg: ArenaLandmarkConfig) -> void:
	# Ancient column on a stepped plinth, rune band glowing at its waist, metal-capped top.
	var step1 := MeshInstance3D.new()
	var s1m := BoxMesh.new()
	s1m.size = Vector3(1.7, 0.3, 1.7)
	step1.mesh = s1m
	step1.position.y = 0.2
	step1.material_override = _rock_mat(cfg.material_tint.darkened(0.15), cfg.material_roughness)
	add_child(step1)
	_mesh_count += 1
	var step2 := MeshInstance3D.new()
	var s2m := BoxMesh.new()
	s2m.size = Vector3(1.35, 0.3, 1.35)
	step2.mesh = s2m
	step2.position.y = 0.5
	step2.material_override = _rock_mat(cfg.material_tint.darkened(0.05), cfg.material_roughness)
	add_child(step2)
	_mesh_count += 1
	var pillar := MeshInstance3D.new()
	var col := BoxMesh.new()
	col.size = Vector3(1.0, 4.2, 1.0)
	pillar.mesh = col
	pillar.position.y = 2.75
	pillar.material_override = _rock_mat(cfg.material_tint, cfg.material_roughness)
	add_child(pillar)
	_mesh_count += 1
	var band := MeshInstance3D.new()
	var bnd := BoxMesh.new()
	bnd.size = Vector3(1.08, 0.2, 1.08)
	band.mesh = bnd
	band.position.y = 3.3
	var band_mat := _emissive_mat(cfg.accent_color, cfg.emissive_energy, 0.4)
	_register_pulse(band_mat)
	band.material_override = band_mat
	add_child(band)
	_mesh_count += 1
	var cap := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.25, 0.35, 1.25)
	cap.mesh = cm
	cap.position.y = 5.02
	var cap_mat := _emissive_mat(cfg.accent_color, cfg.emissive_energy, 0.25, 0.6)
	_register_pulse(cap_mat)
	cap.material_override = cap_mat
	add_child(cap)
	_mesh_count += 1
	_build_floor_art(cfg)
	_add_light(cfg)


## Plinth disc seated on the dais, emissive rim at its edge, wide accent ring on the
## floor. One shared pulse material for both rings so the floor art breathes as one.
func _build_floor_art(cfg: ArenaLandmarkConfig) -> void:
	var plinth_r := minf(maxf(cfg.footprint_half.x, cfg.footprint_half.z) + 0.6, 2.5)
	var plinth := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = plinth_r
	pm.bottom_radius = plinth_r
	pm.height = 0.05
	pm.radial_segments = 40
	plinth.mesh = pm
	plinth.position.y = 0.085
	plinth.material_override = _rock_mat(cfg.material_tint.darkened(0.35), cfg.material_roughness)
	add_child(plinth)
	_mesh_count += 1
	var ring_mat := _emissive_mat(cfg.accent_color, cfg.emissive_energy * 0.7, 0.5)
	_register_pulse(ring_mat)
	_torus(self, plinth_r, plinth_r - 0.16, 0.115, ring_mat)
	_mesh_count += 1
	_torus(self, FLOOR_RING_OUTER, FLOOR_RING_INNER, 0.035, ring_mat)
	_mesh_count += 1


# ------------------------------------------------------------------ shared parts


## A material that breathes with the landmark's idle pulse around its authored energy.
func _register_pulse(mat: StandardMaterial3D) -> void:
	_pulse_mats.append(mat)
	_pulse_base.append(mat.emission_energy_multiplier)


## Flat emissive/stone ring (a squashed torus) for rims, plinths and the floor circle.
func _torus(parent: Node, outer: float, inner: float, y: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.outer_radius = outer
	tm.inner_radius = inner
	tm.rings = 10
	tm.ring_segments = 32
	mi.mesh = tm
	mi.position.y = y
	mi.scale.y = 0.35
	mi.material_override = mat
	parent.add_child(mi)
	return mi


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


## Shared station panel for landmark geometry. Textures
## load lazily; before import or on missing files the tint alone still shades the mesh, so a
## landmark never disappears because an asset is absent.
func _rock_mat(tint: Color, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	if ResourceLoader.exists(ROCK_ALBEDO):
		mat.albedo_texture = load(ROCK_ALBEDO)
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
