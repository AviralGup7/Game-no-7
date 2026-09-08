class_name EnemyStriker
extends RefCounted

## Controlled melee attacks, extracted from EnemyBase. Resolves one guarded swing
## against the host's current target (alive/range/line-of-sight/config checks),
## builds the damage payload, and reports the hit through the host's signals.
## `attack_started` is emitted by the owning state (once per attack); the striker
## only reports contact via `attack_hit`. Duplicate protection comes from the state
## machine (windup phase gating) plus the alive guards here and in the target.


## Perform the melee attack against the current target. Returns true when a hit
## lands (damage accepted exactly once per call).
func execute(host: EnemyBase) -> bool:
	if host == null or not host.is_alive():
		return false
	var target := host.get_move_target()
	if target == null:
		return false
	if not host.target_in_attack_range(target):
		return false
	if _wall_between(host, target):
		return false
	if host.get_config() == null:
		return false
	return _strike(host, target, host.get_effective_attack_damage(), _knockback_strength(host))


## Dash-charge contact hit: wider radius than the melee swing, damage scaled by the
## config's dash_damage_scale, stronger shove. Called at most once per charge by
## the dash state.
func execute_dash(host: EnemyBase, contact_radius: float) -> bool:
	if host == null or not host.is_alive():
		return false
	var cfg := host.get_config()
	if cfg == null:
		return false
	var target := host.get_move_target()
	if target == null:
		return false
	if host.global_position.distance_to(target.global_position) > maxf(contact_radius, 0.1):
		return false
	if _wall_between(host, target):
		return false
	var damage := host.get_effective_attack_damage() * maxf(cfg.dash_damage_scale, 0.0)
	return _strike(host, target, damage, _knockback_strength(host) * 1.5)


func _strike(host: EnemyBase, target: Node3D, damage: float, knockback: float) -> bool:
	var to_t := target.global_position - host.global_position
	to_t.y = 0.0
	var dir := Vector3.FORWARD
	if to_t.length_squared() > 0.0001:
		dir = to_t.normalized()
	var payload := DamagePayload.new()
	payload.amount = damage
	payload.source = host
	payload.source_id = host.get_archetype_id()
	payload.damage_type = &"physical"
	payload.knockback = dir * knockback
	payload.hit_position = host.global_position
	if not target.has_method("apply_damage"):
		return false
	var result: Variant = target.call("apply_damage", payload)
	if result is DamageResult:
		var res := result as DamageResult
		host.attack_hit.emit(target, res)
		return res.accepted
	return false


func _knockback_strength(host: EnemyBase) -> float:
	if host.get_config() == null:
		return 4.0
	# Heavier enemies push harder; scaled by their effective damage for readability.
	return clampf(3.0 + host.get_effective_attack_damage() * 0.25, 2.0, 16.0)


func _wall_between(host: EnemyBase, target: Node3D) -> bool:
	var space := host.get_world_3d().direct_space_state
	if space == null:
		return false
	var from := host.global_position + Vector3(0, 0.8, 0)
	var to := target.global_position + Vector3(0, 0.8, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 0b0001)
	var hit := space.intersect_ray(query)
	return not hit.is_empty()
