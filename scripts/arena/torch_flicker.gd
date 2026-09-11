class_name TorchFlicker
extends Node3D

## Cosmetic light + flame flicker for the HD arena sconces. Pure presentation:
## no gameplay, collision or audio. Each torch keeps its own deterministic phase
## (seeded from `seed_value`) so wall torches never blink in perfect sync while
## the run stays reproducible for a given seed.
##
## A billboard glow halo rides the same flicker signal as the flame and the light,
## so all three breathe together; it loads the approved Kenney flare sprite and
## degrades to flame-only when the texture is not imported.

const GLOW_TEXTURE := "res://assets/scifi/fx/flare.png"

@export var light: OmniLight3D = null
@export var flame: MeshInstance3D = null
@export var seed_value: int = 1
@export var base_energy: float = 1.5
@export var base_emission: float = 5.0

var _time: float = 0.0
var _phase_a: float = 0.0
var _phase_b: float = 0.0
var _flame_mat: StandardMaterial3D = null
var _glow: Sprite3D = null


func _ready() -> void:
	# The halo scale is written from _process (idle time), so opt out of physics
	# interpolation rather than fight it — the physics-timing suite requires it.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Deterministic per-torch phase from the configured seed (no global RNG).
	var mix := float(abs(seed_value % 1024)) + 1.0
	_phase_a = fmod(mix * 1.61803398875, TAU)
	_phase_b = fmod(mix * 0.61803398875 * 2.39996322973, TAU)
	if flame != null:
		var active := flame.get_active_material(0) as StandardMaterial3D
		if active != null:
			# Duplicate once so the four torches flicker independently; textures stay shared.
			_flame_mat = active.duplicate() as StandardMaterial3D
			flame.material_override = _flame_mat
			_base_emission_apply()
	_build_glow()


func _base_emission_apply() -> void:
	if _flame_mat != null:
		_flame_mat.emission_energy_multiplier = base_emission


## Warm halo billboard at the flame's seat. Optional art: a missing texture leaves the
## torch exactly as it was (flame mesh + light), never an error or an empty quad.
func _build_glow() -> void:
	if flame == null or not ResourceLoader.exists(GLOW_TEXTURE):
		return
	var tex := load(GLOW_TEXTURE) as Texture2D
	if tex == null:
		return
	_glow = Sprite3D.new()
	_glow.texture = tex
	_glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_glow.shaded = false
	_glow.pixel_size = 0.012
	_glow.modulate = Color(0.12, 0.65, 1.0, 0.5)
	_glow.position = flame.position + Vector3(0.0, 0.08, 0.0)
	add_child(_glow)


func _process(delta: float) -> void:
	_time += delta
	# Two incommensurate sine bands + a slow drift give a lively, non-periodic feel.
	var a := sin(_time * 11.3 + _phase_a)
	var b := sin(_time * 7.9 + _phase_b)
	var c := sin(_time * 3.1 + _phase_a * 2.0)
	var noise := (a * 0.5 + b * 0.35 + c * 0.15) * 0.5 + 0.5  # 0..1
	var factor := 0.82 + 0.3 * noise
	if light != null:
		light.light_energy = base_energy * factor
	if _flame_mat != null:
		_flame_mat.emission_energy_multiplier = base_emission * (0.85 + 0.35 * noise)
	if _glow != null:
		var tint := _glow.modulate
		tint.a = 0.38 + 0.28 * noise
		_glow.modulate = tint
		var halo := 0.9 + 0.25 * noise
		_glow.scale = Vector3(halo, halo, halo)
