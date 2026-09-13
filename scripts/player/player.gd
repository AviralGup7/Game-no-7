extends Damageable
class_name Player

## Player authority root — gameplay truth is Player → WeaponManager → WeaponInstance
## → MeleeResolver/RangedResolver/ProjectilePool → DamagePayload → HealthComponent.
## Dash intent is captured in request_dodge() → DodgeController (stamina-checked,
## direction from input vs facing, interrupt-aware).
##
## TYPED COMPONENT ARCHITECTURE (see docs/ARCHITECTURE.md): every component is held
## as its concrete `class_name` type and called directly — no `has_method()` guards,
## no `.call()` string dispatch.
##   REQUIRED : HealthComponent, CharacterController, ProgressionComponent,
##              TargetingComponent, DodgeController, StaminaComponent,
##              ExperienceComponent, WeaponManager, StatusManager — verified once in
##              _ready through PlayerComponents; a scene variant that omits one fails
##              fast (push_error + assert) instead of degrading at runtime.
##   OPTIONAL : SkillController, PlayerFeedback, PlayerAudio (nullable by design).
## UI and future systems talk to THIS node through the stable command interface
## below; Player and EnemyBase share the Damageable combat protocol.
##
## Extracted collaborators: PlayerIntake (damage intake + riders), PlayerReactions
## (component signals → feedback/audio/re-emitted signals), PlayerRunCycle (run
## resets + starter kit), PlayerDebugView (snapshots) and PlayerComponents (the
## required-component scene contract).

## move_started/move_stopped are emitted by PlayerLocomotion and
## upgrade_applied by the progression component, both on this node's behalf:
## exempt exactly those three from the per-file usage check.
@warning_ignore("unused_signal")
signal move_started()
@warning_ignore("unused_signal")
signal move_stopped()
signal attack_started()
signal attack_finished()
signal damaged(result: DamageResult)
signal dodged()
signal died()
signal respawned()
@warning_ignore("unused_signal")
signal upgrade_applied(upgrade_id: StringName)
signal leveled_up(new_level: int)

const KILL_XP_BASE := 12.0
const KILL_XP_ELITE_BONUS := 18.0
## Matches the authored capsule in player.tscn (CapsuleShape3D.radius = 0.45).
const HIT_RADIUS := 0.45

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

var _locomotion := PlayerLocomotion.new()
var _build := PlayerBuild.new()
var _combat := PlayerCombat.new()
var _intake := PlayerIntake.new()
var _reactions := PlayerReactions.new()
var _run_cycle := PlayerRunCycle.new()
var _attack_buffer := AttackBuffer.new()
var _gameplay_time := 0.0
var _touch_fire_held := false
var _touch_aim := Vector2.ZERO

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
	_combat.bind(self, _weapons, _dodge, _controller, _stamina, _locomotion, _attack_buffer)
	_combat.buffer_seconds = attack_buffer_seconds
	_reactions.bind(self, _health, _progression, _feedback, _player_audio)
	_run_cycle.bind(_build, _health, _progression, _dodge, _stamina, _experience, _weapons, _status, _skills)
	_locomotion.move_started.connect(move_started.emit)
	_locomotion.move_stopped.connect(move_stopped.emit)
	_build.upgrade_applied.connect(upgrade_applied.emit)
	_health.set_time_source(_health_now)
	_health.health_changed.connect(_reactions.on_health_changed)
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	# Damage resistance: route progression resistance through the generic mitigation
	# seam (HealthComponent stays Player-agnostic).
	_health.set_mitigation_source(_mitigation_provider)
	_weapons.attack_resolved.connect(_reactions.on_weapon_attack_resolved)
	_experience.leveled_up.connect(_reactions.on_leveled_up)
	_dodge.bind_health(_health)
	_dodge.bind_motion(_controller, _progression)
	_dodge.dodged_started.connect(_reactions.on_dodge_started)
	_experience.bind_rewards(_health, _stamina, _skills)
	_stamina.bind_progression(_progression)
	_controller.bind_weapons(_weapons)
	if _skills != null:
		_skills.bind_systems(_experience, _status, _weapons, _health, _controller)
	# Bloodlust-style healing: a valid enemy kill heals the real HealthComponent.
	if not EventBus.enemy_killed.is_connected(_on_enemy_kill_heal):
		EventBus.enemy_killed.connect(_on_enemy_kill_heal)
	if not EventBus.enemy_killed.is_connected(_on_enemy_kill_xp):
		EventBus.enemy_killed.connect(_on_enemy_kill_xp)


func _exit_tree() -> void:
	_unbind_run_events()


