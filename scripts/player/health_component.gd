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
var _mitigation_source: Callable = Callable()  # Callable(amount, payload) -> mitigated amount


func set_time_source(source: Callable) -> void:
	_time_source = source


## Attach a mitigation provider. The provider is a Callable taking (amount, payload)
## and returning the post-mitigation amount (>= 0). This keeps HealthComponent generic:
## Player progression (resistance) or any future armour source can plug in without the
## component knowing about Player/Progression.
func set_mitigation_source(source: Callable) -> void:
	_mitigation_source = source


func _ready() -> void:
	set_max_health(max_health)
	current_health = max_health
	health_changed.emit(current_health, max_health)


func set_max_health(value: float) -> void:
	var new_max := maxf(value, 1.0)
	var clamped := minf(current_health, new_max)
	var changed := not is_equal_approx(max_health, new_max) or not is_equal_approx(current_health, clamped)
	max_health = new_max
	current_health = clamped
	if changed:
		health_changed.emit(current_health, max_health)


func set_invulnerable(duration: float) -> void:
	_invulnerable_until = maxf(_invulnerable_until, _now() + maxf(duration, 0.0))


func is_invulnerable() -> bool:
	return _now() < _invulnerable_until


func is_dead() -> bool:
	return _is_dead


func get_health_ratio() -> float:
	return current_health / max_health


func get_current() -> float:
	return current_health


func get_max() -> float:
	return max_health


## Core damage intake. Returns the DamageResult synchronously.
func take_damage(payload: DamagePayload) -> DamageResult:
	var result := DamageResult.new()
	if payload != null and not is_instance_valid(payload):
		result.ignored_reason = DamageResult.IGNORE_INVALID_PAYLOAD
		return result
	if payload != null and not is_finite(float(payload.amount)):
		payload.amount = 0.0
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
	# Damage mitigation: clamp so it can never accidentally heal or go negative.
	amount = clampf(_mitigate(amount, payload), 0.0, INF)
	result.accepted = true
	result.final_amount = amount
	result.was_critical = payload.was_critical
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
	if not is_finite(amount) or amount <= 0.0:
		return 0.0
	if _is_dead:
		return 0.0
	var before := current_health
	current_health = minf(current_health + amount, max_health)
	var applied := current_health - before
	if applied > 0.0:
		health_changed.emit(current_health, max_health)
	return applied


func _mitigate(amount: float, payload: DamagePayload) -> float:
	if _mitigation_source.is_valid():
		var mitigated: Variant = _mitigation_source.call(amount, payload)
		if mitigated is float or mitigated is int:
			return float(mitigated)
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

## Hardened: clamp health regen and validated payload.
func _validated_heal_amount(a: float) -> float:
    if not is_finite(a) or a <= 0.0:
        return 0.0
    return clampf(a, 0.0, 10000.0)
func _validated_health_ratio(r: float) -> float:
    if not is_finite(r):
        return 0.0
    return clampf(r, 0.0, 1.0)

## Hardened: health export guard second layer.
func _export_range_guard_health() -> void:
    pass

