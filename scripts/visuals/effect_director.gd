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

const MAX_BURSTS := 10
const MAX_RINGS := 14
const MAX_MUZZLE := 4
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

const SKILL_COLORS := {
	&"bladestorm": Color(0.88, 0.62, 0.18),
	&"frost_nova": Color(0.42, 0.76, 1.0),
	&"phantom_rush": Color(0.64, 0.42, 1.0),
	&"seismic_slam": Color(0.82, 0.48, 0.18),
	&"warcry": Color(1.0, 0.42, 0.22),
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
	EventBus.enemy_damaged.connect(_on_enemy_damaged)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.pickup_collected.connect(_on_pickup_collected)
	EventBus.pickup_spawned.connect(_on_pickup_spawned)
	EventBus.status_applied.connect(_on_status_applied)
	EventBus.boss_spawned.connect(_on_boss_spawned)
	EventBus.boss_slain.connect(_on_boss_slain)
	EventBus.projectile_fired.connect(_on_projectile_fired)
	EventBus.skill_cast.connect(_on_skill_cast)
	EventBus.player_leveled_up.connect(_on_player_leveled_up)
	EventBus.weapon_equipped.connect(_on_weapon_equipped)


func _on_enemy_spawned(enemy: Node, _archetype: StringName) -> void:
	if is_instance_valid(enemy) and enemy is Node3D:
		ring_at((enemy as Node3D).global_position, Color(0.9, 0.55, 0.3), 1.25)


func _on_enemy_killed(enemy: Node, _archetype: StringName, _score: int, _currency: int) -> void:
	if is_instance_valid(enemy) and enemy is Node3D:
		var at := (enemy as Node3D).global_position + Vector3(0, 0.35, 0)
		burst_at(at, Color(0.95, 0.55, 0.25), 1.15)
		ring_at((enemy as Node3D).global_position, Color(1.0, 0.62, 0.35), 1.85)


func _on_enemy_damaged(enemy: Node, result: DamageResult) -> void:
	if not is_instance_valid(enemy) or not enemy is Node3D or result == null or not result.accepted:
		return
	var at := (enemy as Node3D).global_position + Vector3(0, 1.1, 0)
	if result.was_critical:
		# Gold crit: larger, brighter, with shock ring for readability.
		burst_at(at, Color(1.0, 0.88, 0.22), 0.82)
		ring_at((enemy as Node3D).global_position, Color(1.0, 0.92, 0.45), 1.05)
	else:
		burst_at(at, Color(0.9, 0.72, 0.55), 0.42)



func _on_wave_started(wave_number: int, _planned: int) -> void:
	ring_at(Vector3.ZERO, Color(0.85, 0.45, 0.22), 6.5)
	burst_at(Vector3(0, 0.2, 0), Color(1.0, 0.65, 0.3), 1.2)


func _on_wave_completed(_wave_number: int, _bonus: int) -> void:
	ring_at(Vector3.ZERO, Color(1.0, 0.88, 0.38), 8.0)
	burst_at(Vector3(0, 0.4, 0), Color(1.0, 0.92, 0.5), 1.45)


func _on_boss_spawned(boss: Node, _boss_id: StringName) -> void:
	var at := Vector3.ZERO
	if is_instance_valid(boss) and boss is Node3D:
		at = (boss as Node3D).global_position
	ring_at(at, Color(0.95, 0.18, 0.12), 5.2)
	burst_at(at + Vector3(0, 0.6, 0), Color(1.0, 0.32, 0.18), 2.0)


func _on_boss_slain(_boss_id: StringName) -> void:
	ring_at(Vector3.ZERO, Color(1.0, 0.85, 0.32), 9.5)
	burst_at(Vector3.ZERO + Vector3(0, 0.5, 0), Color(1.0, 0.88, 0.4), 2.2)


func _on_pickup_collected(pickup_id: StringName, _amount: int, collector: Node) -> void:
	var at := Vector3.ZERO
	if is_instance_valid(collector) and collector is Node3D:
		at = (collector as Node3D).global_position
	ring_at(at, Color(1.0, 0.88, 0.38), 1.0)
	burst_at(at + Vector3(0, 0.6, 0), Color(1.0, 0.92, 0.55), 0.55)


func _on_pickup_spawned(pickup: Node, _pickup_id: StringName) -> void:
	if not is_instance_valid(pickup) or not pickup is Node3D:
		return
	ring_at((pickup as Node3D).global_position, Color(0.45, 0.85, 1.0), 1.15)


func _on_status_applied(target: Node, effect_id: StringName, _stacks: int) -> void:
	if not is_instance_valid(target) or not target is Node3D:
		return
	var color: Color = STATUS_COLORS.get(effect_id, Color(0.7, 0.7, 0.7))
	var at := (target as Node3D).global_position + Vector3(0, 1.6, 0)
	ring_at(at, color, 0.85)
	if effect_id == &"burn" or effect_id == &"shock":
		burst_at(at, color, 0.5)


func _on_projectile_fired(owner: Node, _weapon_id: StringName) -> void:
	if not is_instance_valid(owner) or not owner is Node3D:
		return
	var at := (owner as Node3D).global_position + Vector3(0, 1.0, 0)
	burst_at(at, Color(1.0, 0.82, 0.45), 0.48)


func _on_skill_cast(skill_id: StringName, caster: Node) -> void:
	var at := Vector3.ZERO
	if is_instance_valid(caster) and caster is Node3D:
		at = (caster as Node3D).global_position
	var color: Color = SKILL_COLORS.get(skill_id, Color(0.8, 0.6, 0.2))
	var radius := 2.8
	if skill_id == &"frost_nova":
		radius = 4.2
	elif skill_id == &"seismic_slam":
		radius = 3.6
	ring_at(at, color, radius)
	burst_at(at + Vector3(0, 0.3, 0), color, 1.35)


func _on_player_leveled_up(_new_level: int, _xp: int) -> void:
	# Celebratory burst — called from player; find player via group if available.
	var at := Vector3.ZERO
	var players := get_tree().get_nodes_in_group(&"player") if get_tree() != null else []
	if players.size() > 0 and is_instance_valid(players[0]) and players[0] is Node3D:
		at = (players[0] as Node3D).global_position
	ring_at(at, Color(1.0, 0.88, 0.32), 2.2)
	burst_at(at + Vector3(0, 1.2, 0), Color(1.0, 0.95, 0.55), 1.6)
	burst_at(at + Vector3(0, 0.4, 0), Color(0.45, 0.85, 1.0), 1.1)


func _on_weapon_equipped(_weapon_id: StringName, _slot: int) -> void:
	# Brief equip flash at player.
	var at := Vector3.ZERO
	var players := get_tree().get_nodes_in_group(&"player") if get_tree() != null else []
	if players.size() > 0 and is_instance_valid(players[0]) and players[0] is Node3D:
		at = (players[0] as Node3D).global_position + Vector3(0, 1.0, 0)
	burst_at(at, Color(0.72, 0.82, 1.0), 0.62)


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
	mat.spread = 68.0
	mat.gravity = Vector3(0, -4.2, 0)
	mat.initial_velocity_min = 1.2
	mat.initial_velocity_max = 4.2
	mat.scale_min = 0.14
	mat.scale_max = 0.38
	mat.color = Color(1.0, 0.85, 0.55)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.angular_velocity_min = -120.0
	mat.angular_velocity_max = 120.0
	var p := GPUParticles3D.new()
	p.process_material = mat
	p.amount = 22
	p.lifetime = 0.68
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
	mat.albedo_color = Color(1, 1, 1, 0.52)
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = 0.35
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
	return ResourceLoader.exists(path)

## Hardened: clamp effect scale.
func _validated_effect_scale(s: float) -> float:
	if not is_finite(s) or s <= 0.0:
		return 1.0
	return clampf(s, 0.1, 10.0)

