extends CharacterBody3D
class_name Player

## Coordinates movement, combat, health, death, and external commands for the player.
## Composition: CharacterController (motion), HealthComponent (health), AttackController
## (legacy attack timing), WeaponManager (loadout + melee/volley dispatch),
## ProgressionComponent (upgrades), TargetingComponent (aim), StaminaComponent
## (dodge/skill resource), ExperienceComponent (XP/levels), SkillController (active
## skills), StatusManager (buffs/debuffs). Locomotion input/bounds live in
## PlayerLocomotion and upgrade/derived-stat application in PlayerBuild; UI and future
## systems talk to THIS node through the stable command interface below.

signal move_started()
signal move_stopped()
signal attack_started()
signal attack_hit(target: Node, result: DamageResult)
signal attack_finished()
signal damaged(result: DamageResult)
signal dodged()
signal died()
signal respawned()
signal upgrade_applied(upgrade_id: StringName)
signal leveled_up(new_level: int)

const DODGE_STAMINA_COST := 25.0
const KILL_XP_BASE := 12.0
const KILL_XP_ELITE_BONUS := 18.0

var _control_enabled := false
var _is_dead := false

## Component references (cached in _ready; tolerant if a scene variant omits them).
var _controller: Node = null
var _health: Node = null
var _attack: Node = null
var _progression: Node = null
var _targeting: Node = null
var _feedback: Node = null
var _player_audio: Node = null
var _dodge: Node = null
var _stamina: Node = null
var _experience: Node = null
var _skills: Node = null
var _weapons: Node = null
var _status: Node = null
var _locomotion := PlayerLocomotion.new()
var _build := PlayerBuild.new()

@export var walk_speed: float = 6.0
@export var max_health: float = 100.0


func _ready() -> void:
	add_to_group("player")
	_controller = get_node_or_null("CharacterController")
	_health = get_node_or_null("HealthComponent")
	_attack = get_node_or_null("AttackController")
	_progression = get_node_or_null("ProgressionComponent")
	_targeting = get_node_or_null("TargetingComponent")
	_feedback = get_node_or_null("PlayerFeedback")
	_player_audio = get_node_or_null("PlayerAudio")
	_dodge = get_node_or_null("DodgeController")
	_stamina = get_node_or_null("StaminaComponent")
	_experience = get_node_or_null("ExperienceComponent")
	_skills = get_node_or_null("SkillController")
	_weapons = get_node_or_null("WeaponManager")
	_status = get_node_or_null("StatusManager")
	_locomotion.bind(self, _dodge, _controller)
	_build.bind(_health, _progression, _controller, _stamina, _weapons, _skills, walk_speed, max_health)
	_locomotion.move_started.connect(move_started.emit)
	_locomotion.move_stopped.connect(move_stopped.emit)
	_build.upgrade_applied.connect(upgrade_applied.emit)
	if _health != null:
		_health.health_changed.connect(_on_health_changed)
		_health.damaged.connect(_on_damaged)
		_health.died.connect(_on_died)
		# Damage resistance: route progression resistance through the generic mitigation
		# seam (HealthComponent stays Player-agnostic).
		if _health.has_method("set_mitigation_source"):
			_health.call("set_mitigation_source", _mitigation_provider)
	if _attack != null:
		_attack.attack_started.connect(_on_attack_started)
		_attack.attack_finished.connect(_on_attack_finished)
		_attack.attack_hit.connect(_on_attack_hit)
	if _weapons != null:
		if _weapons.has_signal("attack_resolved"):
			_weapons.attack_resolved.connect(_on_weapon_attack_resolved)
	if _experience != null and _experience.has_signal("leveled_up"):
		_experience.leveled_up.connect(_on_leveled_up)
	if _dodge != null:
		if _dodge.has_method("bind_health"):
			_dodge.call("bind_health", _health)
		if _dodge.has_signal("dodged_started"):
			_dodge.dodged_started.connect(_on_dodge_started)
	# Bloodlust-style healing: a valid enemy kill heals the real HealthComponent.
	if not EventBus.enemy_killed.is_connected(_on_enemy_kill_heal):
		EventBus.enemy_killed.connect(_on_enemy_kill_heal)
	if not EventBus.enemy_killed.is_connected(_on_enemy_kill_xp):
		EventBus.enemy_killed.connect(_on_enemy_kill_xp)