## GAME_OVER freeze: the player node stays in WorldRoot for the summary
## camera, so kill-heal / kill-XP listeners would still fire on lingering
## deaths. Unbind those run-scoped feeds; HUD EventBus stays connected.
func isolate_run() -> void:
	_unbind_run_events()
	var build_effects := get_node_or_null("BuildEffects") as BuildEffects
	if build_effects != null:
		build_effects.isolate_run()
	if _player_audio != null:
		_player_audio.isolate_run()


func _unbind_run_events() -> void:
	if EventBus == null:
		return
	if EventBus.enemy_killed.is_connected(_on_enemy_kill_heal):
		EventBus.enemy_killed.disconnect(_on_enemy_kill_heal)
	if EventBus.enemy_killed.is_connected(_on_enemy_kill_xp):
		EventBus.enemy_killed.disconnect(_on_enemy_kill_xp)


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


## Fail fast when a REQUIRED component is missing from the scene variant (see
## PlayerComponents): the scene contract lives in one place, the resolution above
## stays here because it assigns this class's typed fields.
func _check_required_components() -> bool:
	return PlayerComponents.check_required(
		self, _health, _controller, _progression, _targeting, _dodge, _stamina, _experience, _weapons, _status
	)


func _mitigation_provider(amount: float, _payload: DamagePayload) -> float:
	return _intake.mitigation(self, amount)


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
		_tick_motion(delta, Vector2.ZERO)
		# Stunned: timers still advance so the stun itself can expire, but no input.
		_weapons.tick(delta)
		return
	if _touch_fire_held:
		_try_attack()
	if _locomotion.uses_actions():
		if not _touch_fire_held and Input.is_action_pressed("attack"):
			var over_ui := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and get_viewport().gui_get_hovered_control() != null
			# Ignore Android touch-to-mouse copies, without disabling physical
			# keyboard/gamepad fire when no touch/mouse button is held.
			var android_mouse := OS.has_feature("android") and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			if not over_ui and not android_mouse:
				_try_attack()
		if Input.is_action_just_pressed("reload"):
			request_reload()
		if Input.is_action_just_pressed("dodge"):
			request_dodge()
		if Input.is_action_just_pressed("switch_weapon"):
			request_weapon_switch()
		if InputMap.has_action("lock_on") and Input.is_action_just_pressed("lock_on"):
			request_lock_on()
	# Advance weapon timers every active step so hits resolve deterministically.
	_weapons.tick(delta)
	_attack_buffer.tick(delta, _try_attack)
	var move := _locomotion.gather()
	move *= _move_speed_factor()
	_tick_motion(delta, move)


## Dodge cooldown and normal movement share one path, including while stunned.
func _tick_motion(delta: float, move: Vector2) -> void:
	var fire_facing := -global_basis.z
	var dodge_owned := _dodge.is_dodging()
	_dodge.tick(delta)
	if not dodge_owned:
		_controller.tick(move, delta)
	# Holding FIRE keeps facing independent of the left movement stick.
	if _touch_fire_held and not dodge_owned:
		# Reuse the aim already selected this step; no second target/LOS scan.
		_controller.face_direction(fire_facing)
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


func get_move_intent() -> float:
	return _locomotion.gather().length()


func clear_move_input() -> void:
	_locomotion.clear_and_idle()


func request_attack() -> bool:
	_combat.buffer_seconds = attack_buffer_seconds
	return _combat.request_attack(_try_attack)


func _can_combat() -> bool:
	return not _is_dead and _control_enabled and not _is_stunned()


func _try_attack() -> bool:
	# AUTHORITATIVE: Player → WeaponManager → WeaponInstance → Resolver → DamagePayload.
	# WeaponManager is the single attack authority; without an equipped weapon
	# instance there is nothing to attack with (the legacy AttackController
	# fallback was removed).
	if not _can_combat() or _dodge.is_dodging():
		return false
	_aim_attack()
	if not _combat.try_start():
		return false
	_reactions.on_attack_started()
	return true


func _aim_attack() -> void:
	if not is_inside_tree():
		return
	_targeting.apply_settings()
	var inst := _weapons.active_instance()
	if inst != null:
		_targeting.max_target_range = inst.effective_range()
	# Touch aim uses the same camera-relative coordinates as the left stick.
	# A deliberate drag narrows assistance; desktop testing can use the mouse.
	var manual_touch := _touch_fire_held and _touch_aim.length_squared() > 0.0001
	_targeting.acquisition_cone_degrees = 20.0 if manual_touch else 65.0
	if manual_touch:
		_controller.face_direction(_controller.screen_to_world_dir(_touch_aim))
	elif not _touch_fire_held and not OS.has_feature("mobile") and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			var point := get_viewport().get_mouse_position()
			var plane := Plane(Vector3.UP, global_position.y + 1.0)
			var hit: Variant = plane.intersects_ray(camera.project_ray_origin(point), camera.project_ray_normal(point))
			if hit is Vector3:
				_controller.face_direction((hit as Vector3) - global_position)
	if _targeting.aim_assist_strength <= 0.0:
		_targeting.clear_sticky()
		return
	var nodes := get_tree().get_nodes_in_group("enemies")
	var target := _targeting.pick_best_target(nodes)
	if target is Node3D:
		_controller.face_direction((target as Node3D).global_position - global_position)


