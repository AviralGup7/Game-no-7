class_name HazardMarker
extends Node3D

## The optional visual for one hazard: a flat disc that brightens while the hazard is
## arming. Built from the SAME radius the gameplay uses, and deliberately incapable of
## affecting gameplay — gameplay writes at most a pulse level and (for movers) a position
## per tick, and reads nothing back.
##
## The disc is the honest hitbox read and never lies about the radius: nothing here scales
## it. Around and beneath it, the marker dresses the hazard so its kind reads at a glance:
## a crisp rim ring at the exact radius, a KayKit floor model under the disc for the kinds
## that have a physical form (spike bed, open vent, pressure plate), and a floating ember
## orb for the orbiting mover. Every extra is optional art — a missing model leaves the
## disc and the rim, which is the whole telegraph.
##
## Two things this replaces: (1) a hazard record that carried its node in a Dictionary and
## dug the mesh back out through set_meta("disc")/get_meta("disc") on every frame it wanted
## to glow — metadata is a scene-annotation facility, and it is measurably slow in the hot
## path; (2) the "base colour" the tick code kept reading through metadata and never used.
## Both live here as typed fields now.

const DUNGEON := "res://assets/scifi/"
## Floor model per hazard id. `fit` scales the model's 4 m tile to the live radius
## (placements can override it, so the model follows the hitbox); a fixed scale keeps
## the plate's 4 m tile glued to its 2 m trigger instead of its 3.5 m blast. `lift`
## seats the tile's base on the floor (KayKit tiles sit 0.1 m under their origin).
const MODEL_BY_HAZARD := {
	&"spike_bed": {"path": DUNGEON + "hazard_tile.glb", "fit": true, "fixed": 1.0, "lift": 0.0},
	&"fire_vent": {"path": DUNGEON + "hazard_tile.glb", "fit": true, "fixed": 1.0, "lift": 0.0},
	&"pressure_plate": {"path": DUNGEON + "hazard_tile.glb", "fit": false, "fixed": 1.0, "lift": 0.0},
}
const TILE_METRES := 4.0
const MIN_FIT_SCALE := 0.35
const MAX_FIT_SCALE := 1.5
const RIM_WIDTH := 0.18

static var _scene_cache := {}

var _disc: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _rim_mat: StandardMaterial3D = null
var _rest_emission: float = 0.4
var _peak_emission: float = 1.2
var _rim_rest: float = 0.6
var _rim_peak: float = 1.8
var _level: float = 0.0
var _shimmer: float = 0.0


## Factory so the caller never has to know which children exist. Returns an unparented
## node; the owner adds it as a child of the hazard root.
static func build(config: HazardConfig, radius: float) -> HazardMarker:
	var marker := HazardMarker.new()
	marker.configure(config, radius)
	return marker


func configure(config: HazardConfig, radius: float) -> void:
	if config == null:
		return
	_rest_emission = config.marker_emission
	_peak_emission = maxf(config.marker_emission_armed, config.marker_emission)
	_rim_rest = _rest_emission * 1.5
	_rim_peak = _peak_emission * 1.5
	var height := maxf(config.marker_height, 0.01)
	var glow := Color(config.marker_color.r, config.marker_color.g, config.marker_color.b, 1.0)
	var mesh := CylinderMesh.new()
	# Discs lie flat on the floor and are as wide as the hitbox they represent.
	mesh.top_radius = maxf(radius, 0.1)
	mesh.bottom_radius = mesh.top_radius
	mesh.height = height
	mesh.radial_segments = 20
	mesh.rings = 1
	_disc = MeshInstance3D.new()
	_disc.mesh = mesh
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = config.marker_color
	_material.emission_enabled = true
	_material.emission = glow
	_material.emission_energy_multiplier = _rest_emission
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc.material_override = _material
	add_child(_disc)
	_build_rim(maxf(radius, 0.1), height, glow)
	_mount_floor_model(config, radius)
	_mount_orb(config)


## Crisp ring at the exact hitbox radius: the disc's soft edge is hard to judge at a
## glance, the rim is not. Energy-only pulse — the ring never moves off the radius.
func _build_rim(radius: float, height: float, glow: Color) -> void:
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.outer_radius = radius
	tm.inner_radius = maxf(radius - RIM_WIDTH, 0.1)
	tm.rings = 8
	tm.ring_segments = 28
	rim.mesh = tm
	rim.position.y = height * 0.5
	rim.scale.y = 0.4
	_rim_mat = StandardMaterial3D.new()
	_rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rim_mat.albedo_color = Color(glow.r, glow.g, glow.b, 0.85)
	_rim_mat.emission_enabled = true
	_rim_mat.emission = glow
	_rim_mat.emission_energy_multiplier = _rim_rest
	_rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim.material_override = _rim_mat
	add_child(rim)


func _mount_floor_model(config: HazardConfig, radius: float) -> void:
	var spec: Dictionary = MODEL_BY_HAZARD.get(config.hazard_id, {})
	if spec.is_empty():
		return
	var path := String(spec.get("path", ""))
	if path.is_empty():
		return
	if not _scene_cache.has(path):
		var res := load(path)
		_scene_cache[path] = res if res is PackedScene else null
	var scene: PackedScene = _scene_cache.get(path)
	if scene == null:
		return
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return
	var fit_scale := float(spec.get("fixed", 1.0))
	if bool(spec.get("fit", false)):
		fit_scale = clampf(radius * 2.0 / TILE_METRES, MIN_FIT_SCALE, MAX_FIT_SCALE)
	inst.scale = Vector3.ONE * fit_scale
	inst.position.y = float(spec.get("lift", 0.0)) * fit_scale
	add_child(inst)
	HdMaterials.polish(inst)


## The orbiting mover's heart: a floating ember the disc pulses beneath as it travels.
func _mount_orb(config: HazardConfig) -> void:
	if config.hazard_id != &"ember_mover":
		return
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	orb.mesh = sm
	orb.position.y = 0.9
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = config.marker_color
	mat.emission_enabled = true
	mat.emission = Color(config.marker_color.r, config.marker_color.g, config.marker_color.b, 1.0)
	mat.emission_energy_multiplier = _peak_emission
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orb.material_override = mat
	add_child(orb)


## level 0 = resting glow, 1 = fully armed. `shimmer` (0..1) is a game-time-driven wobble
## for the telegraph; passing a wall-clock value is what made vents visibly desync during
## hitstop.
func set_pulse(level: float, shimmer: float) -> void:
	var next_level := clampf(level, 0.0, 1.0)
	var next_shimmer := clampf(shimmer, 0.0, 1.0)
	if is_equal_approx(next_level, _level) and is_equal_approx(next_shimmer, _shimmer):
		return
	_level = next_level
	_shimmer = next_shimmer
	_apply()


func set_center(next_position: Vector3) -> void:
	position = next_position


func _apply() -> void:
	if _material == null or not is_instance_valid(_material):
		return
	var glow := lerpf(_rest_emission, _peak_emission, _level)
	if _level > 0.0:
		glow *= 0.85 + 0.15 * _shimmer
	_material.emission_energy_multiplier = glow if is_finite(glow) else _rest_emission
	if _rim_mat == null or not is_instance_valid(_rim_mat):
		return
	var rim_glow := lerpf(_rim_rest, _rim_peak, _level)
	if _level > 0.0:
		rim_glow *= 0.85 + 0.15 * _shimmer
	_rim_mat.emission_energy_multiplier = rim_glow if is_finite(rim_glow) else _rim_rest
