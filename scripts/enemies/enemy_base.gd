extends CharacterBody3D
class_name EnemyBase

## Reusable enemy base. Owns lifecycle, damage intake, idempotent death + exactly-once
## score payload (Phase 2 guarantees preserved), and — since Phase 3 — AI behaviour:
## a state machine (Idle/Chase/Attack/Hurt/Dead) driving movement intent, integrated by
## EnemyLocomotion (gravity/knockback/clamp/stall), steered by EnemyNavigator (navmesh),
## and striking through EnemyStriker (guarded melee). Resistance-aware knockback and
## arena-bound clamping included; attacks damage the player through the existing
## HealthComponent/apply_damage interface.

signal initialized(archetype_id: StringName)
signal state_changed(previous_state: StringName, current_state: StringName)
signal damaged(result: DamageResult)
signal died()
signal attack_started()
signal attack_hit(target: Node, result: DamageResult)
signal despawn_requested(enemy: Node)

const TARGET_GROUP := "enemies"

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
var _target: Node3D = null
var _locomotion := EnemyLocomotion.new()
var _navigator := EnemyNavigator.new()
var _striker := EnemyStriker.new()

## Movement intent produced by the current state.
var desired_dir := Vector3.ZERO
var desired_speed := 0.0

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
	_navigator.bind(get_node_or_null("NavigationAgent3D") as NavigationAgent3D)
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
	if _is_status_stunned():
		# Stunned: no AI, no intent; gravity + knockback decay still run.
		desired_dir = Vector3.ZERO
		desired_speed = 0.0
		_locomotion.integrate(self, Vector3.ZERO, 0.0, 1.0, delta, false)
		return
	if _machine != null:
		_machine.physics_update(delta)
	_locomotion.integrate(self, desired_dir, desired_speed, _status_speed_factor(), delta)


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
	_locomotion.reset()
	_locomotion.configure(config.acceleration, _locomotion_bounds(), config.bounds_radius)
	desired_dir = Vector3.ZERO
	desired_speed = 0.0
	if _health != null and _health.has_method("reset"):
		_health.call("reset", config.max_health)
	if _feedback != null and _feedback.has_method("recolor"):
		_feedback.call("recolor", config.color_tint)
	_apply_visual_scale(config.visual_scale)
	if _machine != null:
		_machine.force_state(&"idle")
	_navigator.reset(target)
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
	_locomotion.set_bounds(half)


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


## Navigation-aware steering (see EnemyNavigator): prefers the navmesh path when
## usable, otherwise falls back to the caller's direct direction.
func get_navigation_direction(fallback: Vector3) -> Vector3:
	var interval := _config.navigation_target_update_interval if _config != null else 0.2
	return _navigator.direction(global_position, get_move_target(), fallback, interval)


## Controlled melee attack against the current target (see EnemyStriker). Returns
## true when a hit lands; damage is applied exactly once per call.
func perform_enemy_attack() -> bool:
	return _striker.execute(self)


## Attack audio hook for the striker (tolerant when no EnemyAudio child exists).
func play_attack_sound() -> void:
	if _audio != null and _audio.has_method("play_attack"):
		_audio.call("play_attack")


func _locomotion_bounds() -> float:
	return _locomotion.get_bounds()


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
	_locomotion.add_knockback(resisted)


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


## ---------- Elite + boss-phase API (SpawnManager / BossController) ----------

## Mark this enemy elite with the given affix ids (see EliteAffix). Visual tint
## blends the affixes; scale bumps slightly so elites read at a glance.
func set_elite(affixes: Array) -> void:
	set_meta("elite_affixes", affixes.duplicate())
	var tint := Color.WHITE
	for raw in affixes:
		tint = tint.blend(EliteAffix.affix_tint(StringName(String(raw))))
	if _feedback != null and _feedback.has_method("recolor"):
		_feedback.call("recolor", tint)
	_apply_visual_scale((_config.visual_scale if _config != null else 1.0) * 1.12)


func is_elite() -> bool:
	return has_meta("elite_affixes") and not (get_meta("elite_affixes") as Array).is_empty()


func get_elite_affixes() -> Array:
	if not has_meta("elite_affixes"):
		return []
	return (get_meta("elite_affixes") as Array).duplicate()


## Boss phase bumps: multiply the CURRENT effective scales (stacks with wave
## scaling without touching the shared config).
func apply_phase_modifiers(damage_mult: float, speed_mult: float) -> void:
	_damage_scale *= maxf(damage_mult, 0.01)
	_speed_scale *= maxf(speed_mult, 0.01)


## StatusManager queries (tolerant when the scene has no StatusManager child).
func _status_node() -> Node:
	return get_node_or_null("StatusManager")


func _is_status_stunned() -> bool:
	var sm := _status_node()
	return sm != null and sm.has_method("is_stunned") and bool(sm.call("is_stunned"))


func _status_speed_factor() -> float:
	var sm := _status_node()
	if sm != null and sm.has_method("move_speed_factor"):
		return clampf(float(sm.call("move_speed_factor")), 0.0, 2.0)
	return 1.0


func get_health_fraction() -> float:
	if _health != null and _health.has_method("get_health_ratio"):
		return clampf(float(_health.call("get_health_ratio")), 0.0, 1.0)
	return 1.0 if _alive else 0.0


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
