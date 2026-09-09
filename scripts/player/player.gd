extends Damageable
class_name Player

## Player authority root — gameplay truth is Player → WeaponManager → WeaponInstance
## → MeleeResolver/RangedResolver/ProjectilePool → DamagePayload → HealthComponent.
## AttackController/ComboChain are LEGACY ISOLATED fallbacks (see M3) and are NOT
## part of the authoritative path when WeaponManager is wired. Dash intent is
## captured in request_dodge() → DodgeController (stamina-checked, direction from
## input vs facing, interrupt-aware).
##
## TYPED COMPONENT ARCHITECTURE (see docs/ARCHITECTURE.md):
## Every component is held as its concrete `class_name` type and called directly —
## no `has_method()` guards, no `.call()` string dispatch. Components split into
## REQUIRED (verified once in _ready; a scene variant that omits one fails fast
## with a push_error + assert instead of silently degrading at runtime) and
## OPTIONAL (genuinely droppable presentation/legacy pieces, held as nullable
## typed references).
##   REQUIRED : HealthComponent, CharacterController, ProgressionComponent,
##              TargetingComponent, DodgeController, StaminaComponent,
##              ExperienceComponent, WeaponManager, StatusManager
##   OPTIONAL : SkillController, PlayerFeedback, PlayerAudio, AttackController
## Coordinates movement, combat, health, death, and external commands for the
## player. UI and future systems talk to THIS node through the stable command
## interface below; Player and EnemyBase share the Damageable combat protocol.

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

## REQUIRED components (see _check_required_components): resolved once in _ready
## and never null afterwards — direct calls, no guards.
var _controller: CharacterController = null
var _health: HealthComponent = null
var _progression: ProgressionComponent = null
var _targeting: TargetingComponent = null
var _dodge: DodgeController = null
var _stamina: StaminaComponent = null
var _experience: ExperienceComponent = null
var _weapons: WeaponManager = null
var _status: StatusManager = null

## OPTIONAL components: genuinely droppable, nullable by design.
var _skills: SkillController = null
var _feedback: PlayerFeedback = null
var _player_audio: PlayerAudio = null
var _attack: AttackController = null

var _locomotion := PlayerLocomotion.new()
var _build := PlayerBuild.new()
var _attack_buffer := AttackBuffer.new()
var _gameplay_time := 0.0

@export var attack_buffer_seconds: float = 0.18

@export var walk_speed: float = 6.0
@export var max_health: float = 100.0


func _ready() -> void:
	add_to_group("player")
	_resolve_components()
	if not _check_required_components():
		return
	_locomotion.bind(self, _dodge, _controller)
	_build.bind(_health, _progression, _controller, _stamina, _weapons, _skills, walk_speed, max_health)
	_locomotion.move_started.connect(move_started.emit)
	_locomotion.move_stopped.connect(move_stopped.emit)
	_build.upgrade_applied.connect(upgrade_applied.emit)
	_health.set_time_source(_health_now)
	_health.health_changed.connect(_on_health_changed)
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	# Damage resistance: route progression resistance through the generic mitigation
	# seam (HealthComponent stays Player-agnostic).
	_health.set_mitigation_source(_mitigation_provider)
	if _attack != null:
		_attack.attack_started.connect(_on_attack_started)
		_attack.attack_finished.connect(_on_attack_finished)
		_attack.attack_hit.connect(_on_attack_hit)
	_weapons.attack_resolved.connect(_on_weapon_attack_resolved)
	_experience.leveled_up.connect(_on_leveled_up)
	_dodge.bind_health(_health)
	_dodge.dodged_started.connect(_on_dodge_started)
	# Bloodlust-style healing: a valid enemy kill heals the real HealthComponent.
	if not EventBus.enemy_killed.is_connected(_on_enemy_kill_heal):
		EventBus.enemy_killed.connect(_on_enemy_kill_heal)
	if not EventBus.enemy_killed.is_connected(_on_enemy_kill_xp):
		EventBus.enemy_killed.connect(_on_enemy_kill_xp)