## Mitigation provider for the generic HealthComponent: computes post-resistance
## damage from the player's progression-derived damage_resistance_add.
func _mitigation_provider(amount: float, _payload: DamagePayload) -> float:
	var resistance := 0.0
	if _progression != null and _progression.has_method("get_stat"):
		resistance = float(_progression.call("get_stat", &"damage_resistance_add", 0.0))
	resistance = clampf(resistance, 0.0, 1.0)
	return maxf(amount * (1.0 - resistance), 0.0)


func _physics_process(delta: float) -> void:
	if not _control_enabled or _is_dead:
		return
	if _is_stunned():
		# Stunned: timers still advance so the stun itself can expire, but no input.
		if _attack != null and _attack.has_method("advance"):
			_attack.call("advance", delta)
		if _weapons != null and _weapons.has_method("tick"):
			_weapons.call("tick", delta)
		return
	if _locomotion.uses_actions():
		if Input.is_action_just_pressed("attack"):
			request_attack()
		if Input.is_action_just_pressed("dodge"):
			request_dodge()
	# Advance attack timers every active step so hits resolve deterministically.
	if _attack != null and _attack.has_method("advance"):
		_attack.call("advance", delta)
	if _weapons != null and _weapons.has_method("tick"):
		_weapons.call("tick", delta)
	var move := _locomotion.gather()
	move *= _move_speed_factor()
	# The dodge is ticked EVERY step so its cooldown can wind down (a cooldown that
	# only ran mid-dodge would lock the player out forever).
	if _dodge != null:
		_dodge.call("tick", delta)
	# Normal locomotion is owned by the CharacterController unless a dodge is mid-flight.
	if _dodge != null and bool(_dodge.call("is_dodging")):
		pass  # DodgeController owns motion (burst + recovery) this step
	elif _controller != null:
		_controller.call("tick", move, delta)
	_locomotion.track(move)
	_locomotion.clamp_to_bounds()


func _is_stunned() -> bool:
	return _status != null and _status.has_method("is_stunned") and bool(_status.call("is_stunned"))


func _move_speed_factor() -> float:
	if _status != null and _status.has_method("move_speed_factor"):
		return clampf(float(_status.call("move_speed_factor")), 0.0, 2.0)
	return 1.0


func set_control_enabled(enabled: bool) -> void:
	_control_enabled = enabled
	if _skills != null and _skills.has_method("set_enabled"):
		_skills.call("set_enabled", enabled)
	if _weapons != null and _weapons.has_method("set_attacks_enabled"):
		_weapons.call("set_attacks_enabled", enabled)
	if not enabled:
		_clear_input()


func enable_action_input(enabled: bool) -> void:
	_locomotion.set_using_actions(enabled)


## ---------- Command interface ----------

func set_move_input(input_vector: Vector2) -> void:
	_locomotion.set_move_input(input_vector)


func clear_move_input() -> void:
	_locomotion.clear_and_idle()


func request_attack() -> void:
	if _is_dead or not _control_enabled:
		return
	# WeaponManager is the primary path when a weapon is equipped; the legacy
	# AttackController stays as the fallback so older scenes keep working.
	if _weapons != null and _weapons.has_method("active_instance") and _weapons.call("active_instance") != null:
		if _weapons.has_method("request_attack"):
			_weapons.call("request_attack")
		return
	if _attack != null and _attack.has_method("request_attack"):
		_attack.call("request_attack")


func request_dodge() -> bool:
	if _is_dead or not _control_enabled:
		return false
	if _dodge == null or not _dodge.has_method("request"):
		return false
	if not try_spend_stamina(DODGE_STAMINA_COST):
		return false
	# Direction: prefer the current movement input (camera-relative); fall back to the
	# body's facing (world -Z) so a standing dodge always goes somewhere.
	var dir := Vector3.FORWARD
	if _controller != null and _controller.has_method("screen_to_world_dir"):
		var move := _locomotion.gather()
		var world := _controller.call("screen_to_world_dir", move) as Vector3
		if world.length_squared() > 0.0001:
			dir = world
	var started := bool(_dodge.call("request", dir))
	if started:
		dodged.emit()
	else:
		# Refund the stamina when the dodge itself refused (cooldown, mid-air...).
		restore_stamina(DODGE_STAMINA_COST)
	return started


func apply_damage(payload: DamagePayload) -> DamageResult:
	var result := DamageResult.new()
	if _health == null or not _health.has_method("take_damage"):
		result.ignored_reason = &"no_health_component"
		return result
	if _is_dead:
		result.ignored_reason = DamageResult.IGNORE_DEAD
		return result
	var final_payload := _apply_status_intake(payload)
	var taken: Variant = _health.call("take_damage", final_payload)
	if taken is DamageResult:
		return taken
	result.ignored_reason = &"invalid_result"
	return result


