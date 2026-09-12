class_name Projectile
extends Area3D

## Pooled projectile for ranged weapons (player + enemies share this type).
## Flies straight with an optional gravity arc, expires on lifetime / range /
## world impact, and damages the first valid target(s) on each side up to its
## pierce count. Friendly fire is resolved via `team`: &"player" projectiles
## hit enemies, &"enemy" projectiles hit the player. Returned to its pool via
## `release_requested` instead of freeing, so volleys never allocate.
##
## SWEPT COLLISION (`swept_collision`, on by default): the node moves itself by
## assigning global_position, so it is NOT the physics server integrating it and
## gets no continuous collision detection. At the fastest authored shot (sunbow,
## projectile_speed = 24) that is 0.40 m of travel per 60 Hz tick against a
## 0.25 m detection sphere — a thin barrier, or a target that dodges across the
## line between two ticks, can be skipped outright. So each step first asks
## cast_motion() how far it may safely go and only then advances, which makes the
## whole segment a solid test instead of two point samples. The Area3D overlap
## signals stay connected as the fallback path (they still cover a shot spawned
## already inside something, which cast_motion ignores by design), and every
## contact funnels through the same _resolve_hit(), so the two paths can never
## disagree about what a hit means. Disable `swept_collision` only to reproduce
## the pre-sweep behaviour in a test.

signal release_requested(projectile: Projectile)
signal impacted(projectile: Projectile, target: Node)

const TEAM_PLAYER := &"player"
const TEAM_ENEMY := &"enemy"

## Contacts resolved per physics step before the step is abandoned and the rest of
## the travel is applied in one go. Piercing shots through a crowd are bounded by
## `pierce`, so this only has to cover same-team bodies standing in the way.
const MAX_SWEEP_SEGMENTS := 4
## A contact closer than this to the current position is "we are already touching
## it"; advancing past it prevents a zero-fraction loop.
const SWEEP_MIN_ADVANCE := 0.0005

## Radius of the sphere used for the swept test. Kept equal to the collision
## shape (the pool sets it from the authored SphereShape3D) so the sweep and the
## Area3D overlap agree on what counts as a hit.
@export var sweep_radius: float = 0.25
@export var swept_collision: bool = true

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
# Two shared materials for the whole game (player gold / enemy red). Built once
# (pool _ready / first tint) so a volley never allocates StandardMaterial3D.
static var _shared_player_mat: StandardMaterial3D = null
static var _shared_enemy_mat: StandardMaterial3D = null
# Pooled sweep query state (built once per pooled instance, mutated per step —
# allocating a shape + two parameter objects per shot per tick is exactly the
# churn the pool exists to avoid).
var _sweep_shape: SphereShape3D = null
var _sweep_query: PhysicsShapeQueryParameters3D = null
var _sweep_ray: PhysicsRayQueryParameters3D = null
## RIDs this flight ignores: the launcher (so a shot never collides with the body
## it spawned inside) and anything already resolved or same-team (so the sweep
## cannot stall on a body the Area3D path is allowed to pass through).
##
## Deliberately RIDs, not node refs: the server's exclusion is a RID set-membership
## test, so a collider that dies mid-flight leaves a stale number that simply never
## matches again — no freed-object dereference anywhere on this path. The list is
## rebuilt empty at every launch, so even a recycled RID can only shadow a body for
## the remainder of one shot (<= `lifetime`, and `pierce` keeps the count tiny).
var _ignore_rids: Array = []


func _ready() -> void:
	_visual = get_node_or_null("Visual") as Node3D
	# No "Trail" lookup on purpose: the pool builds shots with only a Visual
	# node, no scene or code ever names a Trail child, and cosmetic trails
	# attach to the player. The scene-path contract gate pins that absence.
	monitoring = true
	monitorable = false
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


## Configure + launch. Safe to call on a pooled (already in tree) instance.
func launch(config: Dictionary) -> void:
	team = config.get("team", TEAM_PLAYER)
	var raw_dir: Vector3 = config.get("direction", Vector3.FORWARD) as Vector3
	if raw_dir.length_squared() < 0.0001 or not is_finite(raw_dir.x) or not is_finite(raw_dir.y) or not is_finite(raw_dir.z):
		raw_dir = Vector3.FORWARD
	direction = raw_dir.normalized()
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
	status_effects.clear()
	for tag in config.get("status_effects", []):
		status_effects.append(StringName(String(tag)))
	_ensure_sweep_state()
	_travelled = 0.0
	_age = 0.0
	_hit_bodies.clear()
	_ignore_rids.clear()
	_ignore_body(source)
	global_position = config.get("origin", global_position)
	# Pool → live is a teleport (the idle slot parks at y = -100). Without this,
	# the first rendered frame would glide up from the parking spot.
	reset_physics_interpolation()
	_active = true
	visible = true
	set_physics_process(true)
	_face_travel()
	_apply_team_tint()


