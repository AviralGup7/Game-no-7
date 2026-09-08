class_name EffectDirector
extends Node

## Lightweight, pooled 3D VFX director for combat + wave + status feedback. It listens
## to existing EventBus signals (no gameplay edits) and spawns short-lived, low-count
## GPUParticles3D bursts + billboard rings so nothing accumulates or runs per frame.
##
## Mobile-safe:
##  - One shared template per effect type (cached), reused across the pool.
##  - Pool caps, one-shot particles, tiny amounts, short lifetimes.
##  - GPU particles only; no scripted per-frame emitter work beyond returning a ring.
##
## All methods are no-ops when particles are unsupported or the event node is invalid.

const MAX_BURSTS := 6
const MAX_RINGS := 10
const RING_TEXTURE := "res://assets/effects/kenney/circle_05.png"
const BURST_TEXTURE := "res://assets/effects/kenney/spark_01.png"

## Status effect visual accent -> colour (matches ART_STYLE readability accents).
const STATUS_COLORS := {
	&"burn": Color(1.0, 0.45, 0.12),
	&"bleed": Color(0.9, 0.15, 0.15),
	&"shock": Color(0.5, 0.75, 1.0),
	&"slow": Color(0.45, 0.75, 1.0),
	&"stun": Color(1.0, 0.85, 0.3),
	&"guard": Color(0.55, 0.7, 1.0),
	&"regen": Color(0.45, 1.0, 0.55),
	&"warcry": Color(1.0, 0.6, 0.25),
}

var _bursts: Array[GPUParticles3D] = []
var _burst_template: GPUParticles3D = null
var _ring_pool: Array[Node3D] = []
var _wired := false


func _ready() -> void:
	_wire_events()


## Death / impact explosion at a world position (pooled, no autoload dependency).
func burst_at(at: Vector3, color: Color, scale: float = 1.0) -> void:
	var p := _claim_burst()
	if p == null:
		return
	p.global_position = at
	var mat := p.process_material as ParticleProcessMaterial
	if mat != null:
		mat.color = color
	p.scale = Vector3.ONE * scale
	p.restart()
	EventBus.report_info("EffectDirector burst at %s" % str(at))


## Expanding telegraph/collect ring (flat translucent disc on the ground plane).
func ring_at(at: Vector3, color: Color, radius: float = 1.0) -> void:
	var ring := _claim_ring()
	if ring == null:
		return
	ring.global_position = at + Vector3(0.02, 0, 0.02)
	var mi := ring.get_node_or_null("Disc") as MeshInstance3D
	if mi != null:
		var mat := mi.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(color, 0.45)
	ring.scale = Vector3(radius, radius, radius)
	_show_ring(ring, 0.6)
	EventBus.report_info("EffectDirector ring at %s" % str(at))


# ---------------------- event wiring ----------------------

func _wire_events() -> void:
	if _wired or EventBus == null:
		return
	_wired = true
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.pickup_collected.connect(_on_pickup_collected)
	EventBus.status_applied.connect(_on_status_applied)
	EventBus.boss_spawned.connect(_on_boss_spawned)
	EventBus.boss_slain.connect(_on_boss_slain)


func _on_enemy_spawned(enemy: Node, _archetype: StringName) -> void:
	if is_instance_valid(enemy) and enemy is Node3D:
		ring_at((enemy as Node3D).global_position, Color(0.9, 0.5, 0.3), 1.1)


func _on_enemy_killed(enemy: Node, _archetype: StringName, _score: int, _currency: int) -> void:
	if is_instance_valid(enemy) and enemy is Node3D:
		burst_at((enemy as Node3D).global_position, Color(0.7, 0.5, 0.35), 0.9)


func _on_wave_started(wave_number: int, _planned: int) -> void:
	ring_at(Vector3.ZERO, Color(0.8, 0.5, 0.25), 6.0)


func _on_wave_completed(_wave_number: int, _bonus: int) -> void:
	ring_at(Vector3.ZERO, Color(1.0, 0.85, 0.35), 7.0)


func _on_boss_spawned(boss: Node, _boss_id: StringName) -> void:
	var at := Vector3.ZERO
	if is_instance_valid(boss) and boss is Node3D:
		at = (boss as Node3D).global_position
	ring_at(at, Color(0.9, 0.2, 0.15), 4.5)
	burst_at(at, Color(0.9, 0.3, 0.2), 1.6)


func _on_boss_slain(_boss_id: StringName) -> void:
	ring_at(Vector3.ZERO, Color(1.0, 0.8, 0.3), 8.0)


func _on_pickup_collected(pickup_id: StringName, _amount: int, collector: Node) -> void:
	var at := Vector3.ZERO
	if is_instance_valid(collector) and collector is Node3D:
		at = (collector as Node3D).global_position
	ring_at(at, Color(1.0, 0.85, 0.35), 0.8)


func _on_status_applied(target: Node, effect_id: StringName, _stacks: int) -> void:
	if not is_instance_valid(target) or not target is Node3D:
		return
	var color: Color = STATUS_COLORS.get(effect_id, Color(0.7, 0.7, 0.7))
	# Telegraph up to ~2 m above the target's feet so it reads over the body.
	var at := (target as Node3D).global_position + Vector3(0, 1.6, 0)
	ring_at(at, color, 0.7)


# ---------------------- pool management ----------------------

func _claim_burst() -> GPUParticles3D:
	if _burst_template == null:
		_burst_template = _make_burst_template()
		if _burst_template == null:
			return null
	for b in _bursts:
		if not b.emitting:
			return b
	# Grow the pool up to the mobile cap.
	if _bursts.size() < MAX_BURSTS:
		var b := _make_burst_template() as GPUParticles3D
		if b == null:
			return null
		add_child(b)
		_bursts.append(b)
		return b
	return null


func _claim_ring() -> Node3D:
	for r in _ring_pool:
		if not r.visible:
			return r
	if _ring_pool.size() < MAX_RINGS:
		var r := _make_ring()
		if r != null:
			add_child(r)
			_ring_pool.append(r)
			return r
	return null


## One-shot bursts recycle automatically when particles finish (one_shot + short life).
func _make_burst_template() -> GPUParticles3D:
	if not _has_particle_texture(BURST_TEXTURE):
		return null
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 55.0
	mat.gravity = Vector3(0, -3.0, 0)
	mat.initial_velocity_min = 0.8
	mat.initial_velocity_max = 2.6
	mat.scale_min = 0.1
	mat.scale_max = 0.28
	mat.color = Color(0.8, 0.7, 0.6)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	var p := GPUParticles3D.new()
	p.process_material = mat
	p.amount = 14
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 1.0
	p.draw_pass_1 = _make_sprite(BURST_TEXTURE)
	p.emitting = false
	return p


## Expanding translucent disc lying flat on the ground (rotates up-facing, fades out).
func _make_ring() -> Node3D:
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = &"Disc"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mi.mesh = quad
	mi.rotation_degrees.x = -90.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = load(RING_TEXTURE)
	mat.albedo_color = Color(1, 1, 1, 0.45)
	mi.material_override = mat
	holder.add_child(mi)
	holder.visible = false
	holder.set_script(load("res://scripts/visuals/ring_fade.gd"))
	return holder


func _make_sprite(path: String) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = load(path)
	quad.material = mat
	return quad


func _show_ring(ring: Node3D, duration: float) -> void:
	ring.visible = true
	if ring.has_method("trigger"):
		ring.call("trigger", duration)


func _has_particle_texture(path: String) -> bool:
	return load(path) != null
