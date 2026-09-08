extends CharacterBody3D
class_name EnemyBase

## Reusable enemy base. Owns lifecycle, damage intake, idempotent death + exactly-once
## score payload (Phase 2 guarantees preserved), and the AI behaviour: a state machine
## (Idle/Chase/Attack/Hurt/Dead/Ranged/Dash/Fuse) driving movement intent, integrated
## by EnemyLocomotion (gravity/knockback/clamp/stall), steered by EnemyNavigator
## (navmesh), and striking through EnemyStriker (guarded melee + dash strikes).
## Resistance-aware knockback and arena-bound clamping included; attacks damage the
## player through the existing HealthComponent/apply_damage interface.
##
## Command surface for states/controllers (states NEVER reach into internals):
##   set_desired_move / face_target / face_direction / get_navigation_direction
##   set_move_override / clear_move_override   (telegraphs, charges, recoveries)
##   set_poise_guard                            (windup interruption budget)
##   perform_enemy_attack / perform_dash_strike / detonate_self
##   try_begin_dash                             (cooldown-gated dash entry)
##   state_machine_change_to / force_state / get_state
## EventBus/AudioManager are resolved lazily through the tree so the same code
## runs in-game and in the autoload-free headless test harness.

signal initialized(archetype_id: StringName)
signal state_changed(previous_state: StringName, current_state: StringName)
signal damaged(result: DamageResult)
signal died()
signal attack_started()
signal attack_hit(target: Node, result: DamageResult)
signal despawn_requested(enemy: Node)

const TARGET_GROUP := "enemies"
## Poise damage decays per second while the guard is up.
const POISE_DECAY_PER_SECOND := 25.0

var _archetype_id: StringName = &"uninitialized"
var _config: EnemyConfig = null
var _alive := false
var _death_handled := false
var _score_value: int = 0
var _currency_value: int = 0
var _run_seed: int = 0

var _health: Node = null
var _feedback: Node = null
var _audio: Node = null
var _machine: EnemyStateMachine = null
var _target: Node3D = null
var _locomotion := EnemyLocomotion.new()
var _navigator := EnemyNavigator.new()
var _striker := EnemyStriker.new()

## Movement intent produced by the current state.
var desired_dir := Vector3.ZERO
var desired_speed := 0.0

var _ai_enabled := true

## Per-run difficulty scaling applied at spawn without mutating the shared config.
var _hp_scale := 1.0
var _damage_scale := 1.0
var _speed_scale := 1.0

## Movement override: while > 0 the override wins over whatever the AI states ask
## for. Used by dash charges, boss telegraphs/charges/recovery windows.
var _move_override_dir := Vector3.ZERO
var _move_override_speed := 0.0
var _move_override_time := 0.0

## Poise guard: while armed (windups), accepted damage accumulates instead of
## forcing Hurt until the config's poise budget breaks.
var _poise_guard := false
var _poise_damage := 0.0

## Dash cooldown owned by the host so the Chase state can gate entry without
## reaching into the dash state instance.
var _dash_cooldown_left := 0.0

## Deterministic per-enemy personality: approach offset keeps packs from stacking
## on the exact same spot behind the player.
var _spawn_serial := 0
var _approach_offset := Vector3.ZERO

## Elite affix cache (set via set_elite; queried by cadence/vampiric hooks).
var _elite_affixes: Array[StringName] = []

var _event_bus: Node = null
var _event_bus_resolved := false


func _ready() -> void:
	add_to_group(TARGET_GROUP)
	_health = get_node_or_null("HealthComponent")
	_feedback = get_node_or_null("EnemyFeedback")
	_audio = get_node_or_null("EnemyAudio")
	_machine = get_node_or_null("EnemyStateMachine") as EnemyStateMachine
	_navigator.bind(get_node_or_null("NavigationAgent3D") as NavigationAgent3D)
	if _health != null:
		_health.damaged.connect(_on_damaged)
		_health.died.connect(_on_died)