func _physics_process(delta: float) -> void:
	if not is_inside_tree() or not is_instance_valid(self):
		return
	if delta <= 0.0 or not is_finite(delta):
		return
	if not _active:
		return
	if gravity_arc > 0.0:
		direction = (direction + Vector3.DOWN * gravity_arc * delta).normalized()
	var step := speed * delta
	_travelled += step
	_age += delta
	_advance(step)
	_face_travel()
	if _travelled >= max_distance or _age >= lifetime:
		_expire()


## One step of travel, resolved against everything the shot may touch. Swept when
## `swept_collision` and a space is available (headless fixtures have neither, and
## must keep the plain-integration behaviour), otherwise exactly the old
## position += direction * step.
func _advance(step: float) -> void:
	# Any missing ingredient (no tree, no space, launched by a caller that skipped
	# launch(), opt-out) takes the plain-integration path: the shot still flies and
	# the Area3D overlap still resolves it, exactly as before the sweep existed.
	var space := _direct_space()
	if space == null or not swept_collision or _sweep_query == null:
		global_position += direction * step
		return
	var consumed := 0.0
	var guard := 0
	while _active and guard < MAX_SWEEP_SEGMENTS and step - consumed > SWEEP_MIN_ADVANCE:
		guard += 1
		var from := global_position
		var remaining := step - consumed
		var hit := _sweep_first(space, from, from + direction * remaining)
		if hit.is_empty():
			global_position = from + direction * remaining
			return
		var frac := clampf(float(hit.get("fraction", 1.0)), 0.0, 1.0)
		global_position = from + direction * (remaining * frac)
		consumed += remaining * frac
		var body := hit.get("collider") as Node
		_resolve_hit(body)
		if not _active:
			return
		# Still flying (pierce budget left, or a body this shot may pass through):
		# stop asking about it for the rest of the flight.
		_ignore_body(body)
	if _active and step - consumed > SWEEP_MIN_ADVANCE:
		# Segment budget spent inside a dense crowd: finish the step so the shot
		# can never stall mid-flight, and let the Area3D overlap pick up the rest.
		global_position += direction * (step - consumed)


## Build (once) the sphere + query objects this projectile sweeps with.
func _ensure_sweep_state() -> void:
	if _sweep_shape == null:
		_sweep_shape = SphereShape3D.new()
		_sweep_shape.radius = maxf(sweep_radius, 0.02)
	elif not is_equal_approx(_sweep_shape.radius, maxf(sweep_radius, 0.02)):
		_sweep_shape.radius = maxf(sweep_radius, 0.02)
	if _sweep_query == null:
		_sweep_query = PhysicsShapeQueryParameters3D.new()
		_sweep_query.shape = _sweep_shape
		# Bodies only: other projectiles are Area3D siblings, and an arc of
		# shots must not shoot each other down.
		_sweep_query.collide_with_bodies = true
		_sweep_query.collide_with_areas = false
	if _sweep_ray == null:
		_sweep_ray = PhysicsRayQueryParameters3D.new()
		_sweep_ray.collide_with_bodies = true
		_sweep_ray.collide_with_areas = false
		# The contact is by definition touching the probe origin.
		_sweep_ray.hit_from_inside = true


func _direct_space() -> PhysicsDirectSpaceState3D:
	if not is_inside_tree():
		return null
	var world := get_world_3d()
	if world == null:
		return null
	return world.direct_space_state