## Resolve every component reference ONCE, as its concrete type. A wrong script
## on a child node yields null here (the `as` cast never lies), which the
## required-component check then reports by name.
func _resolve_components() -> void:
	_controller = get_node_or_null("CharacterController") as CharacterController
	_health = get_node_or_null("HealthComponent") as HealthComponent
	_progression = get_node_or_null("ProgressionComponent") as ProgressionComponent
	_targeting = get_node_or_null("TargetingComponent") as TargetingComponent
	_dodge = get_node_or_null("DodgeController") as DodgeController
	_stamina = get_node_or_null("StaminaComponent") as StaminaComponent
	_experience = get_node_or_null("ExperienceComponent") as ExperienceComponent
	_weapons = get_node_or_null("WeaponManager") as WeaponManager
	_status = get_node_or_null("StatusManager") as StatusManager
	_skills = get_node_or_null("SkillController") as SkillController
	_feedback = get_node_or_null("PlayerFeedback") as PlayerFeedback
	_player_audio = get_node_or_null("PlayerAudio") as PlayerAudio
	_attack = get_node_or_null("AttackController") as AttackController


## Fail fast when a REQUIRED component is missing from the scene variant.
## Debug/test builds assert immediately (the bug is caught the moment the scene
## loads); release builds log once and disable processing rather than silently
## degrading into a half-functional player.
func _check_required_components() -> bool:
	var missing := PackedStringArray()
	if _health == null:
		missing.append("HealthComponent")
	if _controller == null:
		missing.append("CharacterController")
	if _progression == null:
		missing.append("ProgressionComponent")
	if _targeting == null:
		missing.append("TargetingComponent")
	if _dodge == null:
		missing.append("DodgeController")
	if _stamina == null:
		missing.append("StaminaComponent")
	if _experience == null:
		missing.append("ExperienceComponent")
	if _weapons == null:
		missing.append("WeaponManager")
	if _status == null:
		missing.append("StatusManager")
	if missing.is_empty():
		return true
	push_error("Player requires components missing from its scene: %s — these are not optional; fix the scene variant of player.tscn." % ", ".join(missing))
	assert(false, "Player missing required components: %s" % ", ".join(missing))
	set_physics_process(false)
	return false


## Mitigation provider for the generic HealthComponent: computes post-resistance
## damage from the player's progression-derived damage_resistance_add.
func _mitigation_provider(amount: float, _payload: DamagePayload) -> float:
	var resistance := clampf(_progression.get_stat(&"damage_resistance_add", 0.0), 0.0, 1.0)
	return maxf(amount * (1.0 - resistance), 0.0)


func _physics_process(delta: float) -> void:
	# Runtime assertion replacing the dead _validated_delta helper: a non-finite
	# delta (NaN/inf from a broken clock or manual call) must never feed gameplay
	# timers, motion, or the health clock.
	if not is_finite(delta):
		return
	if not _control_enabled or _is_dead:
		return
	_gameplay_time += maxf(delta, 0.0)
	if _is_stunned():
		_cancel_combat()
		velocity.x = 0.0
		velocity.z = 0.0
		var dodge_moving := _dodge.is_dodging()
		_dodge.tick(delta)
		if not dodge_moving:
			_controller.tick(Vector2.ZERO, delta)
		_locomotion.track(Vector2.ZERO)
		_locomotion.clamp_to_bounds()
		# Stunned: timers still advance so the stun itself can expire, but no input.
		if _attack != null:
			_attack.advance(delta)
		_weapons.tick(delta)
		return
	if _locomotion.uses_actions():
		if Input.is_action_just_pressed("attack"):
			request_attack()
		if Input.is_action_just_pressed("dodge"):
			request_dodge()
		if Input.is_action_just_pressed("switch_weapon"):
			request_weapon_switch()
	# Advance attack timers every active step so hits resolve deterministically.
	if _attack != null:
		_attack.advance(delta)
	_weapons.tick(delta)
	_attack_buffer.tick(delta, _try_attack)
	var move := _locomotion.gather()
	move *= _move_speed_factor()
	# The dodge is ticked EVERY step so its cooldown can wind down (a cooldown that
	# only ran mid-dodge would lock the player out forever).
	var dodge_owned_motion := _dodge.is_dodging()
	_dodge.tick(delta)
	# Normal locomotion is owned by the CharacterController unless a dodge is mid-flight.
	if dodge_owned_motion:
		pass  # DodgeController owns motion (burst + recovery) this step
	else:
		_controller.tick(move, delta)
	_locomotion.track(move)
	_locomotion.clamp_to_bounds()