## Lazy, cached autoload lookup: identical to a direct reference in-game, null-safe
## under the bare headless test SceneTree.
func _eb() -> Node:
	if not _event_bus_resolved:
		_event_bus_resolved = true
		if is_inside_tree():
			_event_bus = get_node_or_null("/root/EventBus")
	return _event_bus


func set_ai_enabled(enabled: bool) -> void:
	_ai_enabled = enabled
	if not enabled:
		desired_dir = Vector3.ZERO
		desired_speed = 0.0
		velocity.x = 0.0
		velocity.z = 0.0


func _physics_process(delta: float) -> void:
	if _config == null or not _alive or not _ai_enabled:
		return
	_decay_timers(delta)
	if _is_status_stunned():
		# Stunned: no AI, no intent; gravity + knockback decay still run.
		desired_dir = Vector3.ZERO
		desired_speed = 0.0
		_locomotion.integrate(self, Vector3.ZERO, 0.0, 1.0, delta, false)
		return
	if _machine != null:
		_machine.physics_update(delta)
	var dir := desired_dir
	var speed := desired_speed
	if _move_override_time > 0.0:
		dir = _move_override_dir
		speed = _move_override_speed
	_locomotion.integrate(self, dir, speed, _status_speed_factor(), delta)


func _decay_timers(delta: float) -> void:
	if _move_override_time > 0.0:
		_move_override_time = maxf(_move_override_time - delta, 0.0)
	if _dash_cooldown_left > 0.0:
		_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
	if _poise_guard and _poise_damage > 0.0:
		_poise_damage = maxf(_poise_damage - POISE_DECAY_PER_SECOND * delta, 0.0)


## ---------- Stable command interface (Phase 2 preserved) ----------

func initialize(config: EnemyConfig, target: Node3D, run_seed: int = 0) -> void:
	if config == null:
		push_warning("EnemyBase.initialize received null config")
		return
	_config = config
	_archetype_id = config.archetype_id
	_score_value = config.score_value
	_currency_value = config.currency_value
	_run_seed = run_seed
	_target = target
	_alive = true
	_death_handled = false
	_locomotion.reset()
	_locomotion.configure(config.acceleration, _locomotion_bounds(), config.bounds_radius)
	desired_dir = Vector3.ZERO
	desired_speed = 0.0
	_move_override_time = 0.0
	_poise_guard = false
	_poise_damage = 0.0
	_dash_cooldown_left = 0.0
	if _health != null and _health.has_method("reset"):
		_health.call("reset", config.max_health)
	if _feedback != null and _feedback.has_method("recolor"):
		_feedback.call("recolor", config.color_tint)
	_apply_visual_scale(config.visual_scale)
	# Presentation hook (Agent 4): mount the archetype's approved model under
	# VisualRoot/CharacterModel. No gameplay effect; primitives remain if absent.
	if CharacterVisuals.has_model(config.archetype_id):
		CharacterVisuals.mount(self, config.archetype_id)
	if _machine != null:
		_machine.force_state(&"idle")
	_navigator.reset(target)
	initialized.emit(_archetype_id)


func apply_damage(payload: DamagePayload) -> DamageResult:
	var result := DamageResult.new()
	if _health == null or not _health.has_method("take_damage"):
		result.ignored_reason = &"no_health_component"
		return result
	if not _alive:
		result.ignored_reason = DamageResult.IGNORE_DEAD
		return result
	# Status mitigation/shields are an intake stage, but do not consume a shield
	# for malformed or invulnerable hits that HealthComponent will reject.
	var final_payload := payload
	if payload != null and payload.is_valid() and not (_health.has_method("is_invulnerable") and bool(_health.call("is_invulnerable"))):
		final_payload = _apply_status_intake(payload)
	var taken: Variant = _health.call("take_damage", final_payload)
	if taken is DamageResult:
		var res := taken as DamageResult
		_on_damage_applied(res, payload)
		# Invulnerability, shields and dead-state rejection must not grant a
		# status proc. Only an accepted hit is allowed to advance a build synergy.
		if res.accepted and res.final_amount > 0.0:
			_apply_payload_status(payload, res)
		return res
	result.ignored_reason = &"invalid_result"
	return result


