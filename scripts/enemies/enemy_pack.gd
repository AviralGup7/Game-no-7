class_name EnemyPack
extends RefCounted

## Pack-coordination module, extracted from EnemyBase (composition pattern:
## EnemyLocomotion / EnemyNavigator / EnemyStriker). One module owns the
## "the pack around me" side of the brain:
##
##   * HEARING — an ally taking a hit nearby is a stimulus for every enemy in
##     alert_radius (routed into EnemyPerception.note_noise, so it wakes the
##     unaware and shortens the reaction beat of the suspicious);
##   * GRIEF   — two or more allies killed inside FEAR_WINDOW make a wounded,
##     CAUTIOUS individual back off briefly (readable "rallying");
##   * PLAYER NOISE — projectiles / skills cast by the target are heard;
##   * SEPARATION — soft steering push away from nearby enemies so packs fan
##     out instead of clipping through each other (objects stay hard physics;
##     peers are steering — the swarm-standard split).
##
## Signal wiring is injected (connect_signals / disconnect_signals) so the
## module stays tree-free and headless-testable; EnemyBase owns the bus
## lifetime and the fear/separation call sites.

## Radius (world units) in which an ally's death registers as grief.
const FEAR_RADIUS := 12.0
## Rolling window (physics seconds) the grief kills are counted in.
const FEAR_WINDOW := 4.0
## Kills inside the window needed before a qualifying enemy retreats.
const FEAR_KILLS := 2
## Only below this health fraction does grief make an enemy back off.
const FEAR_HP_TRIGGER := 0.55
## How long the grief retreat lasts once triggered.
const FEAR_DURATION := 0.9

## Separation peers only (CollisionLayers.SEPARATION_QUERY_MASK, pinned to the
## enemy_base.tscn layer by tests/python/test_regress_collision_contract.py):
## the query must never react to the player or the arena, or steering would fight
## the hard collision those bodies already resolve. Authoring the value here
## rather than as `4` is the point — this line and the scene must agree.
## Separation steering (soft): radius, query period, blend weight.
const SEP_RADIUS := 1.0
const SEP_PERIOD := 0.12
const SEP_WEIGHT := 0.6

var _host: EnemyBase = null
var _bus: Node = null

var _fear_times: Array[float] = []
var _fear_left := 0.0

var _sep_timer := 0.0
var _sep_push := Vector3.ZERO
var _sep_shape := SphereShape3D.new()
## Reused across queries (no per-query allocation): the server reads the
## parameters at intersect_shape() time, so mutating transform per call is
## safe and avoids GC churn for 12-40 concurrent enemies.
var _sep_query := PhysicsShapeQueryParameters3D.new()


func bind(host: EnemyBase) -> void:
	_host = host
	_sep_shape.radius = SEP_RADIUS
	_sep_query.shape = _sep_shape
	_sep_query.collide_with_bodies = true
	_sep_query.collision_mask = CollisionLayers.SEPARATION_QUERY_MASK


## Clear transient pack state (spawn / re-initialize).
func reset() -> void:
	_fear_times.clear()
	_fear_left = 0.0
	_sep_push = Vector3.ZERO
	_sep_timer = 0.0


## Wire the EventBus signals (idempotent). Called by EnemyBase once the bus
## resolves; a bare headless harness never has one and stays silent.
func connect_signals(bus: Node) -> void:
	if _bus != null or bus == null:
		return
	if bus.has_signal("enemy_damaged") and not bus.enemy_damaged.is_connected(on_ally_damaged):
		bus.enemy_damaged.connect(on_ally_damaged)
	if bus.has_signal("enemy_killed") and not bus.enemy_killed.is_connected(on_ally_killed):
		bus.enemy_killed.connect(on_ally_killed)
	if bus.has_signal("projectile_fired") and not bus.projectile_fired.is_connected(on_projectile_fired):
		bus.projectile_fired.connect(on_projectile_fired)
	if bus.has_signal("skill_cast") and not bus.skill_cast.is_connected(on_skill_cast):
		bus.skill_cast.connect(on_skill_cast)
	_bus = bus


## Unwire (EnemyBase._exit_tree). Never throws if the bus vanished first.
func disconnect_signals() -> void:
	if _bus == null or not is_instance_valid(_bus):
		_bus = null
		return
	var handlers := {
		"enemy_damaged": on_ally_damaged,
		"enemy_killed": on_ally_killed,
		"projectile_fired": on_projectile_fired,
		"skill_cast": on_skill_cast,
	}
	for sig_name in handlers:
		if _bus.has_signal(sig_name):
			var cb: Callable = handlers[sig_name]
			if _bus.is_connected(sig_name, cb):
				_bus.disconnect(sig_name, cb)
	_bus = null


