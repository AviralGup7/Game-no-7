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
var _attack_buffer := AttackBuffer.new()
var _gameplay_time := 0.0

@export var attack_buffer_seconds: float = 0.18

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
		if _health.has_method("set_time_source"):
			_health.call("set_time_source", _health_now)
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
	_gameplay_time += maxf(delta, 0.0)
	if _is_stunned():
		_cancel_combat()
		velocity.x = 0.0
		velocity.z = 0.0
		var dodge_moving := _dodge != null and bool(_dodge.call("is_dodging"))
		if _dodge != null:
			_dodge.call("tick", delta)
		if not dodge_moving and _controller != null:
			_controller.call("tick", Vector2.ZERO, delta)
		_locomotion.track(Vector2.ZERO)
		_locomotion.clamp_to_bounds()
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
		if Input.is_action_just_pressed("switch_weapon"):
			request_weapon_switch()
	# Advance attack timers every active step so hits resolve deterministically.
	if _attack != null and _attack.has_method("advance"):
		_attack.call("advance", delta)
	if _weapons != null and _weapons.has_method("tick"):
		_weapons.call("tick", delta)
	_attack_buffer.tick(delta, _try_attack)
	var move := _locomotion.gather()
	move *= _move_speed_factor()
	# The dodge is ticked EVERY step so its cooldown can wind down (a cooldown that
	# only ran mid-dodge would lock the player out forever).
	var dodge_owned_motion := _dodge != null and bool(_dodge.call("is_dodging"))
	if _dodge != null:
		_dodge.call("tick", delta)
	# Normal locomotion is owned by the CharacterController unless a dodge is mid-flight.
	if dodge_owned_motion:
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
	if _attack != null:
		_attack.call("set_attacks_enabled", enabled)
	if not enabled:
		velocity = Vector3.ZERO
		_clear_input()


func enable_action_input(enabled: bool) -> void:
	_locomotion.set_using_actions(enabled)


## ---------- Command interface ----------

func set_move_input(input_vector: Vector2) -> void:
	if not is_control_enabled():
		_locomotion.clear()
		return
	_locomotion.set_move_input(input_vector)


func clear_move_input() -> void:
	_locomotion.clear_and_idle()


func request_attack() -> void:
	if not _can_combat():
		return
	_attack_buffer.clear()
	if not _try_attack():
		_attack_buffer.push(attack_buffer_seconds)


func _can_combat() -> bool:
	return not _is_dead and _control_enabled and not _is_stunned()


func _try_attack() -> bool:
	if not _can_combat() or (_dodge != null and bool(_dodge.call("is_dodging"))):
		return false
	if _weapons != null and _weapons.has_method("active_instance") and _weapons.call("active_instance") != null:
		if int(_weapons.call("request_attack")) <= 0:
			return false
		_aim_attack()
		_on_attack_started()
		return true
	if _attack != null:
		var started := bool(_attack.call("request_attack"))
		if started:
			_aim_attack()
		return started
	return false


func _aim_attack() -> void:
	if _targeting == null or _controller == null or not _controller.has_method("face_direction"):
		return
	var target: Node = _targeting.call("pick_best_target", get_tree().get_nodes_in_group("enemies"))
	if target is Node3D:
		_controller.call("face_direction", (target as Node3D).global_position - global_position)


func request_dodge() -> bool:
	if not _can_combat():
		return false
	if _dodge == null or not _dodge.has_method("request"):
		return false
	if not bool(_dodge.call("is_ready")):
		return false
	if not bool(_dodge.get("can_interrupt_attack")) and _combat_busy():
		return false
	var cost := maxf(float(_dodge.get("stamina_cost")), 0.0)
	if not try_spend_stamina(cost):
		return false
	# Direction: prefer the current movement input (camera-relative); fall back to the
	# body's facing (world -Z) so a standing dodge always goes somewhere.
	var dir := -global_basis.z
	if _controller != null and _controller.has_method("screen_to_world_dir"):
		var move := _locomotion.gather()
		var world := _controller.call("screen_to_world_dir", move) as Vector3
		if world.length_squared() > 0.0001:
			dir = world
	var started := bool(_dodge.call("request", dir))
	if started:
		_cancel_combat()
		if _controller != null:
			_controller.call("face_direction", dir)
		dodged.emit()
	else:
		# Refund the stamina when the dodge itself refused (cooldown, mid-air...).
		restore_stamina(cost)
	return started