## Projectile/melee riders: apply the payload's status effects to our manager.
func _apply_payload_status(payload: DamagePayload, result: DamageResult = null) -> void:
	if payload == null or payload.status_effects.is_empty():
		return
	var sm := _status_node()
	if sm != null and sm.has_method("apply_effects"):
		var applied: Variant = sm.call("apply_effects", payload.status_effects, payload.source)
		if result != null and applied is Dictionary:
			for raw_id in applied:
				if int(applied[raw_id]) > 0:
					result.status_effects_applied.append(StringName(String(raw_id)))


func _apply_status_intake(payload: DamagePayload) -> DamagePayload:
	var sm := _status_node()
	if sm == null or payload == null:
		return payload
	var factor := 1.0
	if sm.has_method("incoming_damage_factor"):
		factor = float(sm.call("incoming_damage_factor"))
	var amount := payload.amount * factor
	if sm.has_method("absorb_direct"):
		amount = float(sm.call("absorb_direct", amount))
	if is_equal_approx(amount, payload.amount):
		return payload
	return payload.with_amount(amount)


func force_state(state_id: StringName) -> void:
	if _machine != null:
		_machine.force_state(state_id)


## Regular (non-forcing) transition facade used by AI states; refused if already current.
func state_machine_change_to(state_id: StringName) -> void:
	if _machine != null:
		_machine.change_to(state_id)


func get_state() -> StringName:
	if _machine == null:
		return &""
	return _machine.get_current()


func is_alive() -> bool:
	return _alive


func get_archetype_id() -> StringName:
	return _archetype_id


func get_config() -> EnemyConfig:
	return _config


## Set arena-bound half extent; -1 disables the clamp.
func set_bounds(half: float) -> void:
	_locomotion.set_bounds(half)


func set_velocity_flat(flat: Vector3) -> void:
	velocity.x = flat.x
	velocity.z = flat.z


## Apply wave difficulty scaling (>=1.0). Resets health to the scaled maximum.
func apply_difficulty(hp_scale: float, damage_scale: float, speed_scale: float) -> void:
	_hp_scale = maxf(hp_scale, 1.0)
	_damage_scale = maxf(damage_scale, 1.0)
	_speed_scale = maxf(speed_scale, 1.0)
	if _health != null and _health.has_method("reset"):
		_health.call("reset", _scaled_max_health())


func _scaled_max_health() -> float:
	var cfg := _config
	var base := cfg.max_health if cfg != null else 1.0
	return base * _hp_scale


func get_effective_speed() -> float:
	var cfg := _config
	var base := cfg.move_speed if cfg != null else 2.0
	return base * _speed_scale


func get_effective_attack_damage() -> float:
	var cfg := _config
	var base := cfg.attack_damage if cfg != null else 5.0
	return base * _damage_scale


## Attack cadence: base cooldown, sped up for wounded FRENZIED elites. Never
## mutates the shared config.
func get_effective_attack_cooldown() -> float:
	var cfg := _config
	var base := cfg.attack_cooldown if cfg != null else 1.2
	if EliteAffix.FRENZIED in _elite_affixes and get_health_fraction() < EliteAffix.FRENZIED_HP_TRIGGER:
		base *= EliteAffix.FRENZIED_COOLDOWN_MULT
	return base


func get_move_target() -> Node3D:
	if _target == null or not is_instance_valid(_target):
		return null
	if _target.has_method("is_alive") and not bool(_target.call("is_alive")):
		return null
	return _target


func set_desired_move(dir: Vector3, speed: float) -> void:
	desired_dir = dir
	desired_speed = maxf(speed, 0.0)