func _is_stunned() -> bool:
	return _status.is_stunned()


func _move_speed_factor() -> float:
	return clampf(_status.move_speed_factor(), 0.0, 2.0)


func set_control_enabled(enabled: bool) -> void:
	_control_enabled = enabled
	if _skills != null:
		_skills.set_enabled(enabled)
	_weapons.set_attacks_enabled(enabled)
	if _attack != null:
		_attack.set_attacks_enabled(enabled)
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
	# AUTHORITATIVE: Player → WeaponManager → WeaponInstance → Resolver → DamagePayload.
	# Legacy AttackController is isolated fallback only when no WeaponInstance is equipped (headless).
	if not _can_combat() or _dodge.is_dodging():
		return false
	if _weapons.active_instance() != null:
		if _weapons.request_attack() <= 0:
			return false
		_aim_attack()
		_on_attack_started()
		return true
	# Legacy fallback — isolated, not authoritative; kept for minimal test scenes without WeaponManager wiring.
	if _attack != null:
		var started := _attack.request_attack()
		if started:
			_aim_attack()
		return started
	return false


func _aim_attack() -> void:
	if not is_inside_tree():
		return
	var nodes := get_tree().get_nodes_in_group("enemies")
	var target := _targeting.pick_best_target(nodes)
	if target is Node3D:
		_controller.face_direction((target as Node3D).global_position - global_position)


func request_dodge() -> bool:
	if not _can_combat():
		return false
	if not _dodge.is_ready():
		return false
	if not _dodge.can_interrupt_attack and _combat_busy():
		return false
	var cost := maxf(_dodge.stamina_cost, 0.0)
	if not try_spend_stamina(cost):
		return false
	# Direction: prefer the current movement input (camera-relative); fall back to the
	# body's facing (world -Z) so a standing dodge always goes somewhere.
	var dir := -global_basis.z
	var move := _locomotion.gather()
	var world := _controller.screen_to_world_dir(move)
	if world.length_squared() > 0.0001:
		dir = world
	var started := _dodge.request(dir)
	if started:
		_cancel_combat()
		_controller.face_direction(dir)
		dodged.emit()
	else:
		# Refund the stamina when the dodge itself refused (cooldown, mid-air...).
		restore_stamina(cost)
	return started


func apply_damage(payload: DamagePayload) -> DamageResult:
	var result := DamageResult.new()
	if _is_dead:
		result.ignored_reason = DamageResult.IGNORE_DEAD
		return result
	# Do not consume a shield for payloads HealthComponent will reject before
	# intake (malformed, invulnerable, or already-dead). Accepted hits are then
	# reduced by status mitigation/shields exactly once.
	if payload == null or not payload.is_valid() or _health.is_invulnerable():
		return _health.take_damage(payload)
	var final_payload := _apply_status_intake(payload)
	var taken := _health.take_damage(final_payload)
	if taken.accepted and taken.final_amount > 0.0:
		_apply_payload_status(payload, taken)
	return taken


## Incoming weapon/projectile riders: apply payload effects after an accepted hit.
func _apply_payload_status(payload: DamagePayload, result: DamageResult = null) -> void:
	if payload == null or payload.status_effects.is_empty():
		return
	var applied := _status.apply_effects(payload.status_effects, payload.source)
	if result != null:
		for raw_id in applied:
			if int(applied[raw_id]) > 0:
				result.status_effects_applied.append(StringName(String(raw_id)))