func apply_damage(payload: DamagePayload) -> DamageResult:
	var result := DamageResult.new()
	if _health == null or not _health.has_method("take_damage"):
		result.ignored_reason = &"no_health_component"
		return result
	if _is_dead:
		result.ignored_reason = DamageResult.IGNORE_DEAD
		return result
	# Do not consume a shield for payloads HealthComponent will reject before
	# intake (malformed, invulnerable, or already-dead). Accepted hits are then
	# reduced by status mitigation/shields exactly once.
	if payload == null or not payload.is_valid() or (_health.has_method("is_invulnerable") and bool(_health.call("is_invulnerable"))):
		var rejected: Variant = _health.call("take_damage", payload)
		if rejected is DamageResult:
			return rejected
		return result
	var final_payload := _apply_status_intake(payload)
	var taken: Variant = _health.call("take_damage", final_payload)
	if taken is DamageResult:
		if (taken as DamageResult).accepted and (taken as DamageResult).final_amount > 0.0:
			_apply_payload_status(payload, taken as DamageResult)
		return taken
	result.ignored_reason = &"invalid_result"
	return result


## Incoming weapon/projectile riders: apply payload effects after an accepted hit.
func _apply_payload_status(payload: DamagePayload, result: DamageResult = null) -> void:
	if payload == null or payload.status_effects.is_empty():
		return
	if _status != null and _status.has_method("apply_effects"):
		var applied: Variant = _status.call("apply_effects", payload.status_effects, payload.source)
		if result != null and applied is Dictionary:
			for raw_id in applied:
				if int(applied[raw_id]) > 0:
					result.status_effects_applied.append(StringName(String(raw_id)))


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


## Serializable build mirror consumed by RunState. Live components remain the
## source of truth; this method only reads their stable content ids and tags.
func get_build_snapshot() -> Dictionary:
	var weapons: Array = []
	var skills: Array = []
	if _weapons != null and _weapons.has_method("get_loadout_ids"):
		weapons = _weapons.call("get_loadout_ids")
	if _skills != null and _skills.has_method("get_assigned_skill_ids"):
		skills = _skills.call("get_assigned_skill_ids")
	var archetypes: Array[StringName] = []
	if ContentRegistry != null:
		for id in weapons:
			var wc := ContentRegistry.get_weapon(StringName(String(id)))
			if wc != null:
				for tag in wc.tags:
					if tag not in archetypes:
						archetypes.append(tag)
		for id in skills:
			var sc := ContentRegistry.get_skill(StringName(String(id)))
			if sc != null:
				for tag in sc.tags:
					if tag not in archetypes:
						archetypes.append(tag)
		if _progression != null and _progression.has_method("get_upgrade_stack_snapshot"):
			var stacks: Dictionary = _progression.call("get_upgrade_stack_snapshot")
			for id in stacks:
				if int(stacks[id]) <= 0:
					continue
				var uc := ContentRegistry.get_upgrade(StringName(String(id)))
				if uc != null:
					if uc.category not in archetypes:
						archetypes.append(uc.category)
					for tag in uc.tags:
						if tag not in archetypes:
							archetypes.append(tag)
	return {"equipped_weapons": weapons, "equipped_skills": skills, "build_archetypes": archetypes}


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


## Rebuild all runtime facades after an external permanent/meta modifier is applied.
func rebuild_derived_stats() -> void:
	_build.rebuild_derived_stats()


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
	if _progression != null and _progression.has_method("get_stat"):
		award *= float(_progression.call("get_stat", &"xp_multiplier_add", 1.0))
	add_xp(award)


func _on_leveled_up(new_level: int) -> void:
	leveled_up.emit(new_level)
	# The ExperienceComponent owns the level reward (heal + stamina); the player
	# owns the celebration.
	if EventBus != null:
		EventBus.announcement.emit(&"level_up", "Level %d!" % new_level, &"info")
	if AudioManager != null:
		AudioManager.play_sfx(&"upgrade_select")


func _on_weapon_attack_resolved(weapon_id: StringName, hit_count: int, was_crit: bool) -> void:
	attack_finished.emit()
	if hit_count > 0 and _feedback != null:
		_feedback.call("play_impact_feedback", was_crit)


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


## Cycle the weapon loadout (Tab / Y / touch button). Returns false when there is
## no second weapon to switch to.
func request_weapon_switch() -> bool:
	if not _can_combat() or (_dodge != null and bool(_dodge.call("is_dodging"))):
		return false
	if _weapons == null or not _weapons.has_method("cycle_weapon"):
		return false
	var switched := bool(_weapons.call("cycle_weapon"))
	if switched:
		_attack_buffer.clear()
	return switched


