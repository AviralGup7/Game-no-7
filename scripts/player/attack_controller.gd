extends Node
class_name AttackController

## Owns attack timing: cooldown, windup, the damage payload a completed melee attack
## produces, and attack signals. Phase 1 implements timing + the stable command/signal
## contract; the actual hitbox/application pipeline plugs in during the combat phase
## through the same interface, and future weapons reuse it via data-driven profiles.

signal attack_started()
signal attack_finished()
signal attack_hit(target: Node, result: DamageResult)

@export var attack_cooldown: float = 0.55
@export var attack_windup: float = 0.12
@export var attack_range: float = 2.2
@export var attack_damage: float = 10.0
@export var knockback_strength: float = 6.0
@export var can_crit: bool = true
@export var critical_multiplier: float = 1.5

var _attacking := false
var _cooldown_until: float = 0.0
var _time_source: Callable = Callable()


func _ready() -> void:
	pass


func set_time_source(source: Callable) -> void:
	_time_source = source


func is_attacking() -> bool:
	return _attacking


func is_on_cooldown() -> bool:
	return _now() < _cooldown_until


func is_attack_ready() -> bool:
	return not _attacking and not is_on_cooldown()


## Request an attack. Returns true when one begins; repeated requests are rejected
## (guard against held-input spam / multi-touch duplicates).
func request_attack() -> bool:
	if not is_attack_ready():
		return false
	_attacking = true
	_cooldown_until = _now() + attack_cooldown
	attack_started.emit()
	_finish_later()
	return true


func _finish_later() -> void:
	if not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_interval(attack_windup)
	tween.tween_callback(_complete_attack)


func _complete_attack() -> void:
	_attacking = false
	attack_finished.emit()


func set_attack_cooldown(value: float) -> void:
	attack_cooldown = maxf(value, 0.05)


func set_attack_damage(value: float) -> void:
	attack_damage = maxf(value, 0.0)


func set_attack_range(value: float) -> void:
	attack_range = maxf(value, 0.5)


func reset_attack_state() -> void:
	_attacking = false
	_cooldown_until = 0.0


func _now() -> float:
	if _time_source.is_valid():
		return float(_time_source.call())
	return Time.get_ticks_msec() / 1000.0


func get_debug_snapshot() -> Dictionary:
	return {
		"attacking": _attacking,
		"on_cooldown": is_on_cooldown(),
		"attack_cooldown": attack_cooldown,
	}