## Scale + shield an incoming payload through the StatusManager (guard shields,
## shock vulnerability...). Returns the original payload when no manager exists.
func _apply_status_intake(payload: DamagePayload) -> DamagePayload:
	if _status == null or payload == null:
		return payload
	var factor := 1.0
	if _status.has_method("incoming_damage_factor"):
		factor = float(_status.call("incoming_damage_factor"))
	var amount := payload.amount * factor
	if _status.has_method("absorb_direct"):
		amount = float(_status.call("absorb_direct", amount))
	if is_equal_approx(amount, payload.amount):
		return payload
	return payload.with_amount(amount)


## ---------- Stamina / XP / skill / weapon / status facades ----------

func try_spend_stamina(amount: float) -> bool:
	if _stamina == null or not _stamina.has_method("try_spend"):
		return true  # no stamina system wired: actions are free
	return bool(_stamina.call("try_spend", amount))


func restore_stamina(amount: float) -> void:
	if _stamina != null and _stamina.has_method("restore"):
		_stamina.call("restore", amount)


func get_stamina_fraction() -> float:
	if _stamina != null and _stamina.has_method("get_fraction"):
		return float(_stamina.call("get_fraction"))
	return 1.0


func add_xp(amount: float) -> int:
	if _experience != null and _experience.has_method("add_xp"):
		return int(_experience.call("add_xp", amount))
	return 0


func get_level() -> int:
	if _experience != null and _experience.has_method("get_level"):
		return int(_experience.call("get_level"))
	return 1


func get_xp_fraction() -> float:
	if _experience != null and _experience.has_method("get_fraction_into_level"):
		return float(_experience.call("get_fraction_into_level"))
	return 0.0


func request_skill(slot: int) -> bool:
	if _is_dead or not _control_enabled:
		return false
	if _skills != null and _skills.has_method("try_cast_slot"):
		return bool(_skills.call("try_cast_slot", slot))
	return false


func get_skill_controller() -> Node:
	return _skills


func get_weapon_manager() -> Node:
	return _weapons


func get_status_manager() -> Node:
	return _status


func apply_status_effects(effect_ids: Array, source: Node = null) -> Dictionary:
	if _status != null and _status.has_method("apply_effects"):
		return _status.call("apply_effects", effect_ids, source)
	return {}


func cleanse_status(only_harmful: bool = true) -> int:
	if _status != null and _status.has_method("cleanse_all"):
		return int(_status.call("cleanse_all", only_harmful))
	return 0


## Apply an upgrade through the runtime ProgressionComponent (see PlayerBuild).
func apply_upgrade(upgrade_id: StringName) -> bool:
	return _build.apply_upgrade(upgrade_id)


## Bloodlust-style heal: valid enemy kills heal while the player is alive.
func _on_enemy_kill_heal(_enemy: Node, _archetype_id: StringName, _score: int, _currency: int) -> void:
	if _is_dead or _health == null:
		return
	if _progression == null or not _progression.has_method("get_stat"):
		return
	var heal_amount := float(_progression.call("get_stat", &"healing_on_kill", 0.0))
	if heal_amount > 0.0 and _health.has_method("heal"):
		_health.call("heal", heal_amount)


## Every valid kill feeds XP (elites are worth extra).
func _on_enemy_kill_xp(enemy: Node, _archetype_id: StringName, _score: int, _currency: int) -> void:
	if _is_dead or _experience == null:
		return
	var award := KILL_XP_BASE
	if enemy != null and enemy.has_method("is_elite") and bool(enemy.call("is_elite")):
		award += KILL_XP_ELITE_BONUS
	add_xp(award)


func _on_leveled_up(new_level: int) -> void:
	leveled_up.emit(new_level)


func _on_weapon_attack_resolved(weapon_id: StringName, hit_count: int, was_crit: bool) -> void:
	attack_finished.emit()
	EventBus.report_info("Weapon %s resolved %d hits%s" % [String(weapon_id), hit_count, " CRIT" if was_crit else ""])