## ---------- Bus handlers ----------

## An ally took a hit nearby: this enemy HEARS it — a stimulus, not an order.
func on_ally_damaged(enemy: Node, _result: DamageResult) -> void:
	if _host == null or enemy == null or not is_instance_valid(enemy) or enemy == _host:
		return
	var other := enemy as Node3D
	if other == null:
		return
	var cfg := _host.get_config()
	var radius := cfg.alert_radius if cfg != null else 10.0
	if _host.global_position.distance_to(other.global_position) > radius:
		return
	var perception := _host.get_perception()
	if perception != null:
		perception.note_noise(other.global_position, 0.7, _host.global_position)


## An ally died nearby: grief. Two or more inside the window make a cautious,
## wounded enemy back off for FEAR_DURATION before re-committing.
func on_ally_killed(enemy: Node, _archetype: StringName, _score: int, _currency: int) -> void:
	if _host == null or enemy == null or not is_instance_valid(enemy) or enemy == _host:
		return
	var other := enemy as Node3D
	if other == null:
		return
	if _host.global_position.distance_to(other.global_position) > FEAR_RADIUS:
		return
	_fear_times.append(_host.get_run_time())
	_prune_fear_times()
	if _fear_times.size() >= FEAR_KILLS and _host.get_health_fraction() < FEAR_HP_TRIGGER:
		var caution := 0.5
		var personality := _host.get_personality()
		if personality != null:
			caution = personality.caution
		if caution > 0.5:
			_fear_left = maxf(_fear_left, FEAR_DURATION)


## Player projectiles are noise (intensity below melee skills on purpose:
## a stray volley is a hint, a dodge is a shout).
func on_projectile_fired(owner: Node, _weapon_id: StringName) -> void:
	_player_noise(owner, 0.45)


func on_skill_cast(_skill_id: StringName, caster: Node) -> void:
	_player_noise(caster, 0.8)


func _player_noise(source: Node, intensity: float) -> void:
	if _host == null:
		return
	var target := _host.get_move_target()
	if target == null or source != target:
		return
	var node := source as Node3D
	if node == null:
		return
	var perception := _host.get_perception()
	if perception != null:
		perception.note_noise(node.global_position, intensity, _host.global_position)


## ---------- Per-frame pulls (called by EnemyBase) ----------

## Decay the grief timer and prune the kill window.
func update(delta: float) -> void:
	if _fear_left > 0.0:
		_fear_left = maxf(_fear_left - delta, 0.0)
	_prune_fear_times()


func _prune_fear_times() -> void:
	if _host == null:
		return
	var now := _host.get_run_time()
	while not _fear_times.is_empty() and now - _fear_times[0] > FEAR_WINDOW:
		_fear_times.pop_front()


## True while a griefed (cautious, wounded) enemy backs off — the chase state
## honors it by retreating instead of pursuing.
func is_retreating() -> bool:
	return _fear_left > 0.0


## Blend the soft separation push into the host's movement intent (never
## stronger than the intent itself: separation sidesteps, it does not flee).
func apply_separation(delta: float) -> void:
	if _host == null or _host.desired_speed <= 0.0:
		_sep_push = Vector3.ZERO
		return
	_sep_timer -= delta
	if _sep_timer <= 0.0:
		_sep_timer = SEP_PERIOD
		_sep_push = _query_separation()
	if _sep_push == Vector3.ZERO:
		return
	var blended := _host.desired_dir + _sep_push * SEP_WEIGHT
	if blended.length_squared() > 0.0001:
		_host.desired_dir = blended.normalized()


func _query_separation() -> Vector3:
	if _host == null or not _host.is_inside_tree():
		return Vector3.ZERO
	var world := _host.get_world_3d()
	if world == null:
		return Vector3.ZERO
	_sep_query.transform = Transform3D(Basis(), _host.global_position)
	# intersect_shape lives on the physics direct-space state, not World3D.
	# Headless tests have no physics space; guard so separation is skipped.
	var space_state := world.direct_space_state
	if space_state == null:
		return Vector3.ZERO
	var results: Array[Dictionary] = space_state.intersect_shape(_sep_query, 8)
	var push := Vector3.ZERO
	for r in results:
		var body = r.get("collider")
		if body == null or not (body is Node3D) or body == _host:
			continue
		var away := _host.global_position - (body as Node3D).global_position
		away.y = 0.0
		var d := away.length()
		if d > 0.001 and d < SEP_RADIUS:
			push += (away / d) * clampf((SEP_RADIUS - d) / SEP_RADIUS, 0.0, 1.0)
	if push.length() > 1.0:
		push = push.normalized()
	return push