## Swept test for one segment. Returns {} when the segment is clear or the
## collider cannot be identified (in which case the caller flies the full
## distance and changes nothing about the pre-sweep outcome), else
## {"fraction": safe fraction of the segment, "collider": Node}.
func _sweep_first(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	_sweep_query.transform = Transform3D(Basis(), from)
	_sweep_query.motion = to - from
	_sweep_query.collision_mask = CollisionLayers.PROJECTILE_HIT_MASK
	_sweep_query.exclude = _ignore_rids
	var motion := space.cast_motion(_sweep_query)
	if motion.size() < 2:
		return {}
	var safe := clampf(float(motion[0]), 0.0, 1.0)
	if safe >= 1.0 - 0.0001:
		return {}
	# cast_motion gives the fraction but not WHO was hit; a short ray from the safe
	# stop point identifies it. The probe reaches a little past the contact so a
	# grazing sphere still reports the surface.
	var axis := (to - from).normalized()
	_sweep_ray.from = from + (to - from) * safe
	_sweep_ray.to = _sweep_ray.from + axis * maxf(sweep_radius * 2.0, 0.1)
	_sweep_ray.collision_mask = CollisionLayers.PROJECTILE_HIT_MASK
	_sweep_ray.exclude = _ignore_rids
	var hit := space.intersect_ray(_sweep_ray)
	if hit.is_empty():
		return {}
	var body: Node = hit.get("collider")
	if body == null or body == self or not is_instance_valid(body):
		return {}
	return {"fraction": safe, "collider": body}


## Forget a body for the remainder of this flight. Only CollisionObject3D-derived
## nodes have a physics RID to ignore, which is exactly the set the sweep can hit.
func _ignore_body(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	if not (body is CollisionObject3D):
		return
	var collider: CollisionObject3D = body
	_ignore_rids.append(collider.get_rid())


func _face_travel() -> void:
	if _visual == null or direction.length_squared() <= 0.0001:
		return
	var up := Vector3.UP
	if absf(direction.normalized().dot(up)) > 0.99:
		up = Vector3.FORWARD
	_visual.look_at(_visual.global_position + direction, up)


## Pre-build the two team materials. Safe to call repeatedly; the pool calls
## this at _ready so the first volley is assignment-only.
static func ensure_shared_tints() -> void:
	if _shared_player_mat == null:
		_shared_player_mat = _make_team_mat(Color(0.15, 0.8, 1.0))
	if _shared_enemy_mat == null:
		_shared_enemy_mat = _make_team_mat(Color(1.0, 0.2, 0.25))


static func _make_team_mat(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 1.5
	return mat


func _apply_team_tint() -> void:
	# Assignment only: gold = player, red = enemy. Construction lives in
	# ensure_shared_tints() so launch never allocates a StandardMaterial3D.
	var mesh := get_node_or_null("Visual/Mesh") as MeshInstance3D
	if mesh == null:
		return
	ensure_shared_tints()
	mesh.material_override = _shared_player_mat if team == TEAM_PLAYER else _shared_enemy_mat


func _on_body_entered(body: Node) -> void:
	_resolve_hit(body)


## THE single contact resolver for both paths (swept cast + Area3D overlap), so a
## hit cannot mean one thing to the sweep and another to the overlap signals.
## A released projectile stops simulating, which is also how the sweep loop learns
## the shot was consumed.
func _resolve_hit(body: Node) -> void:
	if not _active or body == null:
		return
	if not is_instance_valid(body) or body == source:
		return
	if body in _hit_bodies:
		return
	if not _is_enemy_of(body):
		# World geometry (or same-team bodies): fizzle without damage.
		if _is_world(body):
			_release_with_impact(null)
		return
	_hit_bodies.append(body)
	var payload := DamagePayload.new()
	payload.amount = damage
	payload.source = source if is_instance_valid(source) else null
	payload.source_id = source_id
	payload.damage_type = damage_type
	payload.can_crit = false
	payload.was_critical = was_critical
	payload.critical_multiplier = critical_multiplier
	payload.hit_position = global_position
	payload.knockback = direction * knockback_strength
	payload.status_effects = status_effects.duplicate()
	var damageable := body as Damageable
	if damageable != null and payload.is_valid():
		damageable.apply_damage(payload)
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
	_release_once()


func _release_with_impact(_target: Node) -> void:
	_release_once()


func _release_once() -> void:
	if not _active:
		return
	_active = false
	release_requested.emit(self)


## Pool reset: park offscreen, hide, stop simulating. Keeps configuration for
## introspection but marks inactive so stray physics callbacks are ignored.
func pool_reset() -> void:
	_active = false
	visible = false
	set_physics_process(false)
	_hit_bodies.clear()
	_ignore_rids.clear()
	_travelled = 0.0
	_age = 0.0
	global_position = Vector3(0, -100, 0)
	# Parking spot is a teleport; never interpolate the visual across it.
	reset_physics_interpolation()


func is_active() -> bool:
	return _active


func get_debug_snapshot() -> Dictionary:
	return {
		"team": String(team),
		"active": _active,
		"damage": damage,
		"travelled": _travelled,
		"pierce": pierce_remaining,
		"swept": swept_collision,
		"sweep_radius": sweep_radius,
	}
