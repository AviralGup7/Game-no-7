class_name PlayerCosmetics
extends Node3D

## Attaches the player's prestige-unlocked cosmetics to the live hero. Prestige
## used to write cosmetic IDs into the save and stop there; this node reads them
## back (via the Cosmetics catalogue) and renders them in-world:
##
##   trail_ember / trail_frost -> a coloured GPUParticles3D trail that streams off
##       the player's feet as they move.
##   aura_legend               -> a slowly-rotating emissive ground ring + soft
##       upward motes surrounding the hero.
##
## Banners (banner_survivor / banner_last_stand) are arena-scoped and handled by
## ArenaDecorator; titles are HUD/summary text. This node owns only the two
## body-attached visual kinds so pooling/teardown stay local to the player.
##
## Mounted under the player's VisualRoot by Main after the model is validated.
## Always safe to attach: with no unlocked trail/aura it renders nothing.

const TRAIL_TEXTURE := "res://assets/scifi/fx/spark.png"

var _trail: GPUParticles3D = null
var _aura: Node3D = null


## Apply the cosmetics unlocked in `unlocked` (SaveManager.get_unlocked_cosmetics()).
## Idempotent: rebuilds from scratch so it can be called on run start or re-equip.
func apply(unlocked: Array) -> void:
	_clear()
	var trail_id := Cosmetics.active_trail(unlocked)
	if trail_id != &"":
		_build_trail(Cosmetics.color_of(trail_id))
	var aura_id := Cosmetics.active_aura(unlocked)
	if aura_id != &"":
		_build_aura(Cosmetics.color_of(aura_id))


func _clear() -> void:
	if _trail != null and is_instance_valid(_trail):
		_trail.queue_free()
	_trail = null
	if _aura != null and is_instance_valid(_aura):
		_aura.queue_free()
	_aura = null


func _build_trail(color: Color) -> void:
	if not ResourceLoader.exists(TRAIL_TEXTURE):
		return
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 25.0
	mat.gravity = Vector3(0, 1.2, 0)
	mat.initial_velocity_min = 0.2
	mat.initial_velocity_max = 0.8
	mat.scale_min = 0.10
	mat.scale_max = 0.26
	mat.color = color
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.3
	var p := GPUParticles3D.new()
	p.name = "CosmeticTrail"
	p.process_material = mat
	p.amount = 24
	p.lifetime = 0.7
	p.one_shot = false
	p.emitting = true
	p.local_coords = false
	p.draw_pass_1 = _spark_quad(color)
	p.position = Vector3(0, 0.4, 0)
	add_child(p)
	_trail = p


func _build_aura(color: Color) -> void:
	var holder := Node3D.new()
	holder.name = "CosmeticAura"
	# Flat emissive ground ring encircling the hero.
	var ring := MeshInstance3D.new()
	ring.name = "AuraRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.7
	torus.outer_radius = 0.95
	ring.mesh = torus
	ring.rotation_degrees.x = 90.0
	ring.position = Vector3(0, 0.06, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color, 0.65)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	ring.material_override = mat
	holder.add_child(ring)
	# Soft rising motes for a "legend" shimmer.
	if ResourceLoader.exists(TRAIL_TEXTURE):
		var motes_mat := ParticleProcessMaterial.new()
		motes_mat.direction = Vector3.UP
		motes_mat.spread = 8.0
		motes_mat.gravity = Vector3(0, 0.6, 0)
		motes_mat.initial_velocity_min = 0.3
		motes_mat.initial_velocity_max = 0.7
		motes_mat.scale_min = 0.06
		motes_mat.scale_max = 0.16
		motes_mat.color = color
		motes_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		motes_mat.emission_ring_radius = 0.85
		motes_mat.emission_ring_inner_radius = 0.7
		motes_mat.emission_ring_height = 0.1
		motes_mat.emission_ring_axis = Vector3.UP
		var motes := GPUParticles3D.new()
		motes.name = "AuraMotes"
		motes.process_material = motes_mat
		motes.amount = 18
		motes.lifetime = 1.6
		motes.emitting = true
		motes.local_coords = false
		motes.draw_pass_1 = _spark_quad(color)
		holder.add_child(motes)
	add_child(holder)
	_aura = holder
	_spin_aura(holder)


func _spin_aura(holder: Node3D) -> void:
	if holder == null or not is_instance_valid(holder) or not is_inside_tree():
		return
	var tween := holder.create_tween()
	tween.set_loops()
	tween.tween_property(holder, "rotation:y", TAU, 6.0).from(0.0)


func _spark_quad(color: Color) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	if ResourceLoader.exists(TRAIL_TEXTURE):
		mat.albedo_texture = load(TRAIL_TEXTURE)
	quad.material = mat
	return quad