## Scale + shield an incoming payload through the StatusManager (guard shields,
## shock vulnerability...). Returns the original payload when no manager exists.
func _apply_status_intake(payload: DamagePayload) -> DamagePayload:
	if payload == null:
		return payload
	var factor := _status.incoming_damage_factor()
	var amount := payload.amount * factor
	amount = _status.absorb_direct(amount)
	if is_equal_approx(amount, payload.amount):
		return payload
	return payload.with_amount(amount)


## ---------- Stamina / XP / skill / weapon / status facades ----------

func try_spend_stamina(amount: float) -> bool:
	return _stamina.try_spend(amount)


func restore_stamina(amount: float) -> void:
	_stamina.restore(amount)


func get_stamina_fraction() -> float:
	return _stamina.get_fraction()


func add_xp(amount: float) -> int:
	return _experience.add_xp(amount)


func get_level() -> int:
	return _experience.get_level()


func get_xp_fraction() -> float:
	return _experience.get_fraction_into_level()


func request_skill(slot: int) -> bool:
	if _is_dead or not _control_enabled:
		return false
	if _skills != null:
		return _skills.try_cast_slot(slot)
	return false


## Typed component accessors (the old versions returned Node). UI and systems
## use these instead of get_node_or_null() string lookups into the player scene.

func get_skill_controller() -> SkillController:
	return _skills


func get_weapon_manager() -> WeaponManager:
	return _weapons


func get_status_manager() -> StatusManager:
	return _status


func get_progression_component() -> ProgressionComponent:
	return _progression


func get_health_component() -> HealthComponent:
	return _health


func get_stamina_component() -> StaminaComponent:
	return _stamina


func get_experience_component() -> ExperienceComponent:
	return _experience


## Serializable build mirror consumed by RunState. Live components remain the
## source of truth; this method only reads their stable content ids and tags.
func get_build_snapshot() -> Dictionary:
	var weapons: Array = _weapons.get_loadout_ids()
	var skills: Array = [] if _skills == null else _skills.get_assigned_skill_ids()
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
		var stacks: Dictionary = _progression.get_upgrade_stack_snapshot()
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
	return _status.apply_effects(effect_ids, source)


func cleanse_status(only_harmful: bool = true) -> int:
	return _status.cleanse_all(only_harmful)


## Apply an upgrade through the runtime ProgressionComponent (see PlayerBuild).
func apply_upgrade(upgrade_id: StringName) -> bool:
	return _build.apply_upgrade(upgrade_id)


## Rebuild all runtime facades after an external permanent/meta modifier is applied.
func rebuild_derived_stats() -> void:
	_build.rebuild_derived_stats()


## Bloodlust-style heal: valid enemy kills heal while the player is alive.
func _on_enemy_kill_heal(_enemy: Node, _archetype_id: StringName, _score: int, _currency: int) -> void:
	if _is_dead:
		return
	var heal_amount := _progression.get_stat(&"healing_on_kill", 0.0)
	if heal_amount > 0.0:
		_health.heal(heal_amount)


## Every valid kill feeds XP (elites are worth extra).
func _on_enemy_kill_xp(enemy: Node, _archetype_id: StringName, _score: int, _currency: int) -> void:
	if _is_dead:
		return
	var award := KILL_XP_BASE
	if enemy is EnemyBase and (enemy as EnemyBase).is_elite():
		award += KILL_XP_ELITE_BONUS
	award *= _progression.get_stat(&"xp_multiplier_add", 1.0)
	add_xp(award)


func _on_leveled_up(new_level: int) -> void:
	leveled_up.emit(new_level)
	# The ExperienceComponent owns the level reward (heal + stamina) and already
	# plays the `level_up` sting; the player owns the banner. A second stacked
	# chime here only muddied the celebration, so this plays nothing.
	if EventBus != null:
		EventBus.announcement.emit(&"level_up", "Level %d!" % new_level, &"info")


func _on_weapon_attack_resolved(weapon_id: StringName, hit_count: int, was_crit: bool) -> void:
	attack_finished.emit()
	if hit_count > 0 and _feedback != null:
		_feedback.play_impact_feedback(was_crit)