func reset_for_new_run(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	_is_dead = false
	_control_enabled = false
	_clear_input()
	# Reset progression FIRST so health derives from the fresh (empty) run modifiers.
	if _progression != null and _progression.has_method("reset"):
		_progression.call("reset")
	if _health != null and _health.has_method("reset"):
		_health.call("reset", _build.derived_max_health())
	if _attack != null and _attack.has_method("reset_attack_state"):
		_attack.call("reset_attack_state")
	if _dodge != null and _dodge.has_method("reset"):
		_dodge.call("reset")
	if _stamina != null and _stamina.has_method("reset_for_new_run"):
		_stamina.call("reset_for_new_run")
	if _experience != null and _experience.has_method("reset_for_new_run"):
		_experience.call("reset_for_new_run")
	if _skills != null and _skills.has_method("reset_for_new_run"):
		_skills.call("reset_for_new_run")
	if _weapons != null and _weapons.has_method("reset_for_new_run"):
		_weapons.call("reset_for_new_run")
	if _status != null and _status.has_method("clear_all"):
		_status.call("clear_all")
	_build.rebuild_derived_stats()
	_equip_starter_kit()
	respawned.emit()


## Starter kit: Gladius in slot 0 + the first skill unlocked (all tolerant when
## the ContentRegistry is unavailable, e.g. headless direct use).
func _equip_starter_kit() -> void:
	if _weapons != null and _weapons.has_method("equip_by_id"):
		_weapons.call("equip_by_id", &"gladius", 0)
	if _skills != null and _skills.has_method("assign_skill_by_id"):
		_skills.call("assign_skill_by_id", &"seismic_slam", 0, true)
		_skills.call("assign_skill_by_id", &"bladestorm", 1, false)
		_skills.call("assign_skill_by_id", &"phantom_rush", 2, false)


## Set the arena interior half-extent for movement/bounds clamping; -1 disables it.
func set_bounds(half: float) -> void:
	_locomotion.set_bounds(half)


func is_alive() -> bool:
	return not _is_dead


## ---------- Internal ----------

func _clear_input() -> void:
	_locomotion.clear()


func _on_health_changed(current: float, maximum: float) -> void:
	EventBus.player_health_changed.emit(current, maximum)


func _on_damaged(result: DamageResult) -> void:
	damaged.emit(result)
	if _feedback != null and _feedback.has_method("play_hit_feedback"):
		_feedback.call("play_hit_feedback")
	if _player_audio != null and _player_audio.has_method("play_hurt"):
		_player_audio.call("play_hurt")


func _on_died() -> void:
	if _is_dead:
		return
	_is_dead = true
	_control_enabled = false
	_clear_input()
	died.emit()
	EventBus.player_died.emit()
	if _player_audio != null and _player_audio.has_method("play_death"):
		_player_audio.call("play_death")
	if GameRoot != null:
		GameRoot.request_game_over()


func _on_attack_started() -> void:
	attack_started.emit()
	EventBus.report_info("Player attack started")
	if _feedback != null and _feedback.has_method("play_attack_feedback"):
		_feedback.call("play_attack_feedback")
	if _player_audio != null and _player_audio.has_method("play_attack"):
		_player_audio.call("play_attack")


func _on_attack_finished() -> void:
	attack_finished.emit()


func _on_dodge_started() -> void:
	AudioManager.play_sfx(&"player_dodge")
	if _feedback != null and _feedback.has_method("play_dodge_feedback"):
		_feedback.call("play_dodge_feedback")


func _on_attack_hit(target: Node, result: DamageResult) -> void:
	attack_hit.emit(target, result)


func get_progression_snapshot() -> Dictionary:
	if _progression != null and _progression.has_method("get_debug_snapshot"):
		return _progression.call("get_debug_snapshot")
	return {}


func get_debug_snapshot() -> Dictionary:
	var hp: Dictionary = {}
	if _health != null and _health.has_method("get_debug_snapshot"):
		hp = _health.call("get_debug_snapshot")
	var ctl: Dictionary = {}
	if _controller != null and _controller.has_method("get_debug_snapshot"):
		ctl = _controller.call("get_debug_snapshot")
	var weap: Dictionary = {}
	if _weapons != null and _weapons.has_method("get_debug_snapshot"):
		weap = _weapons.call("get_debug_snapshot")
	var skl: Dictionary = {}
	if _skills != null and _skills.has_method("get_debug_snapshot"):
		skl = _skills.call("get_debug_snapshot")
	return {
		"position": global_position,
		"health": hp,
		"controller": ctl,
		"alive": is_alive(),
		"control_enabled": _control_enabled,
		"progression": get_progression_snapshot(),
		"level": get_level(),
		"stamina": get_stamina_fraction(),
		"weapons": weap,
		"skills": skl,
	}
