extends CharacterBody3D
class_name EnemyBase

## Reusable enemy base. Phase 2 responsibility: lifecycle, damage intake, health,
## idempotent death + exactly-once score payload, tinting, and common signals.
## Movement/AI states and navigation arrive in Phase 3 via the StateMachine node.

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
var _alive := true
var _death_handled := false
var _score_value: int = 0
var _currency_value: int = 0
var _run_seed: int = 0

var _health: Node = null
var _feedback: Node = null
var _audio: Node = null
var _target: Node3D = null


func _ready() -> void:
	add_to_group(TARGET_GROUP)
	_health = get_node_or_null("HealthComponent")
	_feedback = get_node_or_null("EnemyFeedback")
	_audio = get_node_or_null("EnemyAudio")
	if _health != null:
		_health.health_changed.connect(func(_c: float, _m: float) -> void: pass)
		_health.damaged.connect(_on_damaged)
		_health.died.connect(_on_died)


## ---------- Stable command interface ----------

func initialize(config: EnemyConfig, target: Node3D, run_seed: int = 0) -> void:
	if config == null:
		push_warning("EnemyBase.initialize received null config")
		return
	_config = config
	_archetype_id = config.archetype_id
	_score_value = config.score_value
	_currency_value = config.currency_value
	_run_seed = run_seed
	_alive = true
	_death_handled = false
	_target = target
	if _health != null and _health.has_method("reset"):
		_health.call("reset", config.max_health)
	if _feedback != null and _feedback.has_method("recolor"):
		_feedback.call("recolor", config.color_tint)
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
		return taken
	result.ignored_reason = &"invalid_result"
	return result


## Reserved for the AI phase. Currently only a diagnostic, never fatal.
func force_state(state_id: StringName) -> void:
	EventBus.report_info("Enemy %s force_state(%s) — state machine arrives in phase 3" % [String(_archetype_id), String(state_id)])


func is_alive() -> bool:
	return _alive


func get_archetype_id() -> StringName:
	return _archetype_id


func get_config() -> EnemyConfig:
	return _config


## ---------- Internal handlers ----------

func _on_damaged(result: DamageResult) -> void:
	damaged.emit(result)
	if _feedback != null and _feedback.has_method("play_damaged"):
		_feedback.call("play_damaged")
	if _audio != null and _audio.has_method("play_hit"):
		_audio.call("play_hit")


func _on_died() -> void:
	if _death_handled:
		return
	_death_handled = true
	_alive = false
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
	tween.tween_interval(0.4)
	tween.tween_callback(queue_free)


## Knockback integration for future movement phases: record the impulse so a later
## controller can consume it. Kept minimal + non-fatal for phase 2.
func apply_knockback(_impulse: Vector3) -> void:
	set_meta("pending_knockback", _impulse)


func get_debug_snapshot() -> Dictionary:
	var hp: Dictionary = {}
	if _health != null and _health.has_method("get_debug_snapshot"):
		hp = _health.call("get_debug_snapshot")
	return {
		"archetype": String(_archetype_id),
		"alive": _alive,
		"death_handled": _death_handled,
		"position": global_position,
		"health": hp,
	}