func reset_for_new_run(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	_is_dead = false
	_control_enabled = false
	_clear_input()
	# Reset progression FIRST so health derives from the fresh (empty) run modifiers.
	_progression.reset()
	_health.reset(_build.derived_max_health())
	if _attack != null:
		_attack.reset_attack_state()
	_dodge.reset()
	_stamina.reset_for_new_run()
	_experience.reset_for_new_run()
	if _skills != null:
		_skills.reset_for_new_run()
	_weapons.reset_for_new_run()
	_status.clear_all()
	_build.rebuild_derived_stats()
	_equip_starter_kit()
	respawned.emit()


## Cycle the weapon loadout (Tab / Y / touch button). Returns false when there is
## no second weapon to switch to.
func request_weapon_switch() -> bool:
	if not _can_combat() or _dodge.is_dodging():
		return false
	var switched := _weapons.cycle_weapon()
	if switched:
		_attack_buffer.clear()
	return switched


## Starter kit: daily loadout (or Gladius) in slot 0 + the first skill unlocked
## (all tolerant when the ContentRegistry is unavailable, e.g. headless direct use).
## Slot 1 + locked skills are filled by Main from owned meta unlocks after reset.
func _equip_starter_kit() -> void:
	_weapons.equip_by_id(_starter_weapon_id(), 0, true)
	if _skills != null:
		_skills.assign_skill_by_id(&"seismic_slam", 0, true)
		_skills.assign_skill_by_id(&"bladestorm", 1, false)
		_skills.assign_skill_by_id(&"phantom_rush", 2, false)


func _starter_weapon_id() -> StringName:
	if GameRoot != null:
		return GameRoot.get_daily_weapon()
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
	if _feedback != null:
		_feedback.play_hit_feedback()
	if not result.target_died and _player_audio != null:
		_player_audio.play_hurt()


func _on_died() -> void:
	if _is_dead:
		return
	_is_dead = true
	set_control_enabled(false)
	_cancel_combat()
	_dodge.reset()
	died.emit()
	EventBus.player_died.emit()
	if _player_audio != null:
		_player_audio.play_death()
	GameRoot.request_game_over()


func _on_attack_started() -> void:
	attack_started.emit()
	if _feedback != null:
		_feedback.play_attack_feedback()
	if _player_audio != null:
		_player_audio.play_attack()


func _on_attack_finished() -> void:
	attack_finished.emit()


func _on_dodge_started() -> void:
	if _player_audio != null:
		_player_audio.play_dodge()
	if _feedback != null:
		_feedback.play_dodge_feedback()


func _on_attack_hit(target: Node, result: DamageResult) -> void:
	attack_hit.emit(target, result)
	if result.accepted and _feedback != null:
		_feedback.play_impact_feedback(result.was_critical)


func get_progression_snapshot() -> Dictionary:
	return _progression.get_debug_snapshot()


func get_debug_snapshot() -> Dictionary:
	return {
		"position": global_position,
		"health": _health.get_debug_snapshot(),
		"controller": _controller.get_debug_snapshot(),
		"alive": is_alive(),
		"control_enabled": _control_enabled,
		"progression": _progression.get_debug_snapshot(),
		"level": get_level(),
		"stamina": get_stamina_fraction(),
		"weapons": _weapons.get_debug_snapshot(),
		"skills": {} if _skills == null else _skills.get_debug_snapshot(),
	}


func _combat_busy() -> bool:
	var inst := _weapons.active_instance()
	if inst != null:
		return inst.phase == WeaponInstance.PHASE_WINDUP or inst.phase == WeaponInstance.PHASE_RECOVERY
	if _attack != null:
		return _attack.is_attacking()
	return false


func _cancel_combat() -> void:
	_attack_buffer.clear()
	_weapons.cancel_in_progress()
	if _attack != null:
		_attack.reset_attack_state()


func is_control_enabled() -> bool:
	return _control_enabled and not _is_dead


func _health_now() -> float:
	return _gameplay_time