func get_aim_target() -> Node3D:
	return _targeting.get_sticky() as Node3D if _targeting != null else null


## One non-buffered shot request retained for command/test callers.
func request_held_fire() -> bool:
	return _try_attack()


func request_reload() -> bool:
	if not _can_combat() or _dodge.is_dodging():
		return false
	return _weapons.request_reload()


func request_lock_on() -> bool:
	if not _can_combat():
		return false
	var tree := get_tree()
	if tree == null:
		return false
	var rig := tree.get_first_node_in_group("camera_rig") as CameraRig
	if rig == null:
		return false
	return rig.toggle_lock_on()


func request_dodge() -> bool:
	var started := _combat.request_dodge()
	if started:
		dodged.emit()
	return started


func apply_damage(payload: DamagePayload) -> DamageResult:
	return _intake.apply_damage(self, payload)


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


func get_character_controller() -> CharacterController:
	return _controller


func get_weapon_manager() -> WeaponManager:
	return _weapons


func get_status_manager() -> StatusManager:
	return _status


func get_progression_component() -> ProgressionComponent:
	return _progression


func get_health_component() -> HealthComponent:
	return _health


func get_hit_radius() -> float:
	return HIT_RADIUS


func get_stamina_component() -> StaminaComponent:
	return _stamina


func get_experience_component() -> ExperienceComponent:
	return _experience


func get_build_snapshot() -> Dictionary:
	return PlayerDebugView.build_snapshot(self)


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
	_reactions.on_enemy_kill_heal()


## Every valid kill feeds XP (elites are worth extra).
func _on_enemy_kill_xp(enemy: Node, _archetype_id: StringName, _score: int, _currency: int) -> void:
	if _is_dead:
		return
	var award := KILL_XP_BASE
	if enemy is EnemyBase and (enemy as EnemyBase).is_elite():
		award += KILL_XP_ELITE_BONUS
	award *= _progression.get_stat(&"xp_multiplier_add", 1.0)
	add_xp(award)


func reset_for_new_run(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform
	# Run start is a teleport onto the arena's PlayerStart: snap the interpolation
	# snapshots too, or the hero glides in from wherever the body was authored.
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	_is_dead = false
	_control_enabled = false
	_clear_input()
	_run_cycle.reset_components()
	_run_cycle.equip_starter_kit()
	respawned.emit()


## Cycle the weapon loadout (Tab / Y / touch button). Returns false when there is
## no second weapon to switch to.
func request_weapon_switch() -> bool:
	return _combat.request_weapon_switch()


## Set the arena interior half-extent for movement/bounds clamping; -1 disables it.
func set_bounds(half: float) -> void:
	_locomotion.set_bounds(half)


func is_alive() -> bool:
	return not _is_dead


## ---------- Internal ----------

func _clear_input() -> void:
	_touch_fire_held = false
	_touch_aim = Vector2.ZERO
	_attack_buffer.clear()
	_locomotion.clear()


## Emit relays for PlayerReactions. Keeping the emit() calls in this file means the
## signal gate keeps arity-checking them as self-signal operations.
func _emit_attack_started() -> void:
	attack_started.emit()


func _emit_attack_finished() -> void:
	attack_finished.emit()


func _emit_leveled_up(new_level: int) -> void:
	leveled_up.emit(new_level)


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


func get_progression_snapshot() -> Dictionary:
	return PlayerDebugView.progression_snapshot(self)


func get_debug_snapshot() -> Dictionary:
	return PlayerDebugView.snapshot(self, _control_enabled)


func _cancel_combat() -> void:
	_combat.cancel()
	# Shared AttackBuffer: combat.cancel() already cleared it. Keep the local
	# writes so a failed _ready (unbound combat) still drops a pending press.
	_attack_buffer.clear()
	if _weapons != null:
		_weapons.cancel_in_progress()


func is_control_enabled() -> bool:
	return _control_enabled and not _is_dead


func _health_now() -> float:
	return _gameplay_time


## Touch UI publishes state, never shot ticks. Timing stays on the physics clock.
func set_touch_fire_input(held: bool, aim: Vector2) -> void:
	if not is_control_enabled() or not held or not aim.is_finite():
		_touch_fire_held = false
		_touch_aim = Vector2.ZERO
		return
	_touch_fire_held = true
	_touch_aim = aim.limit_length(1.0)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_touch_fire_held = false
		_touch_aim = Vector2.ZERO
