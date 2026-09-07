extends Node
class_name HealthComponent

## Owns current/max health, damage, healing, temporary invulnerability, and death
## state for an entity (player or enemy). Emits only the documented signals; combat
## callers read the returned DamageResult synchronously.

signal health_changed(current: float, maximum: float)
signal damaged(result: DamageResult)
signal died()

@export var max_health: float = 100.0
@export var invulnerability_window: float = 0.4

var current_health: float = 100.0
var _invulnerable_until: float = 0.0
var _is_dead := false
var _time_source: Callable = Callable()   # injectable fake clock for deterministic tests


func set_time_source(source: Callable) -> void:
	_time_source = source


func _ready() -> void:
	set_max_health(max_health)
	current_health = max_health
	health_changed.emit(current_health, max_health)


func set_max_health(value: float) -> void:
	max_health = maxf(value, 1.0)
	current_health = minf(current_health, max_health)


func set_invulnerable(duration: float) -> void:
	_invulnerable_until = maxf(_invulnerable_until, _now() + maxf(duration, 0.0))


func is_invulnerable() -> bool:
	return _now() < _invulnerable_until


func is_dead() -> bool:
	return _is_dead


func get_health_ratio() -> float:
	return current_health / max_health


## Core damage intake. Returns the DamageResult synchronously.
func take_damage(payload: DamagePayload) -> DamageResult:
	var result := DamageResult.new()
	if _is_dead:
		result.ignored_reason = DamageResult.IGNORE_DEAD
		return result
	if payload == null or not payload.is_valid():
		result.ignored_reason = DamageResult.IGNORE_INVALID_PAYLOAD
		return result
	if is_invulnerable():
		result.ignored_reason = DamageResult.IGNORE_INVULNERABLE
		return result
	var amount := payload.amount
	# Damage mitigation hook: component subclasses may override _mitigate.
	amount = _mitigate(amount, payload)
	result.accepted = true
	result.final_amount = amount
	current_health = maxf(current_health - amount, 0.0)
	result.target_died = current_health <= 0.0
	result.knockback_applied = payload.knockback
	health_changed.emit(current_health, max_health)
	damaged.emit(result)
	if result.target_died:
		_die()
	return result


## Positive healing; capped at max health. Never revives a dead entity.
func heal(amount: float) -> float:
	if _is_dead or amount <= 0.0:
		return 0.0
	var before := current_health
	current_health = minf(current_health + amount, max_health)
	var applied := current_health - before
	if applied > 0.0:
		health_changed.emit(current_health, max_health)
	return applied


func _mitigate(amount: float, _payload: DamagePayload) -> float:
	# Overridden by entities with resistance/armour. Base returns amount unchanged.
	return amount


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_invulnerable_until = 0.0
	died.emit()


func reset(max_hp: float) -> void:
	_is_dead = false
	_invulnerable_until = 0.0
	set_max_health(max_hp)
	current_health = max_hp
	health_changed.emit(current_health, max_hp)


func _now() -> float:
	if _time_source.is_valid():
		return float(_time_source.call())
	return Time.get_ticks_msec() / 1000.0


func get_debug_snapshot() -> Dictionary:
	return {
		"current_health": current_health,
		"max_health": max_health,
		"invulnerable": is_invulnerable(),
		"is_dead": _is_dead,
	}
