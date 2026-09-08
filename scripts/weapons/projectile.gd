class_name Projectile
extends Area3D

## Pooled projectile for ranged weapons (player + enemies share this type).
## Flies straight with an optional gravity arc, expires on lifetime / range /
## world impact, and damages the first valid target(s) on each side up to its
## pierce count. Friendly fire is resolved via `team`: &"player" projectiles
## hit enemies, &"enemy" projectiles hit the player. Returned to its pool via
## `release_requested` instead of freeing, so volleys never allocate.

signal release_requested(projectile: Projectile)
signal impacted(projectile: Projectile, target: Node)

const TEAM_PLAYER := &"player"
const TEAM_ENEMY := &"enemy"

var team: StringName = TEAM_PLAYER
var direction: Vector3 = Vector3.FORWARD
var speed: float = 18.0
var gravity_arc: float = 0.0
var damage: float = 10.0
var knockback_strength: float = 4.0
var pierce_remaining: int = 0
var max_distance: float = 30.0
var lifetime: float = 1.6
var source: Node = null
var source_id: StringName = &"projectile"
var damage_type: StringName = &"physical"
var was_critical: bool = false
var critical_multiplier: float = 1.0
var status_effects: Array[StringName] = []

var _travelled: float = 0.0
var _age: float = 0.0
var _active := false
var _hit_bodies: Array = []
var _visual: Node3D = null
var _trail: Node = null


func _ready() -> void:
	_visual = get_node_or_null("Visual") as Node3D
	_trail = get_node_or_null("Trail")
	monitoring = true
	monitorable = false
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


## Configure + launch. Safe to call on a pooled (already in tree) instance.
func launch(config: Dictionary) -> void:
	team = config.get("team", TEAM_PLAYER)
	direction = (config.get("direction", Vector3.FORWARD) as Vector3).normalized()
	speed = maxf(float(config.get("speed", 18.0)), 0.1)
	gravity_arc = maxf(float(config.get("gravity", 0.0)), 0.0)
	damage = maxf(float(config.get("damage", 10.0)), 0.0)
	knockback_strength = maxf(float(config.get("knockback", 4.0)), 0.0)
	pierce_remaining = maxi(int(config.get("pierce", 0)), 0)
	max_distance = maxf(float(config.get("max_distance", 30.0)), 0.5)
	lifetime = maxf(float(config.get("lifetime", 1.6)), 0.05)
	source = config.get("source", null)
	source_id = config.get("source_id", &"projectile")
	damage_type = config.get("damage_type", &"physical")
	was_critical = bool(config.get("was_critical", false))
	critical_multiplier = maxf(float(config.get("critical_multiplier", 1.0)), 1.0)
	status_effects = []
	for tag in config.get("status_effects", []):
		status_effects.append(StringName(String(tag)))
	global_position = config.get("origin", global_position)
	_travelled = 0.0
	_age = 0.0
	_hit_bodies.clear()
	_active = true
	visible = true
	set_physics_process(true)
	_face_travel()
	_apply_team_tint()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if gravity_arc > 0.0:
		direction = (direction + Vector3.DOWN * gravity_arc * delta).normalized()
	var step := speed * delta
	global_position += direction * step
	_travelled += step
	_age += delta
	_face_travel()
	if _travelled >= max_distance or _age >= lifetime:
		_expire()


func _face_travel() -> void:
	if _visual != null and direction.length_squared() > 0.0001:
		_visual.look_at(_visual.global_position + direction, Vector3.UP)


func _apply_team_tint() -> void:
	# Pooled visuals recolor cheaply via a named method when present; otherwise
	# fall back to a team-colored material override (gold = player, red = enemy)
	# so pooled shots stay readable no matter which scene built them.
	var mesh := get_node_or_null("Visual/Mesh") as MeshInstance3D
	if mesh == null:
		return
	if mesh.has_method("set_team_tint"):
		mesh.call("set_team_tint", team)
		return
	var tint := Color(1.0, 0.8, 0.25) if team == TEAM_PLAYER else Color(1.0, 0.2, 0.25)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 1.5
	mesh.material_override = mat


func _on_body_entered(body: Node) -> void:
	if not _active:
		return
	if body in _hit_bodies:
		return
	if body == source:
		return
	if not _is_enemy_of(body):
		# World geometry (or same-team bodies): fizzle without damage.
		if _is_world(body):
			_release_with_impact(null)
		return
	_hit_bodies.append(body)
	var payload := DamagePayload.new()
	payload.amount = damage
	payload.source = source
	payload.source_id = source_id
	payload.damage_type = damage_type
	payload.can_crit = false
	payload.was_critical = was_critical
	payload.critical_multiplier = critical_multiplier
	payload.hit_position = global_position
	payload.knockback = direction * knockback_strength
	payload.status_effects = status_effects.duplicate()
	if body.has_method("apply_damage") and payload.is_valid():
		body.call("apply_damage", payload)
	impacted.emit(self, body)
	if pierce_remaining > 0:
		pierce_remaining -= 1
	else:
		_release_with_impact(body)


func _is_enemy_of(body: Node) -> bool:
	if team == TEAM_PLAYER:
		return body.is_in_group(EnemyBase.TARGET_GROUP)
	if team == TEAM_ENEMY:
		return body.is_in_group("player")
	return false


func _is_world(body: Node) -> bool:
	return body is StaticBody3D or body.is_in_group("world_static")


func _expire() -> void:
	release_requested.emit(self)


func _release_with_impact(_target: Node) -> void:
	release_requested.emit(self)


## Pool reset: park offscreen, hide, stop simulating. Keeps configuration for
## introspection but marks inactive so stray physics callbacks are ignored.
func pool_reset() -> void:
	_active = false
	visible = false
	set_physics_process(false)
	_hit_bodies.clear()
	_travelled = 0.0
	_age = 0.0
	global_position = Vector3(0, -100, 0)


func is_active() -> bool:
	return _active


func get_debug_snapshot() -> Dictionary:
	return {
		"team": String(team),
		"active": _active,
		"damage": damage,
		"travelled": _travelled,
		"pierce": pierce_remaining,
	}
