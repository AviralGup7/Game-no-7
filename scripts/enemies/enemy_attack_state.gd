class_name EnemyAttackState
extends EnemyState

## Attack: telegraph (windup) -> one melee damage query -> cooldown -> back to Chase.
## Timing improvements over the naive loop:
##  - the windup tracks the target; if it escapes past attack_range * 1.3 the swing
##    is aborted back to Chase instead of whiffing on thin air;
##  - the strike plays its whoosh exactly once and lands exactly once (phase gating),
##    which together with the EnemyBase death guard prevents duplicate hits/score;
##  - heavies/bosses arm a poise guard for the windup so chip damage cannot
##    perma-stagger their slow swings (budget from EnemyConfig.poise);
##  - cooldown runs through get_effective_attack_cooldown() (FRENZIED elites swing
##    faster when wounded);
##  - skirmishers (attack_retreat_time > 0) back-pedal after landing the hit.

enum { PHASE_WINDUP, PHASE_COOLDOWN, PHASE_RETREAT }

var _phase := PHASE_WINDUP
var _elapsed := 0.0
## Cooldown for the CURRENT swing, jittered per enemy/personality so a pack
## of eight never swings on one clock (the "synchronized horde" tell).
var _cooldown_target := 1.0


func _init() -> void:
	super(&"attack")


func enter(host: EnemyBase) -> void:
	_phase = PHASE_WINDUP
	_elapsed = 0.0
	host.set_desired_move(Vector3.ZERO, 0.0)
	_arm_poise(host, true)
	if host.has_signal("attack_started"):
		host.attack_started.emit()
	# Telegraph: flash + windup sound so the swing is readable before it lands.
	host.play_telegraph_feedback()
	host.play_windup_sound()


func exit(host: EnemyBase) -> void:
	_arm_poise(host, false)


func _arm_poise(host: EnemyBase, active: bool) -> void:
	var cfg := host.get_config()
	if cfg != null and cfg.poise > 0.0:
		host.set_poise_guard(active)


func physics_update(host: EnemyBase, delta: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	if not host.is_alive():
		return
	var cfg := host.get_config()
	if cfg == null:
		host.state_machine_change_to(&"idle")
		return
	var target := host.get_move_target()
	if target == null:
		host.state_machine_change_to(&"idle")
		return
	host.face_target(target)
	match _phase:
		PHASE_WINDUP:
			host.set_desired_move(Vector3.ZERO, 0.0)
			# Whiff rule: the target slipped away mid-windup -> chase again.
			var dist := host.global_position.distance_to(target.global_position)
			if dist > cfg.attack_range * 1.3:
				host.state_machine_change_to(&"chase")
				return
			_elapsed += delta
			if _elapsed >= cfg.attack_windup:
				_arm_poise(host, false)
				host.play_attack_sound()
				host.perform_enemy_attack()
				if cfg.attack_retreat_time > 0.0:
					_phase = PHASE_RETREAT
				else:
					_phase = PHASE_COOLDOWN
					# Human cadence: this swing's rest is its base cooldown
					# jittered by the enemy's own clock (0.6x .. 1.4x).
					_cooldown_target = host.get_effective_attack_cooldown() \
							* host.get_attack_cooldown_roll()
				_elapsed = 0.0
		PHASE_RETREAT:
			# Hit-and-run: create distance after the strike, then re-engage.
			var away := host.global_position - target.global_position
			away.y = 0.0
			if away.length_squared() < 0.0001:
				away = Vector3.BACK
			host.set_desired_move(away.normalized(), host.get_effective_speed() * 0.8)
			_elapsed += delta
			if _elapsed >= cfg.attack_retreat_time:
				host.state_machine_change_to(&"chase")
		PHASE_COOLDOWN:
			host.set_desired_move(Vector3.ZERO, 0.0)
			_elapsed += delta
			if _elapsed >= _cooldown_target:
				host.state_machine_change_to(&"chase")

## Hardened: validate attack cooldown before entering.
func _validated_attack_cd(cd: float) -> float:
	if not is_finite(cd) or cd <= 0.0:
		return 0.8
	return clampf(cd, 0.05, 10.0)
func _attack_can_enter(host: Node) -> bool:
	if host == null or not is_instance_valid(host):
		return false
	if not host.is_inside_tree():
		return false
	return true

