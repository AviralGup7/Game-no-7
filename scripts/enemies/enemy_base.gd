extends CharacterBody3D
class_name EnemyBase

## Reusable enemy base. Owns lifecycle, damage intake, idempotent death + exactly-once
## score payload (Phase 2 guarantees preserved), and — since Phase 3 — AI behaviour:
## a state machine (Idle/Chase/Attack/Hurt/Dead), navigation-aware steering, gravity,
## resistance-aware knockback, arena-bound clamping and a controlled melee attack that
## damages the player through the existing HealthComponent/apply_damage interface.

signal initialized(archetype_id: StringName)
signal state_changed(previous_state: StringName, current_state: StringName)
signal damaged(result: DamageResult)
signal died()
signal attack_started()
signal attack_hit(target: Node, result: DamageResult)
signal despawn_requested(enemy: Node)

const TARGET_GROUP := "enemies"
const GRAVITY := 18.0
const KNOCKBACK_DECAY := 18.0
const STUCK_NUDGE_DIST := 0.05

var _archetype_id: StringName = &"uninitialized"
var _config: EnemyConfig = null
var _alive := false
var _death_handled := false
var _score_value: int = 0
var _currency_value: int = 0
var _run_seed: int = 0

var _health: Node = null
var _feedback: Node = null
var _audio: Node = null
var _machine: EnemyStateMachine = null
var _nav_agent: NavigationAgent3D = null
var _target: Node3D = null

## Movement intent produced by the current state.
var desired_dir := Vector3.ZERO
var desired_speed := 0.0

var _knockback := Vector3.ZERO
var _nav_recompute := 0.0
var _stuck_time := 0.0
var _last_position := Vector3.ZERO
var _bounds_half := -1.0    # -1 disables arena clamp (default); set by the spawn manager
var _ai_enabled := true

## Per-run difficulty scaling applied at spawn without mutating the shared config.
var _hp_scale := 1.0
var _damage_scale := 1.0
var _speed_scale := 1.0


func _ready() -> void:
	add_to_group(TARGET_GROUP)
	_health = get_node_or_null("HealthComponent")
	_feedback = get_node_or_null("EnemyFeedback")
	_audio = get_node_or_null("EnemyAudio")
	_machine = get_node_or_null("EnemyStateMachine") as EnemyStateMachine
	_nav_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if _health != null:
		_health.health_changed.connect(func(_c: float, _m: float) -> void: pass)
		_health.damaged.connect(_on_damaged)
		_health.died.connect(_on_died)


func set_ai_enabled(enabled: bool) -> void:
	_ai_enabled = enabled
	if not enabled:
		desired_dir = Vector3.ZERO
		desired_speed = 0.0
		velocity.x = 0.0
		velocity.z = 0.0


func _physics_process(delta: float) -> void:
	if _config == null or not _alive or not _ai_enabled:
		return
	if _machine != null:
		_machine.physics_update(delta)
	_apply_gravity(delta)
	_decay_knockback(delta)
	_update_motion(delta)
	_detect_stall(delta)


## ---------- Stable command interface (Phase 2 preserved) ----------

func initialize(config: EnemyConfig, target: Node3D, run_seed: int = 0) -> void:
	if config == null:
		push_warning("EnemyBase.initialize received null config")
		return
	_config = config
	_archetype_id = config.archetype_id
	_score_value = config.score_value
	_currency_value = config.currency_value
	_run_seed = run_seed
	_target = target
	_alive = true
	_death_handled = false
	_knockback = Vector3.ZERO
	desired_dir = Vector3.ZERO
	desired_speed = 0.0
	_stuck_time = 0.0
	if _health != null and _health.has_method("reset"):
		_health.call("reset", config.max_health)
	if _feedback != null and _feedback.has_method("recolor"):
		_feedback.call("recolor", config.color_tint)
	_apply_visual_scale(config.visual_scale)
	if _machine != null:
		_machine.force_state(&"idle")
	if _nav_agent != null and target != null:
		_nav_agent.target_position = target.global_position
		_nav_recompute = 0.0
	initialized.emit(_archetype_id)


func apply_damage(payload: DamagePayload) -> DamageResult:
	var result := DamageResult.new()
	if _health == null or not _health.has_method("take_damage"):
		result.ignored_reason = &"no_health_component"
		return result
	if not _alive:
		result.ignored_reason = DamageResult.IGNORE_DEAD
		return result
	var taken: Variant = _health.call("take_damage", payload)
	if taken is DamageResult:
		var res := taken as DamageResult
		_on_damage_applied(res, payload)
		return res
	result.ignored_reason = &"invalid_result"
	return result


func force_state(state_id: StringName) -> void:
	if _machine != null:
		_machine.force_state(state_id)


## Regular (non-forcing) transition facade used by AI states; refused if already current.
func state_machine_change_to(state_id: StringName) -> void:
	if _machine != null:
		_machine.change_to(state_id)


