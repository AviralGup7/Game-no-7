extends Node
class_name AttackController

## Owns attack timing and hit resolution for the player's melee weapon. Reused by
## future weapons via the same command/signal contract. Each completed swing:
##  1. waits out `attack_cooldown` (duplicate presses rejected),
##  2. telegraphs for `attack_windup`,
##  3. resolves targets inside the arc (CombatQuery, against the "enemies" group),
##  4. builds + validates a DamagePayload, applies it, and emits attack_hit.

signal attack_started()
signal attack_finished()
signal attack_hit(target: Node, result: DamageResult)

## Attack tuning (may be overridden by ProgressionComponent-derived stats).
@export var attack_cooldown: float = 0.55
@export var attack_windup: float = 0.12
@export var attack_range: float = 2.6
@export var attack_damage: float = 12.0
@export var knockback_strength: float = 6.0
@export var can_crit: bool = true
@export var critical_multiplier: float = 1.6
@export var crit_chance: float = 0.15
## Melee arc (degrees). 360 => full circle around the player.
@export var arc_degrees: float = 360.0

const TARGET_GROUP := "enemies"

var _attacking := false
var _cooldown_until: float = 0.0
var _time_source: Callable = Callable()
var _owner_body: CharacterBody3D = null


func _ready() -> void:
	_owner_body = get_parent() as CharacterBody3D


func set_time_source(source: Callable) -> void:
	_time_source = source


func is_attacking() -> bool:
	return _attacking


func is_on_cooldown() -> bool:
	return _now() < _cooldown_until


func is_attack_ready() -> bool:
	return not _attacking and not is_on_cooldown()


## Request an attack. Returns true when one begins; repeated requests are rejected.
func request_attack() -> bool:
	if not is_attack_ready():
		return false
	_attacking = true
	_cooldown_until = _now() + attack_cooldown
	attack_started.emit()
	_schedule_resolution()
	return true


func _schedule_resolution() -> void:
	if not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_interval(maxf(attack_windup, 0.0))
	tween.tween_callback(_resolve_hit)
	tween.tween_callback(_complete_attack)


## Build + apply the melee damage to everything in range.
func _resolve_hit() -> void:
	if not is_attacking():
		return
	var owner := _owner_body
	if owner == null or not is_instance_valid(owner) or not owner.is_inside_tree():
		_complete_attack()
		return

	var origin := owner.global_position
	var forward := _facing_forward(owner)
	var candidates := owner.get_tree().get_nodes_in_group(TARGET_GROUP)
	var range_val := _effective_range()
	var targets := CombatQuery.find_targets_in_arc(origin, forward, candidates, range_val, arc_degrees * 0.5)

	for candidate in targets:
		var t: Node3D = candidate as Node3D
		if t == null:
			continue
		var to_target: Vector3 = (t.global_position - origin) * Vector3(1, 0, 1)
		var dir: Vector3 = Vector3.FORWARD if to_target.length_squared() < 0.0001 else to_target.normalized()
		var payload: DamagePayload = _build_payload(dir)
		if not t.has_method("apply_damage"):
			continue
		var result: Variant = t.call("apply_damage", payload)
		if result is DamageResult:
			attack_hit.emit(t, result)
	# All targets resolved exactly once per swing (CombatQuery dedupes by list order).


func _facing_forward(owner: CharacterBody3D) -> Vector3:
	# Visual forward is -Z of the character; keep Y flat.
	var f := -owner.global_transform.basis.z
	f.y = 0.0
	return f if f.length_squared() > 0.001 else Vector3.FORWARD


func _effective_range() -> float:
	if _owner_body == null or not is_instance_valid(_owner_body):
		return attack_range
	var prog := _owner_body.get_node_or_null("ProgressionComponent")
	if prog != null and prog.has_method("get_stat"):
		return float(prog.call("get_stat", &"attack_range_add", attack_range))
	return attack_range


func _effective_damage() -> float:
	var dmg := attack_damage
	if _owner_body != null and is_instance_valid(_owner_body):
		var prog := _owner_body.get_node_or_null("ProgressionComponent")
		if prog != null and prog.has_method("get_stat"):
			dmg = float(prog.call("get_stat", &"attack_damage_multiplier", attack_damage))
	return dmg


func _build_payload(direction: Vector3) -> DamagePayload:
	var payload := DamagePayload.new()
	payload.amount = _effective_damage()
	payload.source = _owner_body
	payload.source_id = &"melee"
	payload.damage_type = &"physical"
	payload.can_crit = can_crit
	payload.critical_multiplier = critical_multiplier
	if can_crit and randf() < crit_chance:
		payload.amount *= critical_multiplier
		payload.metadata["crit"] = true
	var k := knockback_strength
	if _owner_body != null and is_instance_valid(_owner_body):
		var prog := _owner_body.get_node_or_null("ProgressionComponent")
		if prog != null and prog.has_method("get_stat"):
			k = float(prog.call("get_stat", &"knockback_multiplier", knockback_strength))
	payload.knockback = direction * maxf(k, 0.0)
	payload.hit_position = _owner_body.global_position
	return payload


func _complete_attack() -> void:
	if not _attacking:
		return
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
		"attack_range": attack_range,
		"attack_damage": attack_damage,
	}
