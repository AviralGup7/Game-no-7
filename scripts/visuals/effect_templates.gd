class_name EffectTemplates
extends RefCounted

## Node recipes for the pooled VFX: one-shot burst emitters and flat ground rings.
##
## The EffectDirector owns the pool and reuses these nodes; this module only builds
## them (and holds the generic particle recipe the skill catalog overrides on top of),
## so construction never needs a live tree or an autoload.

# Generic burst recipe — the shape every pooled emitter starts from.
const BURST_SPREAD_DEGREES := 68.0
const BURST_AMOUNT := 22
const BURST_LIFETIME := 0.68
const BURST_GRAVITY := -4.2
const BURST_VELOCITY_MIN := 1.2
const BURST_VELOCITY_MAX := 4.2
const BURST_SCALE_MIN := 0.14
const BURST_SCALE_MAX := 0.38
const BURST_SPIN_MIN := -120.0
const BURST_SPIN_MAX := 120.0
const BURST_TINT := Color(1.0, 0.85, 0.55)

# Ring + sprite geometry.
const SPRITE_SIZE := Vector2(0.2, 0.2)
const RING_QUAD_SIZE := Vector2(1.0, 1.0)
const RING_ALPHA := 0.52
const RING_EMISSION_ENERGY := 0.35


## One-shot burst emitter, or null when the texture is unavailable (particles
## unsupported / asset missing) so callers keep their no-op path.
static func make_burst(burst_texture: String) -> GPUParticles3D:
	if not ResourceLoader.exists(burst_texture):
		return null
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = BURST_SPREAD_DEGREES
	mat.gravity = Vector3(0, BURST_GRAVITY, 0)
	mat.initial_velocity_min = BURST_VELOCITY_MIN
	mat.initial_velocity_max = BURST_VELOCITY_MAX
	mat.scale_min = BURST_SCALE_MIN
	mat.scale_max = BURST_SCALE_MAX
	mat.color = BURST_TINT
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.angular_velocity_min = BURST_SPIN_MIN
	mat.angular_velocity_max = BURST_SPIN_MAX
	var p := GPUParticles3D.new()
	p.process_material = mat
	p.amount = BURST_AMOUNT
	p.lifetime = BURST_LIFETIME
	p.one_shot = true
	p.explosiveness = 1.0
	p.draw_pass_1 = make_sprite(burst_texture)
	p.emitting = false
	return p


## Expanding translucent disc lying flat on the ground (RingFade fades it out when
## the director triggers it), hidden until claimed.
static func make_ring(ring_texture: String) -> Node3D:
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = &"Disc"
	var quad := QuadMesh.new()
	quad.size = RING_QUAD_SIZE
	mi.mesh = quad
	mi.rotation_degrees.x = -90.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = load(ring_texture)
	mat.albedo_color = Color(1, 1, 1, RING_ALPHA)
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = RING_EMISSION_ENERGY
	mi.material_override = mat
	holder.add_child(mi)
	holder.visible = false
	holder.set_script(load("res://scripts/visuals/ring_fade.gd"))
	return holder


## Billboard sprite used as the particles' quad draw pass.
static func make_sprite(path: String) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = SPRITE_SIZE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = load(path)
	quad.material = mat
	return quad