func get_state() -> StringName:
	if _machine == null:
		return &""
	return _machine.get_current()


func is_alive() -> bool:
	return _alive


func get_archetype_id() -> StringName:
	return _archetype_id


func get_config() -> EnemyConfig:
	return _config


## Set arena-bound half extent; -1 disables the clamp.
func set_bounds(half: float) -> void:
	_bounds_half = half


func set_velocity_flat(flat: Vector3) -> void:
	velocity.x = flat.x
	velocity.z = flat.z


## Apply wave difficulty scaling (>=1.0). Resets health to the scaled maximum.
func apply_difficulty(hp_scale: float, damage_scale: float, speed_scale: float) -> void:
	_hp_scale = maxf(hp_scale, 1.0)
	_damage_scale = maxf(damage_scale, 1.0)
	_speed_scale = maxf(speed_scale, 1.0)
	if _health != null and _health.has_method("reset"):
		_health.call("reset", _scaled_max_health())
	if _feedback != null and _feedback.has_method("play_damaged"):
		pass


func _scaled_max_health() -> float:
	var cfg := _config
	var base := cfg.max_health if cfg != null else 1.0
	return base * _hp_scale


func get_effective_speed() -> float:
	var cfg := _config
	var base := cfg.move_speed if cfg != null else 2.0
	return base * _speed_scale


func get_effective_attack_damage() -> float:
	var cfg := _config
	var base := cfg.attack_damage if cfg != null else 5.0
	return base * _damage_scale


func get_move_target() -> Node3D:
	if _target == null or not is_instance_valid(_target):
		return null
	if _target.has_method("is_alive") and not bool(_target.call("is_alive")):
		return null
	return _target


func set_desired_move(dir: Vector3, speed: float) -> void:
	desired_dir = dir
	desired_speed = maxf(speed, 0.0)


func target_in_attack_range(target: Node3D) -> bool:
	if target == null:
		return false
	var cfg := _config
	var range_val := cfg.attack_range if cfg != null else 1.5
	return global_position.distance_to(target.global_position) <= range_val


