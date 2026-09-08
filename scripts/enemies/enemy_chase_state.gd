class_name EnemyChaseState
extends EnemyState

## Chase: steers toward the target at the configured move speed (via navigation when
## available, else direct pursuit) and transitions to Attack once in range. Each enemy
## aims at its own approach point (deterministic per spawn) so packs fan out around
## the player instead of stacking. Archetypes with a dash_trigger_range launch a
## telegraphed charge instead of walking in; exploders ignite inside fuse_range.
## Falls back to Idle when the target disappears.

func _init() -> void:
	super(&"chase")


func enter(host: EnemyBase) -> void:
	host.set_desired_move(Vector3.ZERO, 0.0)


func physics_update(host: EnemyBase, _delta: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	if not host.is_alive():
		return
	var target := host.get_move_target()
	if target == null:
		host.set_desired_move(Vector3.ZERO, 0.0)
		host.state_machine_change_to(&"idle")
		return
	var cfg := host.get_config()
	if cfg == null:
		return
	var flat_offset := target.global_position - host.global_position
	flat_offset.y = 0.0
	var dist := flat_offset.length()
	# Ranged archetypes orbit + volley instead of closing to melee.
	if String(cfg.ai_behavior) == "ranged":
		host.state_machine_change_to(&"ranged")
		return
	# Exploder: inside the fuse radius, plant and ignite instead of meleeing.
	if cfg.fuse_range > 0.0 and dist <= cfg.fuse_range:
		host.state_machine_change_to(&"fuse")
		return
	# Dasher: prefer a telegraphed charge over walking in once off cooldown.
	if cfg.dash_trigger_range > 0.0 and dist <= cfg.dash_trigger_range and dist > cfg.attack_range:
		if host.try_begin_dash():
			host.state_machine_change_to(&"dash")
			return
	if host.target_in_attack_range(target):
		host.set_desired_move(Vector3.ZERO, 0.0)
		host.state_machine_change_to(&"attack")
		return
	# Steer to this enemy's personal approach point (fan-out, anti-stacking).
	var approach := host.get_approach_point(target.global_position)
	var offset := approach - host.global_position
	offset.y = 0.0
	var desired := Vector3.FORWARD
	if offset.length_squared() > 0.0001:
		desired = offset.normalized()
	var steer := host.get_navigation_direction(desired)
	host.set_desired_move(steer, host.get_effective_speed())
	host.face_direction(steer)

## A chase target is any live, in-tree Node3D body. (The old expression ended in
## `... or t is Node3D`, which made the has_method() clause dead code and even
## let freed Node3Ds pass; this keeps the intended semantics only.)
func _chase_is_target_valid(t: Node) -> bool:
	return t is Node3D and is_instance_valid(t) and t.is_inside_tree()