## ---------- Movement override (telegraphs / charges / recoveries) ----------

## While active, the override replaces whatever the AI states request. Pass a
## zero dir + zero speed to root the enemy in place (boss telegraph/recovery).
func set_move_override(dir: Vector3, speed: float, duration: float) -> void:
	_move_override_dir = dir
	_move_override_speed = maxf(speed, 0.0)
	_move_override_time = maxf(duration, 0.0)


func clear_move_override() -> void:
	_move_override_time = 0.0


func is_move_overridden() -> bool:
	return _move_override_time > 0.0


## ---------- Poise (heavy/boss windups are not interrupted by chip damage) ----

func set_poise_guard(active: bool) -> void:
	_poise_guard = active
	if not active:
		_poise_damage = 0.0


func is_poise_guarding() -> bool:
	return _poise_guard


## ---------- Dash command (cooldown-gated entry from Chase) ----------

func try_begin_dash() -> bool:
	var cfg := _config
	if cfg == null or cfg.dash_trigger_range <= 0.0:
		return false
	if _dash_cooldown_left > 0.0 or not _alive:
		return false
	_dash_cooldown_left = cfg.dash_cooldown
	return true


func is_dash_ready() -> bool:
	return _dash_cooldown_left <= 0.0


## Charge speed honoring wave/mutator speed scaling (config never mutated).
func get_effective_dash_speed() -> float:
	var cfg := _config
	var base := cfg.dash_speed if cfg != null else 12.0
	return base * _speed_scale


## ---------- Spawn personality (deterministic per run) ----------

func set_spawn_serial(serial: int) -> void:
	_spawn_serial = maxi(serial, 0)
	_roll_approach_offset()


func _roll_approach_offset() -> void:
	if _config == null:
		return
	var rng := RngService.make_generator(_run_seed, RngService.STREAM_AI + _spawn_serial * 7 + 3)
	var angle := rng.randf_range(-PI, PI)
	var radius := rng.randf_range(0.0, 1.6)
	_approach_offset = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


## The point this enemy actually tries to stand at: the target position nudged by
## its personal offset, so packs fan out instead of stacking on one pixel.
func get_approach_point(point: Vector3) -> Vector3:
	return point + _approach_offset


## ---------- Navigation / facing ----------

func target_in_attack_range(target: Node3D) -> bool:
	if target == null:
		return false
	var cfg := _config
	var range_val := cfg.attack_range if cfg != null else 1.5
	return global_position.distance_to(target.global_position) <= range_val