func face_direction(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	var visual := get_node_or_null("VisualRoot") as Node3D
	if visual == null:
		return
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	visual.look_at(visual.global_position + flat, Vector3.UP)


func face_target(target: Node3D) -> void:
	if target == null:
		return
	face_direction(target.global_position - global_position)


## Navigation-aware steering: prefers the NavigationAgent3D next-path position when the
## agent has a usable nav map; otherwise falls back to the caller's direct direction.
func get_navigation_direction(fallback: Vector3) -> Vector3:
	var target := get_move_target()
	if _nav_agent == null or target == null or not _nav_usable():
		return fallback
	_nav_recompute -= _physics_interval()
	if _nav_recompute <= 0.0:
		_nav_agent.target_position = target.global_position
		_nav_recompute = _config.navigation_target_update_interval if _config != null else 0.2
	if _nav_agent.is_navigation_finished():
		return fallback
	var next := _nav_agent.get_next_path_position()
	var offset := next - global_position
	offset.y = 0.0
	if offset.length_squared() < 0.0001:
		return fallback
	return offset.normalized()


func _nav_usable() -> bool:
	if _nav_agent == null:
		return false
	var map := _nav_agent.get_navigation_map()
	if map == null or not map.is_valid():
		return false
	return NavigationServer3D.map_get_iteration_id(map) > 0


func _physics_interval() -> float:
	return 1.0 / 60.0


## Controlled melee attack against the current target. Returns true when a hit lands.
## Performs the damage exactly once per call; duplicate protection is provided by the
## state machine (windup phase) plus the alive guards here and in the target.
func perform_enemy_attack() -> bool:
	if not _alive:
		return false
	var target := get_move_target()
	if target == null:
		return false
	if not target_in_attack_range(target):
		return false
	if _wall_between(target):
		return false
	var cfg := _config
	if cfg == null:
		return false
	attack_started.emit()
	var to_t := target.global_position - global_position
	to_t.y = 0.0
	var dir := Vector3.FORWARD
	if to_t.length_squared() > 0.0001:
		dir = to_t.normalized()
	var payload := DamagePayload.new()
	payload.amount = get_effective_attack_damage()
	payload.source = self
	payload.source_id = _archetype_id
	payload.damage_type = &"physical"
	payload.knockback = dir * _enemy_knockback_strength()
	payload.hit_position = global_position
	if not target.has_method("apply_damage"):
		return false
	var result: Variant = target.call("apply_damage", payload)
	if result is DamageResult:
		var res := result as DamageResult
		attack_hit.emit(target, res)
		if _audio != null and _audio.has_method("play_attack"):
			_audio.call("play_attack")
		return res.accepted
	return false


func _enemy_knockback_strength() -> float:
	if _config == null:
		return 4.0
	# Heavier enemies push harder; scaled by their effective damage for readability.
	return clampf(3.0 + get_effective_attack_damage() * 0.25, 2.0, 16.0)


func _wall_between(target: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var from := global_position + Vector3(0, 0.8, 0)
	var to := target.global_position + Vector3(0, 0.8, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 0b0001)
	var hit := space.intersect_ray(query)
	return not hit.is_empty()


## ---------- Movement helpers ----------

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta


func _decay_knockback(delta: float) -> void:
	if _knockback.length_squared() <= 0.0:
		return
	var decay := KNOCKBACK_DECAY * delta
	_knockback = _knockback.move_toward(Vector3.ZERO, decay)


func _update_motion(delta: float) -> void:
	var cfg := _config
	var accel := cfg.acceleration if cfg != null else 8.0
	var wish_x := desired_dir.x * desired_speed + _knockback.x
	var wish_z := desired_dir.z * desired_speed + _knockback.z
	velocity.x = move_toward(velocity.x, wish_x, accel * delta)
	velocity.z = move_toward(velocity.z, wish_z, accel * delta)
	move_and_slide()
	_clamp_to_bounds()


func _clamp_to_bounds() -> void:
	if _bounds_half < 0.0:
		return
	var cfg := _config
	var margin := cfg.bounds_radius if cfg != null else 0.5
	var limit := _bounds_half - margin
	var p := global_position
	var changed := false
	if p.x < -limit:
		p.x = -limit
		changed = true
	elif p.x > limit:
		p.x = limit
		changed = true
	if p.z < -limit:
		p.z = -limit
		changed = true
	elif p.z > limit:
		p.z = limit
		changed = true
	if changed:
		global_position = p
		velocity.x = 0.0
		velocity.z = 0.0


func _detect_stall(delta: float) -> void:
	if desired_speed <= 0.0:
		_stuck_time = 0.0
		_last_position = global_position
		return
	var moved := global_position.distance_to(_last_position)
	_last_position = global_position
	if moved < STUCK_NUDGE_DIST * delta * 60.0:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time >= 0.5:
		_stuck_time = 0.0
		_apply_stuck_recovery()


func _apply_stuck_recovery() -> void:
	# Nudge perpendicular to the current intent to slide off obstacles/walls.
	var dir := desired_dir
	var perp := Vector3(-dir.z, 0.0, dir.x)
	var strength := maxf(desired_speed * 0.6, 1.0)
	_knockback += perp * strength


func _apply_visual_scale(scale_factor: float) -> void:
	var visual := get_node_or_null("VisualRoot") as Node3D
	if visual != null and scale_factor > 0.0:
		visual.scale = Vector3.ONE * scale_factor


func note_hurt_started() -> void:
	pass


## ---------- Damage / death (Phase 2 exactly-once preserved) ----------

func _on_damage_applied(result: DamageResult, payload: DamagePayload) -> void:
	if not result.accepted:
		return
	var cfg := _config
	var resistance := cfg.knockback_resistance if cfg != null else 0.0
	var resisted := payload.knockback * (1.0 - clampf(resistance, 0.0, 1.0))
	_knockback += Vector3(resisted.x, 0.0, resisted.z)


func _on_damaged(result: DamageResult) -> void:
	damaged.emit(result)
	# EventBus contract: exactly one enemy_damaged per ACCEPTED damage event. HealthComponent
	# emits its local `damaged` signal only on the accepted path, so this is exactly-once.
	EventBus.enemy_damaged.emit(self, result)
	if _feedback != null and _feedback.has_method("play_damaged"):
		_feedback.call("play_damaged")
	if _audio != null and _audio.has_method("play_hit"):
		_audio.call("play_hit")
	if _machine != null:
		_machine.force_state(&"hurt")


func _on_died() -> void:
	if _death_handled:
		return
	_death_handled = true
	_alive = false
	desired_dir = Vector3.ZERO
	desired_speed = 0.0
	if _machine != null:
		_machine.force_state(&"dead")
	died.emit()
	EventBus.report_info("Enemy %s died" % String(_archetype_id))
	# Exactly-once score payload.
	EventBus.enemy_killed.emit(self, _archetype_id, _score_value, _currency_value)
	despawn_requested.emit(self)
	if _feedback != null and _feedback.has_method("play_died"):
		_feedback.call("play_died")
	if _audio != null and _audio.has_method("play_death"):
		_audio.call("play_death")
	_fade_and_free()


func _fade_and_free() -> void:
	if not is_inside_tree():
		queue_free()
		return
	var tween := create_tween()
	tween.tween_interval(0.5)
	tween.tween_callback(queue_free)


func get_debug_snapshot() -> Dictionary:
	var hp: Dictionary = {}
	if _health != null and _health.has_method("get_debug_snapshot"):
		hp = _health.call("get_debug_snapshot")
	return {
		"archetype": String(_archetype_id),
		"state": String(get_state()),
		"alive": _alive,
		"death_handled": _death_handled,
		"position": global_position,
		"health": hp,
		"desired_dir": desired_dir,
		"desired_speed": desired_speed,
	}
