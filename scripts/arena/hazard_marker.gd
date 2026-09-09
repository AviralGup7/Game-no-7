class_name HazardMarker
extends Node3D

## The optional visual for one hazard: a flat disc that brightens while the hazard is
## arming. Built from the SAME radius the gameplay uses, and deliberately incapable of
## affecting gameplay — gameplay writes at most a pulse level and (for movers) a position
## per tick, and reads nothing back.
##
## Two things this replaces: (1) a hazard record that carried its node in a Dictionary and
## dug the mesh back out through set_meta("disc")/get_meta("disc") on every frame it wanted
## to glow — metadata is a scene-annotation facility, and it is measurably slow in the hot
## path; (2) the "base colour" the tick code kept reading through metadata and never used.
## Both live here as typed fields now.

var _disc: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _rest_emission: float = 0.4
var _peak_emission: float = 1.2
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
	var height := maxf(config.marker_height, 0.01)
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
	_material.emission = Color(config.marker_color.r, config.marker_color.g, config.marker_color.b, 1.0)
	_material.emission_energy_multiplier = _rest_emission
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc.material_override = _material
	add_child(_disc)


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