func face_direction(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	var visual := get_node_or_null("VisualRoot") as Node3D
	if visual == null:
		return
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	visual.look_at(visual.global_position + flat, Vector3.UP)


func face_target(target: Node3D) -> void:
	if target == null:
		return
	face_direction(target.global_position - global_position)


## Navigation-aware steering (see EnemyNavigator): prefers the navmesh path when
## usable, otherwise falls back to the caller's direct direction.
func get_navigation_direction(fallback: Vector3) -> Vector3:
	var interval := _config.navigation_target_update_interval if _config != null else 0.2
	return _navigator.direction(global_position, get_move_target(), fallback, interval)


## ---------- Attacks ----------

## Controlled melee attack against the current target (see EnemyStriker). Returns
## true when a hit lands; damage is applied exactly once per call.
func perform_enemy_attack() -> bool:
	return _striker.execute(self)


## Dash-charge contact hit (see EnemyStriker.execute_dash): larger radius, scaled
## damage, exactly one hit per charge (the dash state calls this once).
func perform_dash_strike(contact_radius: float) -> bool:
	return _striker.execute_dash(self, contact_radius)


## Lethal self-damage routed through the HealthComponent so the normal exactly-once
## death path fires (score payload, despawn, death-blast dispatch in SpawnManager).
func detonate_self() -> void:
	if not _alive or _health == null or not _health.has_method("take_damage"):
		return
	var payload := DamagePayload.new()
	payload.amount = _current_health() + 999.0
	payload.source = self
	payload.source_id = _archetype_id
	payload.damage_type = &"explosion"
	_health.call("take_damage", payload)


func _current_health() -> float:
	if _health != null and _health.has_method("get_current"):
		return maxf(float(_health.call("get_current")), 0.0)
	return 0.0


## ---------- Feedback / audio hooks (tolerant when children are absent) ----------

func play_attack_sound() -> void:
	if _audio != null and _audio.has_method("play_attack"):
		_audio.call("play_attack")


func play_spawn_sound() -> void:
	if _audio != null and _audio.has_method("play_spawn"):
		_audio.call("play_spawn")


func play_windup_sound() -> void:
	if _audio != null and _audio.has_method("play_windup"):
		_audio.call("play_windup")


func play_dash_sound() -> void:
	if _audio != null and _audio.has_method("play_dash"):
		_audio.call("play_dash")


func play_explosion_sound() -> void:
	if _audio != null and _audio.has_method("play_explosion"):
		_audio.call("play_explosion")


## Telegraph flash (melee windups, dash windups, fuses, boss tells).
func play_telegraph_feedback() -> void:
	if _feedback != null and _feedback.has_method("play_telegraph"):
		_feedback.call("play_telegraph")


func _locomotion_bounds() -> float:
	return _locomotion.get_bounds()


func _apply_visual_scale(scale_factor: float) -> void:
	var visual := get_node_or_null("VisualRoot") as Node3D
	if visual != null and scale_factor > 0.0:
		visual.scale = Vector3.ONE * scale_factor


func note_hurt_started() -> void:
	pass


## ---------- Damage / death (Phase 2 exactly-once preserved) ----------

func _on_damage_applied(result: DamageResult, payload: DamagePayload) -> void:
	if not result.accepted:
		return
	var cfg := _config
	var resistance := cfg.knockback_resistance if cfg != null else 0.0
	var resisted := payload.knockback * (1.0 - clampf(resistance, 0.0, 1.0))
	_locomotion.add_knockback(resisted)


func _on_damaged(result: DamageResult) -> void:
	damaged.emit(result)
	# EventBus contract: exactly one enemy_damaged per ACCEPTED damage event. HealthComponent
	# emits its local `damaged` signal only on the accepted path, so this is exactly-once.
	var bus := _eb()
	if bus != null:
		bus.enemy_damaged.emit(self, result)
	if _feedback != null and _feedback.has_method("play_damaged"):
		_feedback.call("play_damaged")
	if _audio != null and _audio.has_method("play_hit"):
		_audio.call("play_hit")
	if result.was_critical:
		_juice_hitstop(0.03, 0.12)
	if not _alive:
		return
	# Poise: while a windup is guarded, chip damage accumulates instead of
	# interrupting; only breaking the budget (or an over-budget hit) staggers.
	if _poise_guard:
		var cfg := _config
		var budget := cfg.poise if cfg != null else 0.0
		if budget > 0.0:
			_poise_damage += result.final_amount
			if _poise_damage < budget:
				return
			_poise_damage = 0.0
	if _machine != null:
		_machine.force_state(&"hurt")


func _on_died() -> void:
	if _death_handled:
		return
	_death_handled = true
	_alive = false
	desired_dir = Vector3.ZERO
	desired_speed = 0.0
	clear_move_override()
	set_poise_guard(false)
	if _machine != null:
		_machine.force_state(&"dead")
	died.emit()
	var bus := _eb()
	if bus != null:
		bus.report_info("Enemy %s died" % String(_archetype_id))
		# Exactly-once score payload.
		bus.enemy_killed.emit(self, _archetype_id, _score_value, _currency_value)
	despawn_requested.emit(self)
	if _feedback != null and _feedback.has_method("play_died"):
		_feedback.call("play_died")
	if _audio != null and _audio.has_method("play_death"):
		_audio.call("play_death")
	_juice_hitstop(0.05, 0.2)
	_fade_and_free()


## Crit/death punch: micro-freeze + trauma through the run's HitstopManager.
func _juice_hitstop(duration: float, trauma: float) -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("hitstop_manager"):
		if node == null or not is_instance_valid(node):
			continue
		if node.has_method("request_hitstop"):
			node.call("request_hitstop", duration)
		if node.has_method("add_trauma"):
			node.call("add_trauma", trauma)


func _fade_and_free() -> void:
	if not is_inside_tree():
		queue_free()
		return
	# Slightly longer than the feedback sink so death animations get to land.
	var tween := create_tween()
	tween.tween_interval(0.8)
	tween.tween_callback(queue_free)


## ---------- Elite + boss-phase API (SpawnManager / BossController) ----------

## Mark this enemy elite with the given affixes (see EliteAffix). Visual tint
## blends the affixes; scale bumps slightly so elites read at a glance.
func set_elite(affixes: Array) -> void:
	_elite_affixes.clear()
	for raw in affixes:
		_elite_affixes.append(StringName(String(raw)))
	set_meta("elite_affixes", _elite_affixes.duplicate())
	var tint := Color.WHITE
	for affix in _elite_affixes:
		tint = tint.blend(EliteAffix.affix_tint(affix))
	if _feedback != null and _feedback.has_method("recolor"):
		_feedback.call("recolor", tint)
	_apply_visual_scale((_config.visual_scale if _config != null else 1.0) * 1.12)
	# Behavior affix hooks: VAMPIRIC elites sustain off the damage they deal.
	if EliteAffix.VAMPIRIC in _elite_affixes and not attack_hit.is_connected(_on_vampiric_hit):
		attack_hit.connect(_on_vampiric_hit)


func _on_vampiric_hit(_target: Node, result: DamageResult) -> void:
	if result == null or not result.accepted or not _alive:
		return
	if _health != null and _health.has_method("heal"):
		_health.call("heal", result.final_amount * EliteAffix.VAMPIRIC_HEAL_RATIO)


func is_elite() -> bool:
	return not _elite_affixes.is_empty()


func get_elite_affixes() -> Array:
	return _elite_affixes.duplicate()


## Boss phase bumps: multiply the CURRENT effective scales (stacks with wave
## scaling without touching the shared config).
func apply_phase_modifiers(damage_mult: float, speed_mult: float) -> void:
	_damage_scale *= maxf(damage_mult, 0.01)
	_speed_scale *= maxf(speed_mult, 0.01)


## StatusManager queries (tolerant when the scene has no StatusManager child).
func _status_node() -> Node:
	return get_node_or_null("StatusManager")


func _is_status_stunned() -> bool:
	var sm := _status_node()
	return sm != null and sm.has_method("is_stunned") and bool(sm.call("is_stunned"))


func _status_speed_factor() -> float:
	var sm := _status_node()
	if sm != null and sm.has_method("move_speed_factor"):
		return clampf(float(sm.call("move_speed_factor")), 0.0, 2.0)
	return 1.0


func get_health_fraction() -> float:
	if _health != null and _health.has_method("get_health_ratio"):
		return clampf(float(_health.call("get_health_ratio")), 0.0, 1.0)
	return 1.0 if _alive else 0.0


func get_debug_snapshot() -> Dictionary:
	var hp: Dictionary = {}
	if _health != null and _health.has_method("get_debug_snapshot"):
		hp = _health.call("get_debug_snapshot")
	return {
		"archetype": String(_archetype_id),
		"state": String(get_state()),
		"alive": _alive,
		"death_handled": _death_handled,
		"position": global_position,
		"health": hp,
		"desired_dir": desired_dir,
		"desired_speed": desired_speed,
		"move_override": _move_override_time > 0.0,
		"poise_guard": _poise_guard,
		"elite": is_elite(),
	}