## Starter kit: daily loadout (or Gladius) in slot 0 + the first skill unlocked
## (all tolerant when the ContentRegistry is unavailable, e.g. headless direct use).
## Slot 1 + locked skills are filled by Main from owned meta unlocks after reset.
func _equip_starter_kit() -> void:
	if _weapons != null and _weapons.has_method("equip_by_id"):
		_weapons.call("equip_by_id", _starter_weapon_id(), 0, true)
	if _skills != null and _skills.has_method("assign_skill_by_id"):
		_skills.call("assign_skill_by_id", &"seismic_slam", 0, true)
		_skills.call("assign_skill_by_id", &"bladestorm", 1, false)
		_skills.call("assign_skill_by_id", &"phantom_rush", 2, false)


func _starter_weapon_id() -> StringName:
	if GameRoot != null and GameRoot.has_method("get_daily_weapon"):
		return StringName(GameRoot.call("get_daily_weapon"))
	return &"gladius"


## Set the arena interior half-extent for movement/bounds clamping; -1 disables it.
func set_bounds(half: float) -> void:
	_locomotion.set_bounds(half)


func is_alive() -> bool:
	return not _is_dead


## ---------- Internal ----------

func _clear_input() -> void:
	_attack_buffer.clear()
	_locomotion.clear()


func _on_health_changed(current: float, maximum: float) -> void:
	EventBus.player_health_changed.emit(current, maximum)


func _on_damaged(result: DamageResult) -> void:
	_cancel_combat()
	damaged.emit(result)
	if _feedback != null and _feedback.has_method("play_hit_feedback"):
		_feedback.call("play_hit_feedback")
	if not result.target_died and _player_audio != null and _player_audio.has_method("play_hurt"):
		_player_audio.call("play_hurt")


func _on_died() -> void:
	if _is_dead:
		return
	_is_dead = true
	set_control_enabled(false)
	_cancel_combat()
	if _dodge != null:
		_dodge.call("reset")
	died.emit()
	EventBus.player_died.emit()
	if _player_audio != null and _player_audio.has_method("play_death"):
		_player_audio.call("play_death")
	if GameRoot != null:
		GameRoot.request_game_over()


func _on_attack_started() -> void:
	attack_started.emit()
	if _feedback != null and _feedback.has_method("play_attack_feedback"):
		_feedback.call("play_attack_feedback")
	if _player_audio != null and _player_audio.has_method("play_attack"):
		_player_audio.call("play_attack")


func _on_attack_finished() -> void:
	attack_finished.emit()


func _on_dodge_started() -> void:
	if _player_audio != null:
		_player_audio.call("play_dodge")
	if _feedback != null and _feedback.has_method("play_dodge_feedback"):
		_feedback.call("play_dodge_feedback")


func _on_attack_hit(target: Node, result: DamageResult) -> void:
	attack_hit.emit(target, result)
	if result.accepted and _feedback != null:
		_feedback.call("play_impact_feedback", result.was_critical)


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
	var progression_debug: Dictionary = {}
	if _progression != null and _progression.has_method("get_debug_snapshot"):
		progression_debug = _progression.call("get_debug_snapshot")
	return {
		"position": global_position,
		"health": hp,
		"controller": ctl,
		"alive": is_alive(),
		"control_enabled": _control_enabled,
		"progression": progression_debug,
		"level": get_level(),
		"stamina": get_stamina_fraction(),
		"weapons": weap,
		"skills": skl,
	}


func _combat_busy() -> bool:
	if _weapons != null:
		var inst: WeaponInstance = _weapons.call("active_instance")
		if inst != null:
			return inst.phase == WeaponInstance.PHASE_WINDUP or inst.phase == WeaponInstance.PHASE_RECOVERY
	return _attack != null and bool(_attack.call("is_attacking"))


func _cancel_combat() -> void:
	_attack_buffer.clear()
	if _weapons != null:
		_weapons.call("cancel_in_progress")
	if _attack != null:
		_attack.call("reset_attack_state")


func is_control_enabled() -> bool:
	return _control_enabled and not _is_dead


func _health_now() -> float:
	return _gameplay_time

## Hardened: validate player inputs each frame to prevent NaN propagation.
func _validated_delta(delta: float) -> float:
    if not is_finite(delta) or delta <= 0.0:
        return 0.0
    return clampf(delta, 0.0, 0.2)

